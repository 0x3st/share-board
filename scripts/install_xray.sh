#!/bin/bash

set -e

XRAY_VERSION="1.8.16"
INSTALL_DIR="/usr/local/xray"
CONFIG_DIR="/usr/local/etc/xray"
LOG_DIR="/var/log/xray"
SERVICE_FILE="/etc/systemd/system/xray.service"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Xray 一键安装配置脚本${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 权限运行此脚本${NC}"
    echo "使用: sudo $0"
    exit 1
fi

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        echo -e "${RED}无法检测操作系统${NC}"
        exit 1
    fi
    echo -e "${GREEN}检测到操作系统: $OS $VER${NC}"
}

install_dependencies() {
    echo -e "${YELLOW}安装依赖...${NC}"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update
        apt-get install -y curl wget unzip jq
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y curl wget unzip jq
    else
        echo -e "${RED}不支持的操作系统${NC}"
        exit 1
    fi
}

download_xray() {
    echo -e "${YELLOW}下载 Xray ${XRAY_VERSION}...${NC}"

    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            XRAY_ARCH="linux-64"
            ;;
        aarch64)
            XRAY_ARCH="linux-arm64-v8a"
            ;;
        armv7l)
            XRAY_ARCH="linux-arm32-v7a"
            ;;
        *)
            echo -e "${RED}不支持的架构: $ARCH${NC}"
            exit 1
            ;;
    esac

    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-${XRAY_ARCH}.zip"

    mkdir -p /tmp/xray-install
    cd /tmp/xray-install

    echo "下载地址: $DOWNLOAD_URL"
    wget -O xray.zip "$DOWNLOAD_URL" || {
        echo -e "${RED}下载失败，尝试使用代理...${NC}"
        wget -e use_proxy=yes -e https_proxy=127.0.0.1:7890 -O xray.zip "$DOWNLOAD_URL" || {
            echo -e "${RED}下载失败${NC}"
            exit 1
        }
    }

    unzip -o xray.zip
}

install_xray() {
    echo -e "${YELLOW}安装 Xray...${NC}"

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"

    cp xray "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/xray"

    ln -sf "$INSTALL_DIR/xray" /usr/local/bin/xray

    echo -e "${GREEN}Xray 安装完成${NC}"
    xray version
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

configure_xray() {
    echo -e "${YELLOW}配置 Xray...${NC}"
    echo ""

    read -p "请输入监听端口 (默认: 10086): " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-10086}

    read -p "请输入 gRPC API 端口 (默认: 10085): " API_PORT
    API_PORT=${API_PORT:-10085}

    echo ""
    echo "请选择入站协议:"
    echo "1) VMess"
    echo "2) VLESS"
    echo "3) Socks5"
    echo "4) HTTP"
    read -p "请选择 (1-4): " PROTOCOL_CHOICE

    case $PROTOCOL_CHOICE in
        1)
            PROTOCOL="vmess"
            ;;
        2)
            PROTOCOL="vless"
            ;;
        3)
            PROTOCOL="socks"
            ;;
        4)
            PROTOCOL="http"
            ;;
        *)
            echo -e "${RED}无效选择，使用默认 VMess${NC}"
            PROTOCOL="vmess"
            ;;
    esac

    UUID1=$(generate_uuid)
    UUID2=$(generate_uuid)
    UUID3=$(generate_uuid)

    echo ""
    echo -e "${GREEN}生成的 UUID:${NC}"
    echo "  用户1: $UUID1"
    echo "  用户2: $UUID2"
    echo "  用户3: $UUID3"
    echo ""

    read -p "是否启用 WebSocket 传输? (y/n, 默认: n): " ENABLE_WS
    ENABLE_WS=${ENABLE_WS:-n}

    if [ "$ENABLE_WS" = "y" ]; then
        read -p "请输入 WebSocket 路径 (默认: /): " WS_PATH
        WS_PATH=${WS_PATH:-/}
    fi

    read -p "是否启用 TLS? (y/n, 默认: n): " ENABLE_TLS
    ENABLE_TLS=${ENABLE_TLS:-n}

    if [ "$ENABLE_TLS" = "y" ]; then
        read -p "请输入证书文件路径: " CERT_FILE
        read -p "请输入密钥文件路径: " KEY_FILE
    fi

    echo ""
    echo "是否配置上游代理?"
    echo "1) 不使用代理 (直连)"
    echo "2) HTTP 代理"
    echo "3) SOCKS5 代理"
    read -p "请选择 (1-3, 默认: 1): " PROXY_CHOICE
    PROXY_CHOICE=${PROXY_CHOICE:-1}

    if [ "$PROXY_CHOICE" = "2" ]; then
        read -p "请输入 HTTP 代理地址 (例如: 127.0.0.1:7890): " PROXY_ADDR
        PROXY_PROTOCOL="http"
    elif [ "$PROXY_CHOICE" = "3" ]; then
        read -p "请输入 SOCKS5 代理地址 (例如: 127.0.0.1:1080): " PROXY_ADDR
        PROXY_PROTOCOL="socks"
    fi

    generate_config
}

generate_config() {
    echo -e "${YELLOW}生成配置文件...${NC}"

    INBOUND_SETTINGS=""
    STREAM_SETTINGS=""

    if [ "$PROTOCOL" = "vmess" ]; then
        INBOUND_SETTINGS=$(cat <<EOF
      "settings": {
        "clients": [
          {
            "id": "$UUID1",
            "email": "user1@example.com",
            "alterId": 0
          },
          {
            "id": "$UUID2",
            "email": "user2@example.com",
            "alterId": 0
          },
          {
            "id": "$UUID3",
            "email": "user3@example.com",
            "alterId": 0
          }
        ]
      }
EOF
)
    elif [ "$PROTOCOL" = "vless" ]; then
        INBOUND_SETTINGS=$(cat <<EOF
      "settings": {
        "clients": [
          {
            "id": "$UUID1",
            "email": "user1@example.com"
          },
          {
            "id": "$UUID2",
            "email": "user2@example.com"
          },
          {
            "id": "$UUID3",
            "email": "user3@example.com"
          }
        ],
        "decryption": "none"
      }
EOF
)
    elif [ "$PROTOCOL" = "socks" ]; then
        INBOUND_SETTINGS=$(cat <<EOF
      "settings": {
        "auth": "noauth",
        "udp": true
      }
EOF
)
    elif [ "$PROTOCOL" = "http" ]; then
        INBOUND_SETTINGS=$(cat <<EOF
      "settings": {}
EOF
)
    fi

    if [ "$ENABLE_WS" = "y" ]; then
        if [ "$ENABLE_TLS" = "y" ]; then
            STREAM_SETTINGS=$(cat <<EOF
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$WS_PATH"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
          ]
        }
      }
EOF
)
        else
            STREAM_SETTINGS=$(cat <<EOF
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$WS_PATH"
        }
      }
EOF
)
        fi
    fi

    OUTBOUND_CONFIG=""
    if [ "$PROXY_CHOICE" = "2" ] || [ "$PROXY_CHOICE" = "3" ]; then
        PROXY_HOST=$(echo $PROXY_ADDR | cut -d: -f1)
        PROXY_PORT=$(echo $PROXY_ADDR | cut -d: -f2)

        OUTBOUND_CONFIG=$(cat <<EOF
    {
      "protocol": "$PROXY_PROTOCOL",
      "tag": "proxy",
      "settings": {
        "servers": [
          {
            "address": "$PROXY_HOST",
            "port": $PROXY_PORT
          }
        ]
      }
    },
EOF
)
    fi

    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_DIR/access.log",
    "error": "$LOG_DIR/error.log"
  },
  "api": {
    "tag": "api",
    "services": [
      "StatsService"
    ]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "tag": "api",
      "listen": "127.0.0.1",
      "port": $API_PORT,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    },
    {
      "tag": "main-in",
      "port": $LISTEN_PORT,
      "protocol": "$PROTOCOL",
$INBOUND_SETTINGS$([ -n "$STREAM_SETTINGS" ] && echo "," || echo "")
$STREAM_SETTINGS
    }
  ],
  "outbounds": [
$OUTBOUND_CONFIG
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

    echo -e "${GREEN}配置文件已生成: $CONFIG_DIR/config.json${NC}"
}

create_systemd_service() {
    echo -e "${YELLOW}创建 systemd 服务...${NC}"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$INSTALL_DIR/xray run -config $CONFIG_DIR/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray

    echo -e "${GREEN}systemd 服务已创建${NC}"
}

save_info() {
    INFO_FILE="$CONFIG_DIR/install_info.txt"

    cat > "$INFO_FILE" <<EOF
Xray 安装信息
=====================================
安装时间: $(date)
Xray 版本: $XRAY_VERSION
安装目录: $INSTALL_DIR
配置目录: $CONFIG_DIR
日志目录: $LOG_DIR

服务配置
=====================================
监听端口: $LISTEN_PORT
gRPC API 端口: $API_PORT
协议: $PROTOCOL

用户信息
=====================================
用户1 UUID: $UUID1
用户1 Email: user1@example.com

用户2 UUID: $UUID2
用户2 Email: user2@example.com

用户3 UUID: $UUID3
用户3 Email: user3@example.com

$(if [ "$ENABLE_WS" = "y" ]; then
    echo "WebSocket 路径: $WS_PATH"
fi)

$(if [ "$ENABLE_TLS" = "y" ]; then
    echo "TLS: 已启用"
    echo "证书文件: $CERT_FILE"
    echo "密钥文件: $KEY_FILE"
fi)

$(if [ "$PROXY_CHOICE" != "1" ]; then
    echo "上游代理: $PROXY_PROTOCOL://$PROXY_ADDR"
fi)

常用命令
=====================================
启动服务: systemctl start xray
停止服务: systemctl stop xray
重启服务: systemctl restart xray
查看状态: systemctl status xray
查看日志: journalctl -u xray -f
测试配置: xray -test -config $CONFIG_DIR/config.json

配置文件: $CONFIG_DIR/config.json
EOF

    echo -e "${GREEN}安装信息已保存到: $INFO_FILE${NC}"
}

start_xray() {
    echo -e "${YELLOW}启动 Xray 服务...${NC}"

    xray -test -config "$CONFIG_DIR/config.json" || {
        echo -e "${RED}配置文件测试失败${NC}"
        exit 1
    }

    systemctl start xray
    sleep 2

    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}Xray 服务启动成功！${NC}"
    else
        echo -e "${RED}Xray 服务启动失败${NC}"
        echo "查看日志: journalctl -u xray -n 50"
        exit 1
    fi
}

show_summary() {
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}   Xray 安装完成！${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo -e "${YELLOW}服务信息:${NC}"
    echo "  监听端口: $LISTEN_PORT"
    echo "  gRPC API: 127.0.0.1:$API_PORT"
    echo "  协议: $PROTOCOL"
    echo ""
    echo -e "${YELLOW}用户信息:${NC}"
    echo "  用户1: $UUID1 (user1@example.com)"
    echo "  用户2: $UUID2 (user2@example.com)"
    echo "  用户3: $UUID3 (user3@example.com)"
    echo ""
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  查看状态: systemctl status xray"
    echo "  查看日志: journalctl -u xray -f"
    echo "  重启服务: systemctl restart xray"
    echo ""
    echo -e "${YELLOW}详细信息:${NC}"
    echo "  $CONFIG_DIR/install_info.txt"
    echo ""
    echo -e "${GREEN}=========================================${NC}"
}

main() {
    detect_os
    install_dependencies
    download_xray
    install_xray
    configure_xray
    create_systemd_service
    save_info
    start_xray
    show_summary

    cd /
    rm -rf /tmp/xray-install
}

main
