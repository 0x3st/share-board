#!/usr/bin/env python3
"""
用户管理脚本
用于添加、删除、修改用户和订阅
"""
import sys
import os
import uuid
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.session import SessionLocal
from app.db.models import User, UserRole, Subscription
from app.core.security import get_password_hash


def add_user():
    print("\n=== 添加新用户 ===\n")

    username = input("用户名: ").strip()
    if not username:
        print("❌ 用户名不能为空")
        return

    password = input("密码: ").strip()
    if not password:
        print("❌ 密码不能为空")
        return

    role_input = input("角色 (admin/user, 默认: user): ").strip().lower()
    role = UserRole.admin if role_input == "admin" else UserRole.user

    db = SessionLocal()
    try:
        existing = db.query(User).filter(User.username == username).first()
        if existing:
            print(f"❌ 用户 '{username}' 已存在")
            return

        user = User(
            username=username,
            password_hash=get_password_hash(password),
            role=role
        )
        db.add(user)
        db.commit()
        db.refresh(user)

        print(f"\n✅ 用户创建成功！")
        print(f"  ID: {user.id}")
        print(f"  用户名: {user.username}")
        print(f"  角色: {user.role.value}")
        print(f"  创建时间: {user.created_at}")

        create_sub = input("\n是否为该用户创建订阅? (y/n): ").strip().lower()
        if create_sub == 'y':
            create_subscription(db, user.id)

    except Exception as e:
        print(f"❌ 创建用户失败: {e}")
        db.rollback()
    finally:
        db.close()


def list_users():
    print("\n=== 用户列表 ===\n")

    db = SessionLocal()
    try:
        users = db.query(User).all()

        if not users:
            print("暂无用户")
            return

        print(f"{'ID':<5} {'用户名':<20} {'角色':<10} {'创建时间':<20}")
        print("-" * 60)

        for user in users:
            print(f"{user.id:<5} {user.username:<20} {user.role.value:<10} {user.created_at.strftime('%Y-%m-%d %H:%M:%S'):<20}")

        print(f"\n共 {len(users)} 个用户")

    finally:
        db.close()


def delete_user():
    print("\n=== 删除用户 ===\n")

    list_users()

    user_id = input("\n请输入要删除的用户 ID: ").strip()
    if not user_id.isdigit():
        print("❌ 无效的用户 ID")
        return

    user_id = int(user_id)

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            print(f"❌ 用户 ID {user_id} 不存在")
            return

        confirm = input(f"确认删除用户 '{user.username}'? (yes/no): ").strip().lower()
        if confirm != 'yes':
            print("取消删除")
            return

        db.delete(user)
        db.commit()

        print(f"✅ 用户 '{user.username}' 已删除")

    except Exception as e:
        print(f"❌ 删除用户失败: {e}")
        db.rollback()
    finally:
        db.close()


def change_password():
    print("\n=== 修改密码 ===\n")

    list_users()

    user_id = input("\n请输入用户 ID: ").strip()
    if not user_id.isdigit():
        print("❌ 无效的用户 ID")
        return

    user_id = int(user_id)

    new_password = input("新密码: ").strip()
    if not new_password:
        print("❌ 密码不能为空")
        return

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            print(f"❌ 用户 ID {user_id} 不存在")
            return

        user.password_hash = get_password_hash(new_password)
        db.commit()

        print(f"✅ 用户 '{user.username}' 的密码已修改")

    except Exception as e:
        print(f"❌ 修改密码失败: {e}")
        db.rollback()
    finally:
        db.close()


def create_subscription(db, user_id):
    token = str(uuid.uuid4())
    remark = input("订阅备注 (可选): ").strip() or None

    try:
        subscription = Subscription(
            user_id=user_id,
            token=token,
            remark=remark,
            is_active=True
        )
        db.add(subscription)
        db.commit()
        db.refresh(subscription)

        print(f"\n✅ 订阅创建成功！")
        print(f"  订阅 ID: {subscription.id}")
        print(f"  Token: {subscription.token}")
        print(f"  订阅链接:")
        print(f"    Base64: http://your-domain:8000/api/v1/subscriptions/{token}?format=base64")
        print(f"    Clash:  http://your-domain:8000/api/v1/subscriptions/{token}?format=clash")
        print(f"    Sing-box: http://your-domain:8000/api/v1/subscriptions/{token}?format=singbox")

    except Exception as e:
        print(f"❌ 创建订阅失败: {e}")
        db.rollback()


def add_subscription():
    print("\n=== 添加订阅 ===\n")

    list_users()

    user_id = input("\n请输入用户 ID: ").strip()
    if not user_id.isdigit():
        print("❌ 无效的用户 ID")
        return

    user_id = int(user_id)

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.id == user_id).first()
        if not user:
            print(f"❌ 用户 ID {user_id} 不存在")
            return

        create_subscription(db, user_id)

    finally:
        db.close()


def list_subscriptions():
    print("\n=== 订阅列表 ===\n")

    db = SessionLocal()
    try:
        subscriptions = db.query(Subscription).join(User).all()

        if not subscriptions:
            print("暂无订阅")
            return

        print(f"{'ID':<5} {'用户':<15} {'Token':<38} {'状态':<8} {'备注':<20}")
        print("-" * 90)

        for sub in subscriptions:
            status = "启用" if sub.is_active else "禁用"
            remark = sub.remark or "-"
            print(f"{sub.id:<5} {sub.user.username:<15} {sub.token:<38} {status:<8} {remark:<20}")

        print(f"\n共 {len(subscriptions)} 个订阅")

    finally:
        db.close()


def toggle_subscription():
    print("\n=== 启用/禁用订阅 ===\n")

    list_subscriptions()

    sub_id = input("\n请输入订阅 ID: ").strip()
    if not sub_id.isdigit():
        print("❌ 无效的订阅 ID")
        return

    sub_id = int(sub_id)

    db = SessionLocal()
    try:
        subscription = db.query(Subscription).filter(Subscription.id == sub_id).first()
        if not subscription:
            print(f"❌ 订阅 ID {sub_id} 不存在")
            return

        subscription.is_active = not subscription.is_active
        db.commit()

        status = "启用" if subscription.is_active else "禁用"
        print(f"✅ 订阅已{status}")

    except Exception as e:
        print(f"❌ 操作失败: {e}")
        db.rollback()
    finally:
        db.close()


def show_menu():
    print("\n" + "=" * 50)
    print("   用户管理")
    print("=" * 50)
    print("\n用户操作:")
    print("  1) 添加用户")
    print("  2) 查看用户列表")
    print("  3) 删除用户")
    print("  4) 修改密码")
    print("\n订阅操作:")
    print("  5) 添加订阅")
    print("  6) 查看订阅列表")
    print("  7) 启用/禁用订阅")
    print("\n  0) 退出")
    print()


def main():
    while True:
        show_menu()
        choice = input("请选择操作 (0-7): ").strip()

        if choice == '1':
            add_user()
        elif choice == '2':
            list_users()
        elif choice == '3':
            delete_user()
        elif choice == '4':
            change_password()
        elif choice == '5':
            add_subscription()
        elif choice == '6':
            list_subscriptions()
        elif choice == '7':
            toggle_subscription()
        elif choice == '0':
            print("\n再见！")
            break
        else:
            print("❌ 无效选择")

        input("\n按 Enter 继续...")


if __name__ == "__main__":
    main()
