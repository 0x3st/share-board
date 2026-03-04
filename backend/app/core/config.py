from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    DATABASE_URL: str = "sqlite:///./fq.db"
    SECRET_KEY: str = "dev-secret-key-change-in-production"
    XRAY_API_HOST: str = "127.0.0.1"
    XRAY_API_PORT: int = 62789
    LOG_LEVEL: str = "INFO"

    CORS_ORIGINS: list[str] = ["http://localhost:5173", "http://127.0.0.1:5173"]
    CORS_ALLOW_CREDENTIALS: bool = True
    CORS_ALLOW_METHODS: list[str] = ["*"]
    CORS_ALLOW_HEADERS: list[str] = ["*"]

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


settings = Settings()
