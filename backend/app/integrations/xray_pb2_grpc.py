# Generated gRPC client stub for Xray StatsService
import grpc
from . import xray_pb2


class StatsServiceStub:
    def __init__(self, channel):
        self.GetStats = channel.unary_unary(
            '/xray.app.stats.command.StatsService/GetStats',
            request_serializer=lambda x: self._serialize_request(x),
            response_deserializer=lambda x: self._deserialize_response(x, xray_pb2.GetStatsResponse),
        )
        self.QueryStats = channel.unary_unary(
            '/xray.app.stats.command.StatsService/QueryStats',
            request_serializer=lambda x: self._serialize_request(x),
            response_deserializer=lambda x: self._deserialize_response(x, xray_pb2.QueryStatsResponse),
        )

    def _serialize_request(self, request):
        import json
        data = {}
        if hasattr(request, 'name'):
            data['name'] = request.name
        if hasattr(request, 'pattern'):
            data['pattern'] = request.pattern
        if hasattr(request, 'reset'):
            data['reset'] = request.reset
        return json.dumps(data).encode('utf-8')

    def _deserialize_response(self, response_bytes, response_class):
        import json
        data = json.loads(response_bytes.decode('utf-8'))
        if response_class == xray_pb2.GetStatsResponse:
            stat = xray_pb2.Stat(
                name=data.get('stat', {}).get('name', ''),
                value=data.get('stat', {}).get('value', 0)
            )
            return xray_pb2.GetStatsResponse(stat=stat)
        elif response_class == xray_pb2.QueryStatsResponse:
            stats = []
            for s in data.get('stat', []):
                stats.append(xray_pb2.Stat(name=s.get('name', ''), value=s.get('value', 0)))
            return xray_pb2.QueryStatsResponse(stat=stats)
        return response_class()
