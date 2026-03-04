#!/bin/bash

set -euo pipefail

# 颜色定义
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

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root用户运行此脚本"
        log_error "使用: sudo $0"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi

    log_info "检测到操作系统: $OS $OS_VERSION"
}

# 检查3x-ui是否已安装
check_3xui_installed() {
    if [ -f "/usr/local/x-ui/bin/xray-linux-amd64" ] || [ -f "/usr/local/x-ui/x-ui" ]; then
        return 0
    else
        return 1
    fi
}

# 获取3x-ui当前版本
get_current_version() {
    if [ -f "/usr/local/x-ui/bin/version.txt" ]; then
        cat /usr/local/x-ui/bin/version.txt
    else
        echo "unknown"
    fi
}

# 获取3x-ui最新版本
get_latest_version() {
    curl -s https://api.github.com/repos/MHSanaei/3x-ui/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

# 安装3x-ui
install_3xui() {
    log_info "开始安装3x-ui..."

    # 下载并执行官方安装脚本
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

    if [ $? -eq 0 ]; then
        log_info "3x-ui 安装成功"
    else
        log_error "3x-ui 安装失败"
        exit 1
    fi
}

# 升级3x-ui
upgrade_3xui() {
    log_info "开始升级3x-ui..."

    # 使用官方更新脚本
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) update

    if [ $? -eq 0 ]; then
        log_info "3x-ui 升级成功"
    else
        log_error "3x-ui 升级失败"
        exit 1
    fi
}

# 配置3x-ui
configure_3xui() {
    log_info "配置3x-ui..."

    # 检查配置文件是否存在
    if [ ! -f "/etc/x-ui/x-ui.db" ]; then
        log_warn "3x-ui配置文件不存在，将使用默认配置"
    fi

    # 启动3x-ui服务
    systemctl enable x-ui
    systemctl start x-ui

    # 等待服务启动
    sleep 3

    # 检查服务状态
    if systemctl is-active --quiet x-ui; then
        log_info "3x-ui 服务启动成功"
    else
        log_error "3x-ui 服务启动失败"
        log_error "查看日志: journalctl -u x-ui -n 50"
        exit 1
    fi
}

# 显示访问信息
show_access_info() {
    local IP=$(curl -s ifconfig.me || echo "YOUR_SERVER_IP")
    local PORT=$(grep -oP '(?<="Port":)\d+' /etc/x-ui/x-ui.db 2>/dev/null || echo "2053")

    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   3x-ui 安装完成${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo -e "${GREEN}访问地址:${NC} http://$IP:$PORT"
    echo -e "${GREEN}默认用户名:${NC} admin"
    echo -e "${GREEN}默认密码:${NC} admin"
    echo ""
    echo -e "${YELLOW}重要提示:${NC}"
    echo "1. 请立即登录并修改默认密码"
    echo "2. 建议配置SSL证书以启用HTTPS"
    echo "3. 管理命令: x-ui"
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo ""
}

# 主函数
main() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   3x-ui 自动安装/升级脚本${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    check_root
    detect_os

    if check_3xui_installed; then
        CURRENT_VERSION=$(get_current_version)
        LATEST_VERSION=$(get_latest_version)

        log_info "检测到已安装3x-ui"
        log_info "当前版本: $CURRENT_VERSION"
        log_info "最新版本: $LATEST_VERSION"

        if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
            log_info "已是最新版本，无需升级"

            # 检查服务状态
            if systemctl is-active --quiet x-ui; then
                log_info "3x-ui 服务正在运行"
            else
                log_warn "3x-ui 服务未运行，正在启动..."
                systemctl start x-ui
            fi
        else
            log_warn "发现新版本: $LATEST_VERSION"
            read -p "是否升级? (y/n): " UPGRADE
            if [ "$UPGRADE" = "y" ] || [ "$UPGRADE" = "Y" ]; then
                upgrade_3xui
                configure_3xui
            else
                log_info "跳过升级"
            fi
        fi
    else
        log_info "未检测到3x-ui，开始安装..."
        install_3xui
        configure_3xui
        show_access_info
    fi

    echo ""
    log_info "完成！"
}

main "$@"
