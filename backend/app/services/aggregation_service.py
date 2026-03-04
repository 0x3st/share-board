import logging
from typing import Dict
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime, date
from ..db.models import UsageHourly, UsageDaily

logger = logging.getLogger(__name__)


async def flush_aggregates(db: Session, aggregates: Dict[int, Dict[str, int]]) -> None:
    if not aggregates:
        return

    hour_ts = datetime.utcnow().replace(minute=0, second=0, microsecond=0)

    try:
        for user_id, traffic in aggregates.items():
            uplink = traffic.get('uplink', 0)
            downlink = traffic.get('downlink', 0)
            total = uplink + downlink

            if total == 0:
                continue

            existing = db.query(UsageHourly).filter(
                UsageHourly.user_id == user_id,
                UsageHourly.hour_ts == hour_ts
            ).first()

            if existing:
                existing.uplink_bytes += uplink
                existing.downlink_bytes += downlink
                existing.total_bytes += total
                existing.updated_at = datetime.utcnow()
            else:
                new_record = UsageHourly(
                    user_id=user_id,
                    hour_ts=hour_ts,
                    uplink_bytes=uplink,
                    downlink_bytes=downlink,
                    total_bytes=total
                )
                db.add(new_record)

        db.commit()
        logger.info(f"Flushed aggregates for {len(aggregates)} users at {hour_ts}")

    except Exception as e:
        logger.error(f"Error flushing aggregates: {e}")
        db.rollback()
        raise


async def rollup_daily_usage(db: Session, target_date: date = None) -> None:
    if target_date is None:
        target_date = date.today()

    try:
        start_ts = datetime.combine(target_date, datetime.min.time())
        end_ts = datetime.combine(target_date, datetime.max.time())

        hourly_data = db.query(
            UsageHourly.user_id,
            func.sum(UsageHourly.uplink_bytes).label('total_uplink'),
            func.sum(UsageHourly.downlink_bytes).label('total_downlink'),
            func.sum(UsageHourly.total_bytes).label('total_bytes')
        ).filter(
            UsageHourly.hour_ts >= start_ts,
            UsageHourly.hour_ts <= end_ts
        ).group_by(UsageHourly.user_id).all()

        for row in hourly_data:
            user_id = row.user_id
            uplink = row.total_uplink or 0
            downlink = row.total_downlink or 0
            total = row.total_bytes or 0

            existing = db.query(UsageDaily).filter(
                UsageDaily.user_id == user_id,
                UsageDaily.day_date == target_date
            ).first()

            if existing:
                existing.uplink_bytes = uplink
                existing.downlink_bytes = downlink
                existing.total_bytes = total
                existing.updated_at = datetime.utcnow()
            else:
                new_record = UsageDaily(
                    user_id=user_id,
                    day_date=target_date,
                    uplink_bytes=uplink,
                    downlink_bytes=downlink,
                    total_bytes=total
                )
                db.add(new_record)

        db.commit()
        logger.info(f"Rolled up daily usage for {len(hourly_data)} users on {target_date}")

    except Exception as e:
        logger.error(f"Error rolling up daily usage: {e}")
        db.rollback()
        raise
