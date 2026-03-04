# Xray Traffic Monitor

基于 Xray-core 的轻量化流量监控与订阅管理系统，供几个朋友共用，实现流量采集、订阅生成、用量展示和成本分摊功能。

## 技术栈

**后端：**
- FastAPI
- SQLite (WAL 模式)
- JWT Token 认证
- gRPC 客户端（Xray StatsService）
- 内置后台轮询任务

**前端：**
- React 18
- shadcn/ui + TailwindCSS
- Zustand 状态管理
- Axios + 拦截器
- 简单轮询（5秒）

## 快速开始

### 后端设置

```bash
cd backend

# 运行自动化设置脚本
./scripts/setup.sh

# 或者手动设置：
# 1. 复制环境变量文件
cp .env.example .env

# 2. 编辑 .env 文件配置你的设置
nano .env

# 3. 安装依赖
pip install -r requirements.txt

# 4. 运行数据库迁移
alembic upgrade head

# 5. 初始化数据库并创建管理员用户
python scripts/init_db.py

# 6. 启动服务器
uvicorn app.main:app --reload --port 8000
```

### 前端设置

```bash
cd frontend

# 安装依赖
npm install

# 启动开发服务器
npm run dev
```

访问 http://localhost:5173

## 默认管理员账号

- 用户名: `admin`
- 密码: `admin123`

**请在首次登录后立即修改密码！**

## 配置说明

### 后端配置（backend/.env）

```env
DATABASE_URL=sqlite:///./xray_monitor.db
SECRET_KEY=your-secret-key-change-this-in-production
XRAY_API_HOST=127.0.0.1
XRAY_API_PORT=10085
LOG_LEVEL=INFO
```

### 服务器节点配置（backend/app/core/config.py）

编辑 `SERVER_NODES` 列表，添加你的 Xray 服务器节点：

```python
SERVER_NODES: list[dict] = [
    {
        "name": "HK-01",
        "address": "hk.example.com",
        "port": 443,
        "protocol": "vmess",
        "uuid": "your-uuid-here",
        "alterId": 0,
        "network": "ws",
        "path": "/",
        "tls": True,
    }
]
```

## 核心功能

### 流量监控
- 实时流量采集（60秒轮询）
- 小时/日流量统计
- 流量配额进度条（动态颜色：Green/Yellow/Red）
- 实时上传/下载速率显示

### 订阅管理
- 三种订阅格式：Base64、Clash、Sing-box
- 订阅 Token 管理
- 一键导入客户端

### 成本分摊
- 按流量比例自动分摊
- 月度账单查看
- 计算公式透明展示
- 账本表格（分页、移动端适配）

### 用户管理
- JWT Token 认证
- 管理员/普通用户角色
- 用户数据隔离

## API 文档

启动后端服务后，访问：
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## 项目结构

```
.
├── backend/
│   ├── app/
│   │   ├── api/          # API 路由
│   │   ├── core/         # 核心配置
│   │   ├── db/           # 数据库模型
│   │   ├── integrations/ # Xray gRPC 集成
│   │   ├── middleware/   # 中间件
│   │   ├── services/     # 业务逻辑
│   │   └── workers/      # 后台任务
│   ├── alembic/          # 数据库迁移
│   └── scripts/          # 初始化脚本
└── frontend/
    └── src/
        ├── components/   # 通用组件
        ├── features/     # 功能模块
        ├── hooks/        # 自定义 Hooks
        ├── lib/          # 工具库
        ├── pages/        # 页面组件
        └── store/        # 状态管理
```

## 开发说明

### 数据库迁移

```bash
cd backend

# 创建新迁移
alembic revision --autogenerate -m "description"

# 应用迁移
alembic upgrade head

# 回滚迁移
alembic downgrade -1
```

### 添加新用户

```python
from app.db.session import SessionLocal
from app.db.models import User, UserRole
from app.core.security import get_password_hash

db = SessionLocal()
user = User(
    username="newuser",
    password_hash=get_password_hash("password"),
    role=UserRole.user
)
db.add(user)
db.commit()
```

## 注意事项

1. **Xray API 配置**：确保 Xray 的 gRPC API 端口（默认 10085）已开启
2. **SECRET_KEY**：生产环境请使用强密钥（`openssl rand -hex 32`）
3. **数据库备份**：定期备份 SQLite 数据库文件
4. **计数器重置**：系统已处理 Xray 计数器重置场景
5. **并发限制**：SQLite 适合小规模使用，大规模请考虑 PostgreSQL

## License

MIT
