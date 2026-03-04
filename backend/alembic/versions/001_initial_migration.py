"""initial_migration

Revision ID: 001
Revises:
Create Date: 2026-03-04 13:29:11

"""
from alembic import op
import sqlalchemy as sa


revision = '001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'users',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('username', sa.String(length=255), nullable=False),
        sa.Column('password_hash', sa.String(length=255), nullable=False),
        sa.Column('role', sa.Enum('admin', 'user', name='userrole'), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_users_id'), 'users', ['id'], unique=False)
    op.create_index(op.f('ix_users_username'), 'users', ['username'], unique=True)

    op.create_table(
        'subscriptions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('token', sa.String(length=36), nullable=False),
        sa.Column('remark', sa.String(length=255), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_subscriptions_id'), 'subscriptions', ['id'], unique=False)
    op.create_index(op.f('ix_subscriptions_token'), 'subscriptions', ['token'], unique=True)
    op.create_index(op.f('ix_subscriptions_user_id'), 'subscriptions', ['user_id'], unique=False)

    op.create_table(
        'usage_checkpoints',
        sa.Column('user_key', sa.String(length=255), nullable=False),
        sa.Column('last_uplink', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('last_downlink', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('user_key')
    )

    op.create_table(
        'usage_hourly',
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('hour_ts', sa.DateTime(), nullable=False),
        sa.Column('uplink_bytes', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('downlink_bytes', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('total_bytes', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id', 'hour_ts')
    )
    op.create_index(op.f('ix_usage_hourly_user_hour'), 'usage_hourly', ['user_id', 'hour_ts'], unique=False)

    op.create_table(
        'usage_daily',
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('day_date', sa.Date(), nullable=False),
        sa.Column('uplink_bytes', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('downlink_bytes', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('total_bytes', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id', 'day_date')
    )
    op.create_index(op.f('ix_usage_daily_user_day'), 'usage_daily', ['user_id', 'day_date'], unique=False)

    op.create_table(
        'monthly_cost',
        sa.Column('month', sa.String(length=7), nullable=False),
        sa.Column('total_cost_cents', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('currency', sa.String(length=3), nullable=False, server_default='USD'),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('month')
    )


def downgrade() -> None:
    op.drop_table('monthly_cost')
    op.drop_index(op.f('ix_usage_daily_user_day'), table_name='usage_daily')
    op.drop_table('usage_daily')
    op.drop_index(op.f('ix_usage_hourly_user_hour'), table_name='usage_hourly')
    op.drop_table('usage_hourly')
    op.drop_table('usage_checkpoints')
    op.drop_index(op.f('ix_subscriptions_user_id'), table_name='subscriptions')
    op.drop_index(op.f('ix_subscriptions_token'), table_name='subscriptions')
    op.drop_index(op.f('ix_subscriptions_id'), table_name='subscriptions')
    op.drop_table('subscriptions')
    op.drop_index(op.f('ix_users_username'), table_name='users')
    op.drop_index(op.f('ix_users_id'), table_name='users')
    op.drop_table('users')
