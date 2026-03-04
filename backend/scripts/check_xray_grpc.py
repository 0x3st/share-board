#!/usr/bin/env python3
"""
Xray gRPC API 检查脚本
检查 Xray 的 gRPC API 是否正常开启并可访问
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.integrations.xray_client import XrayClient
from app.core.config import settings


def check_grpc_connection():
    print("=" * 50)
    print("Xray gRPC API 连接检查")
    print("=" * 50)
    print(f"\n配置信息:")
    print(f"  Host: {settings.XRAY_API_HOST}")
    print(f"  Port: {settings.XRAY_API_PORT}")
    print(f"  地址: {settings.XRAY_API_HOST}:{settings.XRAY_API_PORT}")
    print("\n正在尝试连接...")

    try:
        client = XrayClient()
        stats = client.query_stats()

        print("\n✅ 连接成功！")
        print(f"\n获取到的统计数据:")

        if not stats:
            print("  (暂无统计数据)")
        else:
            for stat in stats[:5]:
                print(f"  - {stat.name}: {stat.value}")
            if len(stats) > 5:
                print(f"  ... 还有 {len(stats) - 5} 条数据")

        print("\n正在解析用户流量数据...")
        from app.integrations.xray_client import parse_user_traffic_stats
        traffic_data = parse_user_traffic_stats(stats)

        if not traffic_data:
            print("  (暂无用户流量数据)")
        else:
            print(f"\n用户流量统计:")
            for user_email, traffic in traffic_data.items():
                uplink_mb = traffic['uplink'] / 1024 / 1024
                downlink_mb = traffic['downlink'] / 1024 / 1024
                print(f"  - {user_email}:")
                print(f"      上传: {uplink_mb:.2f} MB")
                print(f"      下载: {downlink_mb:.2f} MB")

        print("\n" + "=" * 50)
        print("✅ Xray gRPC API 工作正常！")
        print("=" * 50)
        return True

    except ConnectionError as e:
        print("\n❌ 连接失败！")
        print(f"\n错误信息: {e}")
        print("\n可能的原因:")
        print("  1. Xray 服务未启动")
        print("  2. Xray gRPC API 未开启")
        print("  3. 端口配置错误")
        print("  4. 防火墙阻止连接")
        print("\n请检查 Xray 配置文件中的 api 和 stats 配置")
        print("=" * 50)
        return False

    except Exception as e:
        print("\n❌ 发生未知错误！")
        print(f"\n错误信息: {e}")
        print("=" * 50)
        return False


if __name__ == "__main__":
    success = check_grpc_connection()
    sys.exit(0 if success else 1)
