# Xray gRPC API 配置指南

## 检查 gRPC API 是否开启

### 方法一：使用检查脚本（推荐）

```bash
cd backend
python scripts/check_xray_grpc.py
```

如果连接成功，会显示：
```
✅ 连接成功！
✅ Xray gRPC API 工作正常！
```

如果连接失败，会显示错误信息和可能的原因。

### 方法二：手动检查端口

```bash
# 检查端口是否在监听
netstat -tlnp | grep 10085
# 或者
ss -tlnp | grep 10085
# 或者
lsof -i :10085
```

如果看到类似输出，说明端口已开启：
```
tcp    0    0 127.0.0.1:10085    0.0.0.0:*    LISTEN    12345/xray
```

### 方法三：使用 grpcurl 工具

```bash
# 安装 grpcurl
# macOS
brew install grpcurl

# Linux
wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.9/grpcurl_1.8.9_linux_x86_64.tar.gz
tar -xvf grpcurl_1.8.9_linux_x86_64.tar.gz
sudo mv grpcurl /usr/local/bin/

# 测试连接
grpcurl -plaintext 127.0.0.1:10085 list
```

如果成功，会列出可用的服务：
```
v2ray.core.app.stats.command.StatsService
```

## Xray 配置示例

要启用 gRPC API，你的 Xray 配置文件需要包含以下部分：

### 完整配置示例

```json
{
  "log": {
    "loglevel": "warning"
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
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    },
    {
      "tag": "vmess-in",
      "port": 443,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "your-uuid-here",
            "email": "user1@example.com",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/path/to/cert.pem",
              "keyFile": "/path/to/key.pem"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      }
    ]
  }
}
```

### 关键配置说明

#### 1. API 配置
```json
"api": {
  "tag": "api",
  "services": [
    "StatsService"
  ]
}
```
- 启用 StatsService 服务

#### 2. Stats 配置
```json
"stats": {}
```
- 启用统计功能（必须）

#### 3. Policy 配置
```json
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
}
```
- 启用用户级别和系统级别的流量统计

#### 4. API Inbound
```json
{
  "tag": "api",
  "listen": "127.0.0.1",
  "port": 10085,
  "protocol": "dokodemo-door",
  "settings": {
    "address": "127.0.0.1"
  }
}
```
- 监听地址：127.0.0.1（仅本地访问，安全）
- 端口：10085（可自定义）
- 协议：dokodemo-door

#### 5. Routing 配置
```json
"routing": {
  "rules": [
    {
      "type": "field",
      "inboundTag": ["api"],
      "outboundTag": "api"
    }
  ]
}
```
- 将 API 流量路由到 API 出站

### 用户配置注意事项

每个用户必须配置 `email` 字段，这是流量统计的关键：

```json
"clients": [
  {
    "id": "uuid-1",
    "email": "user1@example.com",  // 必须配置
    "alterId": 0
  },
  {
    "id": "uuid-2",
    "email": "user2@example.com",  // 必须配置
    "alterId": 0
  }
]
```

## 重启 Xray 服务

修改配置后，需要重启 Xray：

```bash
# systemd
sudo systemctl restart xray

# 或者直接运行
xray -config /path/to/config.json
```

## 常见问题

### 1. 连接被拒绝
- 检查 Xray 是否正在运行
- 检查端口配置是否正确
- 检查防火墙设置

### 2. 无统计数据
- 检查 `stats` 配置是否存在
- 检查 `policy` 中的统计开关是否开启
- 检查用户是否配置了 `email` 字段
- 确保有实际流量产生

### 3. 端口冲突
- 修改 API 端口到其他值（如 10086）
- 同时修改 backend/.env 中的 XRAY_API_PORT

### 4. 权限问题
- 确保运行监控系统的用户有权限访问 Xray API
- 如果 Xray 以 root 运行，可能需要调整权限

## 测试流程

1. 启动 Xray 服务
2. 运行检查脚本：`python backend/scripts/check_xray_grpc.py`
3. 如果成功，启动监控系统后端
4. 等待 60 秒（第一次采集）
5. 查看数据库中是否有数据

```bash
# 查看数据库
sqlite3 backend/xray_monitor.db
sqlite> SELECT * FROM usage_checkpoints;
sqlite> SELECT * FROM usage_hourly;
```
