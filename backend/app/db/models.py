from sqlalchemy import Column, Integer, String, Boolean, DateTime, BigInteger, Date, Enum as SQLEnum, ForeignKey, Index, Numeric
from sqlalchemy.sql import func
from datetime import datetime
import enum
from .session import Base

class UserRole(str, enum.Enum):
    admin = "admin"
    user = "user"

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(255), unique=True, nullable=False, index=True)
    email = Column(String(255), unique=True, nullable=True, index=True)  # 新增：邮箱
    password_hash = Column(String(255), nullable=False)
    role = Column(SQLEnum(UserRole), nullable=False, default=UserRole.user)

    # 3x-ui 相关字段
    xui_client_id = Column(String(100), nullable=True)  # 3x-ui中的client UUID
    xui_inbound_id = Column(Integer, nullable=True)     # 3x-ui中的inbound ID
    xui_email = Column(String(255), nullable=True)      # 3x-ui中的client email

    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, nullable=False, default=func.now())

class Subscription(Base):
    __tablename__ = "subscriptions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    token = Column(String(36), unique=True, nullable=False, index=True)
    remark = Column(String(255), nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, nullable=False, default=func.now())

    __table_args__ = (
        Index("ix_subscriptions_user_id", "user_id"),
        Index("ix_subscriptions_token", "token"),
    )

class UsageCheckpoint(Base):
    __tablename__ = "usage_checkpoints"

    user_key = Column(String(255), primary_key=True)
    last_uplink = Column(BigInteger, nullable=False, default=0)
    last_downlink = Column(BigInteger, nullable=False, default=0)
    updated_at = Column(DateTime, nullable=False, default=func.now(), onupdate=func.now())

class UsageHourly(Base):
    __tablename__ = "usage_hourly"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    hour_ts = Column(DateTime, primary_key=True)
    uplink_bytes = Column(BigInteger, nullable=False, default=0)
    downlink_bytes = Column(BigInteger, nullable=False, default=0)
    total_bytes = Column(BigInteger, nullable=False, default=0)
    updated_at = Column(DateTime, nullable=False, default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index("ix_usage_hourly_user_hour", "user_id", "hour_ts"),
    )

class UsageDaily(Base):
    __tablename__ = "usage_daily"

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    day_date = Column(Date, primary_key=True)
    uplink_bytes = Column(BigInteger, nullable=False, default=0)
    downlink_bytes = Column(BigInteger, nullable=False, default=0)
    total_bytes = Column(BigInteger, nullable=False, default=0)
    updated_at = Column(DateTime, nullable=False, default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index("ix_usage_daily_user_day", "user_id", "day_date"),
    )

class MonthlyCost(Base):
    __tablename__ = "monthly_cost"

    month = Column(String(7), primary_key=True)  # 格式: 2026-03
    total_cost_cents = Column(Integer, nullable=False, default=0)
    currency = Column(String(3), nullable=False, default="USD")
    updated_at = Column(DateTime, nullable=False, default=func.now(), onupdate=func.now())


class TrafficRecord(Base):
    """流量记录表 - 用于成本均摊计算"""
    __tablename__ = "traffic_records"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    month = Column(String(7), nullable=False)  # 格式: 2026-03
    upload_bytes = Column(BigInteger, nullable=False, default=0)
    download_bytes = Column(BigInteger, nullable=False, default=0)
    total_bytes = Column(BigInteger, nullable=False, default=0)
    cost_share = Column(Numeric(10, 2), nullable=True)  # 该用户应分摊的成本
    updated_at = Column(DateTime, nullable=False, default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index("ix_traffic_records_user_month", "user_id", "month", unique=True),
    )
