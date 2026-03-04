# Generated protocol buffer code for Xray StatsService
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from google.protobuf import reflection as _reflection
from google.protobuf import symbol_database as _symbol_database

_sym_db = _symbol_database.Default()

DESCRIPTOR = _descriptor.FileDescriptor(
    name='stats.proto',
    package='xray.app.stats.command',
    syntax='proto3',
    serialized_pb=b'\n\x0bstats.proto\x12\x17xray.app.stats.command'
)

class GetStatsRequest(_message.Message):
    __slots__ = ['name', 'reset']
    NAME_FIELD_NUMBER = 1
    RESET_FIELD_NUMBER = 2

    def __init__(self, name='', reset=False):
        self.name = name
        self.reset = reset

class Stat(_message.Message):
    __slots__ = ['name', 'value']
    NAME_FIELD_NUMBER = 1
    VALUE_FIELD_NUMBER = 2

    def __init__(self, name='', value=0):
        self.name = name
        self.value = value

class GetStatsResponse(_message.Message):
    __slots__ = ['stat']
    STAT_FIELD_NUMBER = 1

    def __init__(self, stat=None):
        self.stat = stat

class QueryStatsRequest(_message.Message):
    __slots__ = ['pattern', 'reset']
    PATTERN_FIELD_NUMBER = 1
    RESET_FIELD_NUMBER = 2

    def __init__(self, pattern='', reset=False):
        self.pattern = pattern
        self.reset = reset

class QueryStatsResponse(_message.Message):
    __slots__ = ['stat']
    STAT_FIELD_NUMBER = 1

    def __init__(self, stat=None):
        self.stat = stat if stat is not None else []
