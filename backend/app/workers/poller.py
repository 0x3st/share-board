import asyncio
import logging
from datetime import datetime, date
from ..db.session import SessionLocal
from ..services.collector_service import collect_once
from ..services.aggregation_service import flush_aggregates, rollup_daily_usage

logger = logging.getLogger(__name__)


async def run_polling_loop(interval_seconds: int = 60):
    logger.info(f"Starting polling loop with interval: {interval_seconds}s")

    last_rollup_date = None

    while True:
        try:
            db = SessionLocal()
            try:
                aggregates = await collect_once(db)
                await flush_aggregates(db, aggregates)

                current_date = date.today()
                if last_rollup_date != current_date:
                    current_hour = datetime.utcnow().hour
                    if current_hour == 0 or last_rollup_date is None:
                        yesterday = date.fromordinal(current_date.toordinal() - 1) if last_rollup_date is None else last_rollup_date
                        await rollup_daily_usage(db, yesterday)
                        last_rollup_date = current_date

            finally:
                db.close()

        except Exception as e:
            logger.error(f"Error in polling loop: {e}", exc_info=True)

        await asyncio.sleep(interval_seconds)
