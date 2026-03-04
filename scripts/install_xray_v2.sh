#!/bin/bash

set -euo pipefail

# 设置安全的文件权限掩码
umask 077

XRAY_VERSION="1.8.16"
INSTALL_DIR="/usr/local/xray"
CONFIG_DIR="/usr/local/etc/xray"
LOG_DIR="/var/log/xray"
SERVICE_FILE="/etc/systemd/system/xray.service"

# 清理临时文件的trap
cleanup() {
    if [ -n "${REALITY_KEYS_FILE:-}" ] && [ -f "$REALITY_KEYS_FILE" ]; then
        rm -f "$REALITY_KEYS_FILE"
    fi
    if [ -n "${WORKDIR:-}" ] && [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Xray 一键安装配置脚本 v2.0${NC}"
echo -e "${GREEN}   支持 VLESS+Reality${NC}"
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
        apt-get install -y curl wget unzip jq openssl
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y curl wget unzip jq openssl
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

    # 使用安全的临时目录
    WORKDIR=$(mktemp -d /tmp/xray-install.XXXXXX)
    cd "$WORKDIR"

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

    # 复制二进制文件
    cp xray "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/xray"

    # 复制 geoip.dat 和 geosite.dat（路由规则必需）
    if [ -f "geoip.dat" ]; then
        cp geoip.dat "$INSTALL_DIR/"
        echo -e "${GREEN}geoip.dat 已安装${NC}"
    else
        echo -e "${YELLOW}警告: geoip.dat 不存在，将从 GitHub 下载...${NC}"
        wget -O "$INSTALL_DIR/geoip.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" || \
        wget -e use_proxy=yes -e https_proxy=127.0.0.1:7890 -O "$INSTALL_DIR/geoip.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    fi

    if [ -f "geosite.dat" ]; then
        cp geosite.dat "$INSTALL_DIR/"
        echo -e "${GREEN}geosite.dat 已安装${NC}"
    else
        echo -e "${YELLOW}警告: geosite.dat 不存在，将从 GitHub 下载...${NC}"
        wget -O "$INSTALL_DIR/geosite.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" || \
        wget -e use_proxy=yes -e https_proxy=127.0.0.1:7890 -O "$INSTALL_DIR/geosite.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    fi

    ln -sf "$INSTALL_DIR/xray" /usr/local/bin/xray

    echo -e "${GREEN}Xray 安装完成${NC}"
    xray version
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

generate_reality_keys() {
    # 使用安全的临时文件存储密钥
    REALITY_KEYS_FILE=$(mktemp /tmp/xray_reality_keys.XXXXXX)
    chmod 600 "$REALITY_KEYS_FILE"

    if ! xray x25519 > "$REALITY_KEYS_FILE" 2>&1; then
        echo -e "${RED}生成Reality密钥失败${NC}"
        rm -f "$REALITY_KEYS_FILE"
        exit 1
    fi

    # 验证密钥文件非空
    if [ ! -s "$REALITY_KEYS_FILE" ]; then
        echo -e "${RED}Reality密钥文件为空${NC}"
        rm -f "$REALITY_KEYS_FILE"
        exit 1
    fi
}

configure_xray() {
    echo -e "${YELLOW}配置 Xray...${NC}"
    echo ""

    read -p "请输入监听端口 (默认: 443): " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-443}

    read -p "请输入 gRPC API 端口 (默认: 10085): " API_PORT
    API_PORT=${API_PORT:-10085}

    echo ""
    echo "请选择入站协议:"
    echo "1) VLESS+Reality (推荐，最安全)"
    echo "2) VLESS+TLS"
    echo "3) VMess+WebSocket+TLS"
    echo "4) Socks5"
    echo "5) HTTP"
    read -p "请选择 (1-5): " PROTOCOL_CHOICE

    case $PROTOCOL_CHOICE in
        1)
            PROTOCOL="vless-reality"
            configure_reality
            ;;
        2)
            PROTOCOL="vless-tls"
            configure_tls
            ;;
        3)
            PROTOCOL="vmess-ws-tls"
            configure_vmess_ws_tls
            ;;
        4)
            PROTOCOL="socks"
            ;;
        5)
            PROTOCOL="http"
            ;;
        *)
            echo -e "${RED}无效选择，使用默认 VLESS+Reality${NC}"
            PROTOCOL="vless-reality"
            configure_reality
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

    echo "是否配置上游代理?"
    echo "1) 不使用代理 (直连)"
    echo "2) HTTP 代理"
    echo "3) SOCKS5 代理"
    read -p "请选择 (1-3, 默认: 1): " PROXY_CHOICE
    PROXY_CHOICE=${PROXY_CHOICE:-1}

    if [ "$PROXY_CHOICE" = "2" ]; then
        read -p "请输入 HTTP 代理地址 (例如: 127.0.0.1:7890): " PROXY_ADDR
        PROXY_PROTOCOL="http"

        read -p "代理是否需要认证? (y/n, 默认: n): " PROXY_AUTH
        if [ "$PROXY_AUTH" = "y" ]; then
            read -p "请输入代理用户名: " PROXY_USER
            read -sp "请输入代理密码: " PROXY_PASS
            echo ""
        fi
    elif [ "$PROXY_CHOICE" = "3" ]; then
        read -p "请输入 SOCKS5 代理地址 (例如: 127.0.0.1:1080): " PROXY_ADDR
        PROXY_PROTOCOL="socks"

        read -p "代理是否需要认证? (y/n, 默认: n): " PROXY_AUTH
        if [ "$PROXY_AUTH" = "y" ]; then
            read -p "请输入代理用户名: " PROXY_USER
            read -sp "请输入代理密码: " PROXY_PASS
            echo ""
        fi
    fi

    generate_config
}

configure_reality() {
    echo ""
    echo -e "${YELLOW}配置 Reality...${NC}"

    read -p "请输入目标网站 SNI (默认: www.microsoft.com): " REALITY_DEST
    REALITY_DEST=${REALITY_DEST:-www.microsoft.com}

    read -p "请输入 serverNames (默认: microsoft.com): " REALITY_SERVER_NAMES
    REALITY_SERVER_NAMES=${REALITY_SERVER_NAMES:-microsoft.com}

    echo "生成 Reality 密钥对..."
    generate_reality_keys

    # 从安全的临时文件读取密钥
    REALITY_PRIVATE_KEY=$(grep "Private key:" "$REALITY_KEYS_FILE" | awk '{print $3}')
    REALITY_PUBLIC_KEY=$(grep "Public key:" "$REALITY_KEYS_FILE" | awk '{print $3}')

    # 验证密钥非空
    if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
        echo -e "${RED}Reality密钥提取失败${NC}"
        exit 1
    fi

    REALITY_SHORT_IDS='["", "0123456789abcdef"]'

    echo -e "${GREEN}Reality 配置完成${NC}"
    echo "  Private Key: $REALITY_PRIVATE_KEY"
    echo "  Public Key: $REALITY_PUBLIC_KEY"
}

configure_tls() {
    echo ""
    read -p "请输入证书文件路径: " CERT_FILE
    read -p "请输入密钥文件路径: " KEY_FILE
}

configure_vmess_ws_tls() {
    echo ""
    read -p "请输入 WebSocket 路径 (默认: /): " WS_PATH
    WS_PATH=${WS_PATH:-/}

    read -p "请输入证书文件路径: " CERT_FILE
    read -p "请输入密钥文件路径: " KEY_FILE
}

generate_config() {
    echo -e "${YELLOW}生成配置文件...${NC}"

    if [ "$PROTOCOL" = "vless-reality" ]; then
        generate_vless_reality_config
    elif [ "$PROTOCOL" = "vless-tls" ]; then
        generate_vless_tls_config
    elif [ "$PROTOCOL" = "vmess-ws-tls" ]; then
        generate_vmess_ws_tls_config
    elif [ "$PROTOCOL" = "socks" ]; then
        generate_socks_config
    elif [ "$PROTOCOL" = "http" ]; then
        generate_http_config
    fi

    # 设置配置文件安全权限（仅root可读写）
    chmod 600 "$CONFIG_DIR/config.json"
    echo -e "${GREEN}配置文件已生成: $CONFIG_DIR/config.json${NC}"

    echo "验证配置文件..."
    if xray -test -config "$CONFIG_DIR/config.json"; then
        echo -e "${GREEN}配置文件验证通过！${NC}"
    else
        echo -e "${RED}配置文件验证失败！${NC}"
        exit 1
    fi
}

generate_vless_reality_config() {
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_DIR/access.log",
    "error": "$LOG_DIR/error.log"
  },
  "api": {
    "tag": "api",
    "services": ["StatsService"]
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
      "tag": "vless-reality",
      "port": $LISTEN_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID1",
            "email": "user1@example.com",
            "flow": "xtls-rprx-vision"
          },
          {
            "id": "$UUID2",
            "email": "user2@example.com",
            "flow": "xtls-rprx-vision"
          },
          {
            "id": "$UUID3",
            "email": "user3@example.com",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DEST:443",
          "xver": 0,
          "serverNames": ["$REALITY_SERVER_NAMES"],
          "privateKey": "$REALITY_PRIVATE_KEY",
          "shortIds": $REALITY_SHORT_IDS
        }
      }
    }
  ],
  "outbounds": [
$(generate_outbound_config)
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
}

generate_vless_tls_config() {
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_DIR/access.log",
    "error": "$LOG_DIR/error.log"
  },
  "api": {
    "tag": "api",
    "services": ["StatsService"]
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
      "tag": "vless-tls",
      "port": $LISTEN_PORT,
      "protocol": "vless",
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
      },
      "streamSettings": {
        "network": "tcp",
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
    }
  ],
  "outbounds": [
$(generate_outbound_config)
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
}

generate_vmess_ws_tls_config() {
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_DIR/access.log",
    "error": "$LOG_DIR/error.log"
  },
  "api": {
    "tag": "api",
    "services": ["StatsService"]
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
      "tag": "vmess-ws-tls",
      "port": $LISTEN_PORT,
      "protocol": "vmess",
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
      },
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
    }
  ],
  "outbounds": [
$(generate_outbound_config)
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
}

generate_socks_config() {
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_DIR/access.log",
    "error": "$LOG_DIR/error.log"
  },
  "api": {
    "tag": "api",
    "services": ["StatsService"]
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
      "tag": "socks",
      "port": $LISTEN_PORT,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
$(generate_outbound_config)
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
}

generate_http_config() {
    cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_DIR/access.log",
    "error": "$LOG_DIR/error.log"
  },
  "api": {
    "tag": "api",
    "services": ["StatsService"]
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
      "tag": "http",
      "port": $LISTEN_PORT,
      "protocol": "http",
      "settings": {}
    }
  ],
  "outbounds": [
$(generate_outbound_config)
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
}

generate_outbound_config() {
    if [ "$PROXY_CHOICE" = "2" ] || [ "$PROXY_CHOICE" = "3" ]; then
        PROXY_HOST=$(echo $PROXY_ADDR | cut -d: -f1)
        PROXY_PORT=$(echo $PROXY_ADDR | cut -d: -f2)

        if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
            # 带认证的代理配置
            cat <<EOF
    {
      "protocol": "$PROXY_PROTOCOL",
      "tag": "proxy",
      "settings": {
        "servers": [
          {
            "address": "$PROXY_HOST",
            "port": $PROXY_PORT,
            "users": [
              {
                "user": "$PROXY_USER",
                "pass": "$PROXY_PASS"
              }
            ]
          }
        ]
      }
    },
EOF
        else
            # 无认证的代理配置
            cat <<EOF
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
        fi
    fi
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

EOF

    if [ "$PROTOCOL" = "vless-reality" ]; then
        cat >> "$INFO_FILE" <<EOF
Reality 配置
=====================================
Private Key: $REALITY_PRIVATE_KEY
Public Key: $REALITY_PUBLIC_KEY
Server Names: $REALITY_SERVER_NAMES
Dest: $REALITY_DEST:443
Short IDs: $REALITY_SHORT_IDS

EOF
    fi

    if [ "$PROXY_CHOICE" != "1" ]; then
        cat >> "$INFO_FILE" <<EOF
上游代理: $PROXY_PROTOCOL://$PROXY_ADDR

EOF
    fi

    cat >> "$INFO_FILE" <<EOF
常用命令
=====================================
启动服务: systemctl start xray
停止服务: systemctl stop xray
重启服务: systemctl restart xray
查看状态: systemctl status xray
查看日志: journalctl -u xray -f
测试配置: xray -test -config $CONFIG_DIR/config.json

配置文件: $CONFIG_DIR/config.json

用户管理
=====================================
添加用户: $INSTALL_DIR/../scripts/manage_xray_users.sh add
删除用户: $INSTALL_DIR/../scripts/manage_xray_users.sh del
列出用户: $INSTALL_DIR/../scripts/manage_xray_users.sh list
EOF

    echo -e "${GREEN}安装信息已保存到: $INFO_FILE${NC}"
}

start_xray() {
    echo -e "${YELLOW}启动 Xray 服务...${NC}"

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

    if [ "$PROTOCOL" = "vless-reality" ]; then
        echo -e "${YELLOW}Reality 配置:${NC}"
        echo "  Public Key: $REALITY_PUBLIC_KEY"
        echo "  Server Names: $REALITY_SERVER_NAMES"
        echo ""
    fi

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
}

main
