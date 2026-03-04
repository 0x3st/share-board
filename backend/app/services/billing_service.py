from datetime import datetime, date
from typing import Dict
from sqlalchemy.orm import Session
from sqlalchemy import func, extract
from app.db.models import UsageDaily, MonthlyCost


def calculate_monthly_shares(db: Session, month: str) -> Dict[int, int]:
    year, month_num = map(int, month.split('-'))

    total_usage = db.query(
        UsageDaily.user_id,
        func.sum(UsageDaily.total_bytes).label('total')
    ).filter(
        extract('year', UsageDaily.day_date) == year,
        extract('month', UsageDaily.day_date) == month_num
    ).group_by(UsageDaily.user_id).all()

    if not total_usage:
        return {}

    total_bytes = sum(row.total for row in total_usage)
    if total_bytes == 0:
        return {row.user_id: 0 for row in total_usage}

    monthly_cost = db.query(MonthlyCost).filter(MonthlyCost.month == month).first()
    if not monthly_cost:
        return {row.user_id: 0 for row in total_usage}

    shares = {}
    for row in total_usage:
        share_ratio = row.total / total_bytes
        shares[row.user_id] = int(monthly_cost.total_cost_cents * share_ratio)

    return shares


def get_user_monthly_cost(db: Session, user_id: int, month: str) -> int:
    shares = calculate_monthly_shares(db, month)
    return shares.get(user_id, 0)
