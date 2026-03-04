#!/bin/bash

set -e

CONFIG_FILE="/usr/local/etc/xray/config.json"
BACKUP_DIR="/usr/local/etc/xray/backups"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        echo "使用: sudo $0"
        exit 1
    fi
}

check_dependencies() {
    if ! command -v jq &> /dev/null; then
        log_warn "jq 未安装，正在安装..."
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
                apt-get update && apt-get install -y jq
            elif [ "$ID" = "centos" ] || [ "$ID" = "rhel" ]; then
                yum install -y jq
            fi
        fi
    fi

    if ! command -v xray &> /dev/null; then
        log_error "Xray 未安装"
        exit 1
    fi
}

backup_config() {
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/config_$(date +%Y%m%d_%H%M%S).json"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    log_info "配置已备份到: $BACKUP_FILE"
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

get_inbound_tag() {
    jq -r '.inbounds[] | select(.protocol != "dokodemo-door") | .tag' "$CONFIG_FILE" | head -1
}

get_inbound_protocol() {
    jq -r '.inbounds[] | select(.protocol != "dokodemo-door") | .protocol' "$CONFIG_FILE" | head -1
}

list_users() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   当前用户列表${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    PROTOCOL=$(get_inbound_protocol)
    INBOUND_TAG=$(get_inbound_tag)

    if [ -z "$PROTOCOL" ]; then
        log_error "未找到有效的入站配置"
        exit 1
    fi

    log_info "协议: $PROTOCOL"
    log_info "入站标签: $INBOUND_TAG"
    echo ""

    USERS=$(jq -r ".inbounds[] | select(.tag == \"$INBOUND_TAG\") | .settings.clients[] | \"\(.email) | \(.id)\"" "$CONFIG_FILE")

    if [ -z "$USERS" ]; then
        log_warn "暂无用户"
        return
    fi

    echo -e "${YELLOW}Email${NC}                    ${YELLOW}UUID${NC}"
    echo "---------------------------------------------------------------------"
    echo "$USERS" | while IFS='|' read -r email uuid; do
        echo -e "${GREEN}$(echo $email | xargs)${NC}  $(echo $uuid | xargs)"
    done
    echo ""
}

add_user() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   添加新用户${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    read -p "请输入用户邮箱 (例如: user@example.com): " EMAIL
    if [ -z "$EMAIL" ]; then
        log_error "邮箱不能为空"
        exit 1
    fi

    PROTOCOL=$(get_inbound_protocol)
    INBOUND_TAG=$(get_inbound_tag)

    EXISTING=$(jq -r ".inbounds[] | select(.tag == \"$INBOUND_TAG\") | .settings.clients[] | select(.email == \"$EMAIL\") | .email" "$CONFIG_FILE")
    if [ -n "$EXISTING" ]; then
        log_error "用户 $EMAIL 已存在"
        exit 1
    fi

    UUID=$(generate_uuid)
    log_info "生成的 UUID: $UUID"

    backup_config

    if [ "$PROTOCOL" = "vmess" ]; then
        NEW_CLIENT=$(cat <<EOF
{
  "id": "$UUID",
  "email": "$EMAIL",
  "alterId": 0
}
EOF
)
    elif [ "$PROTOCOL" = "vless" ]; then
        FLOW=$(jq -r ".inbounds[] | select(.tag == \"$INBOUND_TAG\") | .settings.clients[0].flow // empty" "$CONFIG_FILE")
        if [ -n "$FLOW" ]; then
            NEW_CLIENT=$(cat <<EOF
{
  "id": "$UUID",
  "email": "$EMAIL",
  "flow": "$FLOW"
}
EOF
)
        else
            NEW_CLIENT=$(cat <<EOF
{
  "id": "$UUID",
  "email": "$EMAIL"
}
EOF
)
        fi
    else
        log_error "不支持的协议: $PROTOCOL"
        exit 1
    fi

    TMP_FILE=$(mktemp)
    jq ".inbounds |= map(if .tag == \"$INBOUND_TAG\" then .settings.clients += [$NEW_CLIENT] else . end)" "$CONFIG_FILE" > "$TMP_FILE"

    if xray -test -config "$TMP_FILE" > /dev/null 2>&1; then
        mv "$TMP_FILE" "$CONFIG_FILE"
        log_info "用户添加成功！"
        echo ""
        echo -e "${GREEN}用户信息:${NC}"
        echo "  Email: $EMAIL"
        echo "  UUID: $UUID"
        echo ""

        read -p "是否重启 Xray 服务使配置生效? (y/n): " RESTART
        if [ "$RESTART" = "y" ]; then
            systemctl restart xray
            if systemctl is-active --quiet xray; then
                log_info "Xray 服务已重启"
            else
                log_error "Xray 服务重启失败"
                log_error "查看日志: journalctl -u xray -n 50"
            fi
        fi
    else
        rm -f "$TMP_FILE"
        log_error "配置文件验证失败，未应用更改"
        exit 1
    fi
}

delete_user() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   删除用户${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    list_users

    read -p "请输入要删除的用户邮箱: " EMAIL
    if [ -z "$EMAIL" ]; then
        log_error "邮箱不能为空"
        exit 1
    fi

    INBOUND_TAG=$(get_inbound_tag)

    EXISTING=$(jq -r ".inbounds[] | select(.tag == \"$INBOUND_TAG\") | .settings.clients[] | select(.email == \"$EMAIL\") | .email" "$CONFIG_FILE")
    if [ -z "$EXISTING" ]; then
        log_error "用户 $EMAIL 不存在"
        exit 1
    fi

    read -p "确认删除用户 $EMAIL? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log_info "取消删除"
        exit 0
    fi

    backup_config

    TMP_FILE=$(mktemp)
    jq ".inbounds |= map(if .tag == \"$INBOUND_TAG\" then .settings.clients |= map(select(.email != \"$EMAIL\")) else . end)" "$CONFIG_FILE" > "$TMP_FILE"

    if xray -test -config "$TMP_FILE" > /dev/null 2>&1; then
        mv "$TMP_FILE" "$CONFIG_FILE"
        log_info "用户删除成功！"

        read -p "是否重启 Xray 服务使配置生效? (y/n): " RESTART
        if [ "$RESTART" = "y" ]; then
            systemctl restart xray
            if systemctl is-active --quiet xray; then
                log_info "Xray 服务已重启"
            else
                log_error "Xray 服务重启失败"
                log_error "查看日志: journalctl -u xray -n 50"
            fi
        fi
    else
        rm -f "$TMP_FILE"
        log_error "配置文件验证失败，未应用更改"
        exit 1
    fi
}

show_user_info() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   查看用户详情${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    list_users

    read -p "请输入用户邮箱: " EMAIL
    if [ -z "$EMAIL" ]; then
        log_error "邮箱不能为空"
        exit 1
    fi

    INBOUND_TAG=$(get_inbound_tag)
    USER_INFO=$(jq -r ".inbounds[] | select(.tag == \"$INBOUND_TAG\") | .settings.clients[] | select(.email == \"$EMAIL\")" "$CONFIG_FILE")

    if [ -z "$USER_INFO" ]; then
        log_error "用户 $EMAIL 不存在"
        exit 1
    fi

    echo ""
    echo -e "${GREEN}用户详情:${NC}"
    echo "$USER_INFO" | jq .
    echo ""
}

restore_backup() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   恢复备份${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "备份目录不存在"
        exit 1
    fi

    BACKUPS=$(ls -t "$BACKUP_DIR"/config_*.json 2>/dev/null)
    if [ -z "$BACKUPS" ]; then
        log_error "没有可用的备份"
        exit 1
    fi

    echo "可用的备份:"
    echo ""
    select BACKUP_FILE in $BACKUPS "取消"; do
        if [ "$BACKUP_FILE" = "取消" ]; then
            log_info "取消恢复"
            exit 0
        elif [ -n "$BACKUP_FILE" ]; then
            read -p "确认恢复备份 $(basename $BACKUP_FILE)? (yes/no): " CONFIRM
            if [ "$CONFIRM" = "yes" ]; then
                cp "$BACKUP_FILE" "$CONFIG_FILE"
                log_info "配置已恢复"

                read -p "是否重启 Xray 服务? (y/n): " RESTART
                if [ "$RESTART" = "y" ]; then
                    systemctl restart xray
                    if systemctl is-active --quiet xray; then
                        log_info "Xray 服务已重启"
                    else
                        log_error "Xray 服务重启失败"
                    fi
                fi
            fi
            break
        fi
    done
}

show_menu() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   Xray 用户管理${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo "1) 列出所有用户"
    echo "2) 添加用户"
    echo "3) 删除用户"
    echo "4) 查看用户详情"
    echo "5) 恢复备份"
    echo "6) 退出"
    echo ""
    read -p "请选择操作 (1-6): " CHOICE

    case $CHOICE in
        1)
            list_users
            ;;
        2)
            add_user
            ;;
        3)
            delete_user
            ;;
        4)
            show_user_info
            ;;
        5)
            restore_backup
            ;;
        6)
            exit 0
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

main() {
    check_root
    check_dependencies

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi

    if [ "$1" = "list" ]; then
        list_users
    elif [ "$1" = "add" ]; then
        add_user
    elif [ "$1" = "del" ]; then
        delete_user
    else
        while true; do
            show_menu
            echo ""
            read -p "按 Enter 继续..."
        done
    fi
}

main "$@"
