from fastapi import APIRouter, Depends, HTTPException, status, Query
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from datetime import datetime, date
from typing import List, Optional

from ...db.session import get_db
from ...db.models import UsageHourly, UsageDaily, User
from ...core.security import decode_token
from ...services.billing_service import get_user_monthly_cost
from ...integrations.xray_client import XrayClient


router = APIRouter(prefix="/usage", tags=["usage"])

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> User:
    payload = decode_token(token)
    if not payload or payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    username = payload.get("sub")
    if not username:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = db.query(User).filter(User.username == username).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user


class HourlyUsageResponse(BaseModel):
    hour_ts: datetime
    uplink_bytes: int
    downlink_bytes: int
    total_bytes: int


class DailyUsageResponse(BaseModel):
    day_date: date
    uplink_bytes: int
    downlink_bytes: int
    total_bytes: int


class MonthlyCostResponse(BaseModel):
    month: str
    cost_cents: int
    currency: str = "USD"


class RealtimeUsageResponse(BaseModel):
    uplink: int
    downlink: int
    total: int


@router.get("/hourly", response_model=List[HourlyUsageResponse])
def get_hourly_usage(
    start_hour: datetime = Query(..., description="Start hour timestamp (ISO format)"),
    end_hour: datetime = Query(..., description="End hour timestamp (ISO format)"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    if start_hour >= end_hour:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="start_hour must be before end_hour"
        )

    records = db.query(UsageHourly).filter(
        UsageHourly.user_id == user.id,
        UsageHourly.hour_ts >= start_hour,
        UsageHourly.hour_ts <= end_hour
    ).order_by(UsageHourly.hour_ts).all()

    return [
        HourlyUsageResponse(
            hour_ts=record.hour_ts,
            uplink_bytes=record.uplink_bytes,
            downlink_bytes=record.downlink_bytes,
            total_bytes=record.total_bytes
        )
        for record in records
    ]


@router.get("/daily", response_model=List[DailyUsageResponse])
def get_daily_usage(
    start_date: date = Query(..., description="Start date (YYYY-MM-DD)"),
    end_date: date = Query(..., description="End date (YYYY-MM-DD)"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    if start_date >= end_date:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="start_date must be before end_date"
        )

    records = db.query(UsageDaily).filter(
        UsageDaily.user_id == user.id,
        UsageDaily.day_date >= start_date,
        UsageDaily.day_date <= end_date
    ).order_by(UsageDaily.day_date).all()

    return [
        DailyUsageResponse(
            day_date=record.day_date,
            uplink_bytes=record.uplink_bytes,
            downlink_bytes=record.downlink_bytes,
            total_bytes=record.total_bytes
        )
        for record in records
    ]


@router.get("/monthly-cost", response_model=MonthlyCostResponse)
def get_monthly_cost(
    month: str = Query(..., pattern=r'^\d{4}-\d{2}$', description="Month in YYYY-MM format"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    cost_cents = get_user_monthly_cost(db, user.id, month)

    return MonthlyCostResponse(
        month=month,
        cost_cents=cost_cents,
        currency="USD"
    )


@router.get("/realtime", response_model=RealtimeUsageResponse)
def get_realtime_usage(
    user: User = Depends(get_current_user)
):
    client = XrayClient()

    try:
        raw_stats = client.query_stats(pattern=f'user>>>{user.username}>>>traffic>>>', reset=False)

        if not raw_stats or user.username not in raw_stats:
            return RealtimeUsageResponse(
                uplink=0,
                downlink=0,
                total=0
            )

        traffic = raw_stats[user.username]
        uplink = traffic.get('uplink', 0)
        downlink = traffic.get('downlink', 0)

        return RealtimeUsageResponse(
            uplink=uplink,
            downlink=downlink,
            total=uplink + downlink
        )

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Failed to fetch realtime usage: {str(e)}"
        )
