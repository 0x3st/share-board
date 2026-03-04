import os
import logging
import time
from typing import Dict, Optional
import grpc
from .xray_pb2 import QueryStatsRequest
from .xray_pb2_grpc import StatsServiceStub

logger = logging.getLogger(__name__)


class XrayClient:
    def __init__(
        self,
        host: Optional[str] = None,
        port: Optional[int] = None,
        timeout: int = 5,
        max_retries: int = 3
    ):
        self.host = host or os.getenv('XRAY_API_HOST', '127.0.0.1')
        self.port = port or int(os.getenv('XRAY_API_PORT', '10085'))
        self.timeout = timeout
        self.max_retries = max_retries
        self.address = f'{self.host}:{self.port}'

    def query_stats(self, pattern: str = '', reset: bool = False) -> Optional[Dict[str, Dict[str, int]]]:
        for attempt in range(self.max_retries):
            try:
                with grpc.insecure_channel(self.address) as channel:
                    stub = StatsServiceStub(channel)
                    request = QueryStatsRequest(pattern=pattern, reset=reset)

                    response = stub.QueryStats(request, timeout=self.timeout)

                    return parse_user_traffic_stats(response)

            except grpc.RpcError as e:
                logger.error(
                    f'gRPC error on attempt {attempt + 1}/{self.max_retries}: '
                    f'{e.code()} - {e.details()}'
                )
                if attempt < self.max_retries - 1:
                    time.sleep(1 * (attempt + 1))
                else:
                    raise ConnectionError(
                        f'Failed to connect to Xray API at {self.address} after {self.max_retries} attempts'
                    )
            except Exception as e:
                logger.error(f'Unexpected error querying Xray stats: {e}')
                raise

        return None


def parse_user_traffic_stats(response) -> Dict[str, Dict[str, int]]:
    result = {}

    try:
        if not hasattr(response, 'stat') or not response.stat:
            logger.warning('Empty stats response from Xray')
            return result

        for stat in response.stat:
            if not hasattr(stat, 'name') or not hasattr(stat, 'value'):
                continue

            name = stat.name
            value = stat.value

            parts = name.split('>>>')
            if len(parts) != 4:
                continue

            prefix, email, traffic_type, direction = parts

            if prefix != 'user' or traffic_type != 'traffic':
                continue

            if direction not in ('uplink', 'downlink'):
                continue

            if email not in result:
                result[email] = {'uplink': 0, 'downlink': 0}

            result[email][direction] = value

        return result

    except Exception as e:
        logger.error(f'Failed to parse user traffic stats: {e}')
        return {}


def get_user_traffic(email: Optional[str] = None) -> Dict[str, Dict[str, int]]:
    client = XrayClient()
    pattern = f'user>>>{email}>>>traffic>>>' if email else 'user>>>.*>>>traffic>>>'
    return client.query_stats(pattern=pattern) or {}
