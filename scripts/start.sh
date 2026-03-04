#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$PROJECT_ROOT/backend"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BACKEND_PID_FILE="/tmp/xray-monitor-backend.pid"
FRONTEND_PID_FILE="/tmp/xray-monitor-frontend.pid"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    log_info "检查并安装依赖..."

    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi

    # 检查是否为 root 用户，决定是否使用 sudo
    if [ "$EUID" -eq 0 ]; then
        SUDO_CMD=""
    else
        if ! command -v sudo &> /dev/null; then
            log_error "sudo 未安装且当前不是 root 用户"
            log_error "请以 root 用户运行或安装 sudo"
            exit 1
        fi
        SUDO_CMD="sudo"
    fi

    # 首先检查并安装必要的基础工具（在使用前）
    local missing_tools=()

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi

    if ! command -v sqlite3 &> /dev/null; then
        missing_tools+=("sqlite3")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_warn "缺少工具: ${missing_tools[*]}，正在安装..."
        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            $SUDO_CMD apt-get update
            $SUDO_CMD apt-get install -y "${missing_tools[@]}"
        elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
            $SUDO_CMD yum install -y "${missing_tools[@]}"
        fi
    fi

    # 检查并安装 Python3
    if ! command -v python3 &> /dev/null; then
        log_warn "Python3 未安装，正在安装..."
        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            $SUDO_CMD apt-get update
            $SUDO_CMD apt-get install -y python3
        elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
            $SUDO_CMD yum install -y python3
        else
            log_error "不支持的操作系统: $OS"
            exit 1
        fi
    fi

    # 检查并安装 uv (现代化的Python包管理工具)
    if ! command -v uv &> /dev/null; then
        log_warn "uv 未安装，正在安装..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        # 添加uv到当前会话的PATH
        export PATH="$HOME/.cargo/bin:$PATH"
        if ! command -v uv &> /dev/null; then
            log_error "uv 安装失败，请手动安装: curl -LsSf https://astral.sh/uv/install.sh | sh"
            exit 1
        fi
    fi

    # 检查并安装 Node.js
    if ! command -v node &> /dev/null; then
        log_warn "Node.js 未安装，正在安装..."
        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            # 安装 NodeSource 仓库（Node.js 20.x LTS）
            curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO_CMD -E bash -
            $SUDO_CMD apt-get install -y nodejs
        elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
            curl -fsSL https://rpm.nodesource.com/setup_20.x | $SUDO_CMD bash -
            $SUDO_CMD yum install -y nodejs
        else
            log_error "不支持的操作系统: $OS"
            exit 1
        fi
    else
        # 检查现有版本，如果是18.x则提示升级
        NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$NODE_VERSION" -lt 20 ]; then
            log_warn "检测到 Node.js $NODE_VERSION.x，建议升级到 20.x LTS"
            read -p "是否现在升级? (y/n): " UPGRADE
            if [ "$UPGRADE" = "y" ]; then
                if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
                    curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO_CMD -E bash -
                    $SUDO_CMD apt-get install -y nodejs
                elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
                    curl -fsSL https://rpm.nodesource.com/setup_20.x | $SUDO_CMD bash -
                    $SUDO_CMD yum install -y nodejs
                fi
            fi
        fi
    fi

    # 检查并安装 npm（通常随 Node.js 一起安装）
    if ! command -v npm &> /dev/null; then
        log_error "npm 未安装，请手动安装 Node.js"
        exit 1
    fi

    # 显示版本信息
    log_info "Python 版本: $(python3 --version)"
    log_info "Node.js 版本: $(node --version)"
    log_info "npm 版本: $(npm --version)"

    # 检查 systemctl（用于管理 Xray 服务）
    if ! command -v systemctl &> /dev/null; then
        log_warn "systemctl 未找到，无法管理 Xray 服务"
        log_warn "此脚本需要 systemd 支持"
    fi

    log_info "依赖检查通过"
}

check_xray() {
    log_info "检查 Xray 服务..."

    if ! systemctl is-active --quiet xray 2>/dev/null; then
        log_warn "Xray 服务未运行"
        echo ""
        echo "请先安装并启动 Xray:"
        echo "  sudo $PROJECT_ROOT/scripts/install_xray.sh"
        echo ""
        read -p "是否继续启动监控系统? (y/n): " CONTINUE
        if [ "$CONTINUE" != "y" ]; then
            exit 0
        fi
    else
        log_info "Xray 服务正在运行"
    fi
}

setup_backend() {
    log_info "设置后端..."

    cd "$BACKEND_DIR"

    if [ ! -f ".env" ]; then
        log_warn ".env 文件不存在，从 .env.example 复制"
        if [ ! -f ".env.example" ]; then
            log_error ".env.example 文件不存在，无法创建配置文件"
            exit 1
        fi
        cp .env.example .env
        log_warn "请编辑 .env 文件配置你的设置"
    fi

    if [ ! -d ".venv" ]; then
        log_info "使用 uv 创建虚拟环境..."
        uv venv
    fi

    log_info "使用 uv 安装依赖..."
    if ! uv pip install -r requirements.txt; then
        log_error "Python 依赖安装失败"
        exit 1
    fi

    if [ ! -f "xray_monitor.db" ]; then
        log_info "初始化数据库..."
        alembic upgrade head
        python scripts/init_db.py
    else
        log_info "运行数据库迁移..."
        alembic upgrade head
    fi

    log_info "后端设置完成"
}

setup_frontend() {
    log_info "设置前端..."

    cd "$FRONTEND_DIR"

    if [ ! -d "node_modules" ]; then
        log_info "安装前端依赖..."
        if ! npm install; then
            log_error "前端依赖安装失败"
            exit 1
        fi
    fi

    log_info "前端设置完成"
}

start_backend() {
    log_info "启动后端服务..."

    cd "$BACKEND_DIR"

    # 检查端口 8000 是否被占用
    if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        log_error "端口 8000 已被占用"
        log_error "请先停止占用该端口的进程: lsof -i :8000"
        exit 1
    fi

    nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/xray-monitor-backend.log 2>&1 &
    echo $! > "$BACKEND_PID_FILE"

    sleep 2

    if ps -p $(cat "$BACKEND_PID_FILE") > /dev/null 2>&1; then
        log_info "后端服务启动成功 (PID: $(cat $BACKEND_PID_FILE))"
        log_info "后端地址: http://localhost:8000"
        log_info "API 文档: http://localhost:8000/docs"
    else
        log_error "后端服务启动失败"
        log_error "查看日志: tail -f /tmp/xray-monitor-backend.log"
        exit 1
    fi
}

start_frontend() {
    log_info "启动前端服务..."

    cd "$FRONTEND_DIR"

    # 检查端口 5173 是否被占用
    if lsof -Pi :5173 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        log_error "端口 5173 已被占用"
        log_error "请先停止占用该端口的进程: lsof -i :5173"
        exit 1
    fi

    nohup npm run dev > /tmp/xray-monitor-frontend.log 2>&1 &
    echo $! > "$FRONTEND_PID_FILE"

    sleep 3

    if ps -p $(cat "$FRONTEND_PID_FILE") > /dev/null 2>&1; then
        log_info "前端服务启动成功 (PID: $(cat $FRONTEND_PID_FILE))"
        log_info "前端地址: http://localhost:5173"
    else
        log_error "前端服务启动失败"
        log_error "查看日志: tail -f /tmp/xray-monitor-frontend.log"
        exit 1
    fi
}

stop_services() {
    log_info "停止服务..."

    if [ -f "$BACKEND_PID_FILE" ]; then
        BACKEND_PID=$(cat "$BACKEND_PID_FILE")
        if ps -p $BACKEND_PID > /dev/null 2>&1; then
            kill $BACKEND_PID
            log_info "后端服务已停止"
        fi
        rm -f "$BACKEND_PID_FILE"
    fi

    if [ -f "$FRONTEND_PID_FILE" ]; then
        FRONTEND_PID=$(cat "$FRONTEND_PID_FILE")
        if ps -p $FRONTEND_PID > /dev/null 2>&1; then
            kill $FRONTEND_PID
            log_info "前端服务已停止"
        fi
        rm -f "$FRONTEND_PID_FILE"
    fi

    pkill -f "uvicorn app.main:app" 2>/dev/null || true
    pkill -f "vite" 2>/dev/null || true

    log_info "所有服务已停止"
}

check_status() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   服务状态${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""

    if [ -f "$BACKEND_PID_FILE" ]; then
        BACKEND_PID=$(cat "$BACKEND_PID_FILE")
        if ps -p $BACKEND_PID > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} 后端服务: 运行中 (PID: $BACKEND_PID)"
            echo "  地址: http://localhost:8000"
            echo "  日志: tail -f /tmp/xray-monitor-backend.log"
        else
            echo -e "${RED}✗${NC} 后端服务: 未运行"
        fi
    else
        echo -e "${RED}✗${NC} 后端服务: 未运行"
    fi

    echo ""

    if [ -f "$FRONTEND_PID_FILE" ]; then
        FRONTEND_PID=$(cat "$FRONTEND_PID_FILE")
        if ps -p $FRONTEND_PID > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} 前端服务: 运行中 (PID: $FRONTEND_PID)"
            echo "  地址: http://localhost:5173"
            echo "  日志: tail -f /tmp/xray-monitor-frontend.log"
        else
            echo -e "${RED}✗${NC} 前端服务: 未运行"
        fi
    else
        echo -e "${RED}✗${NC} 前端服务: 未运行"
    fi

    echo ""

    if systemctl is-active --quiet xray 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Xray 服务: 运行中"
        echo "  状态: systemctl status xray"
    else
        echo -e "${RED}✗${NC} Xray 服务: 未运行"
    fi

    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo ""
}

show_logs() {
    echo ""
    echo "选择要查看的日志:"
    echo "1) 后端日志"
    echo "2) 前端日志"
    echo "3) Xray 日志"
    read -p "请选择 (1-3): " LOG_CHOICE

    case $LOG_CHOICE in
        1)
            tail -f /tmp/xray-monitor-backend.log
            ;;
        2)
            tail -f /tmp/xray-monitor-frontend.log
            ;;
        3)
            journalctl -u xray -f
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

show_menu() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}   Xray 流量监控系统${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
    echo "1) 启动所有服务"
    echo "2) 停止所有服务"
    echo "3) 重启所有服务"
    echo "4) 查看服务状态"
    echo "5) 查看日志"
    echo "6) 检查 Xray gRPC 连接"
    echo "7) 退出"
    echo ""
    read -p "请选择操作 (1-7): " CHOICE

    case $CHOICE in
        1)
            check_dependencies
            check_xray
            setup_backend
            setup_frontend
            start_backend
            start_frontend
            check_status
            echo ""
            log_info "所有服务已启动！"
            log_info "访问前端: http://localhost:5173"
            log_info "默认账号: admin / admin123"
            ;;
        2)
            stop_services
            ;;
        3)
            stop_services
            sleep 2
            start_backend
            start_frontend
            check_status
            ;;
        4)
            check_status
            ;;
        5)
            show_logs
            ;;
        6)
            cd "$BACKEND_DIR"
            uv run python scripts/check_xray_grpc.py
            ;;
        7)
            exit 0
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

if [ "${1:-}" = "start" ]; then
    check_dependencies
    check_xray
    setup_backend
    setup_frontend
    start_backend
    start_frontend
    check_status
elif [ "${1:-}" = "stop" ]; then
    stop_services
elif [ "${1:-}" = "restart" ]; then
    stop_services
    sleep 2
    start_backend
    start_frontend
    check_status
elif [ "${1:-}" = "status" ]; then
    check_status
else
    while true; do
        show_menu
        echo ""
        read -p "按 Enter 继续..."
    done
fi
