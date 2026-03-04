from sqlalchemy import Column, Integer, String, Boolean, DateTime, BigInteger, Date, Enum as SQLEnum, ForeignKey, Index
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
    password_hash = Column(String(255), nullable=False)
    role = Column(SQLEnum(UserRole), nullable=False, default=UserRole.user)
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

    month = Column(String(7), primary_key=True)
    total_cost_cents = Column(Integer, nullable=False, default=0)
    currency = Column(String(3), nullable=False, default="USD")
    updated_at = Column(DateTime, nullable=False, default=func.now(), onupdate=func.now())
