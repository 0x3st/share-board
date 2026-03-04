import logging
from typing import Dict, Tuple
from sqlalchemy.orm import Session
from datetime import datetime
from ..db.models import User, UsageCheckpoint
from ..integrations.xray_client import XrayClient

logger = logging.getLogger(__name__)


def compute_delta(old_value: int, new_value: int) -> int:
    if new_value < old_value:
        return new_value
    return new_value - old_value


async def collect_once(db: Session) -> Dict[int, Dict[str, int]]:
    client = XrayClient()

    try:
        raw_stats = client.query_stats(pattern='user>>>.*>>>traffic>>>', reset=False)
        if not raw_stats:
            logger.warning("No stats returned from Xray")
            return {}

        aggregates = {}

        for email, traffic in raw_stats.items():
            user = db.query(User).filter(User.username == email).first()
            if not user:
                logger.debug(f"User not found for email: {email}")
                continue

            user_key = email
            checkpoint = db.query(UsageCheckpoint).filter(
                UsageCheckpoint.user_key == user_key
            ).first()

            if not checkpoint:
                checkpoint = UsageCheckpoint(
                    user_key=user_key,
                    last_uplink=0,
                    last_downlink=0
                )
                db.add(checkpoint)

            uplink = traffic.get('uplink', 0)
            downlink = traffic.get('downlink', 0)

            delta_uplink = compute_delta(checkpoint.last_uplink, uplink)
            delta_downlink = compute_delta(checkpoint.last_downlink, downlink)

            checkpoint.last_uplink = uplink
            checkpoint.last_downlink = downlink
            checkpoint.updated_at = datetime.utcnow()

            if user.id not in aggregates:
                aggregates[user.id] = {'uplink': 0, 'downlink': 0}

            aggregates[user.id]['uplink'] += delta_uplink
            aggregates[user.id]['downlink'] += delta_downlink

        db.commit()

        return aggregates

    except Exception as e:
        logger.error(f"Error collecting traffic stats: {e}")
        db.rollback()
        raise
