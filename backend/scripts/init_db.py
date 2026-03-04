#!/usr/bin/env python3
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.db.session import SessionLocal, engine
from app.db.models import Base, User, UserRole
from app.core.security import get_password_hash


def init_db():
    print("Creating database tables...")
    Base.metadata.create_all(bind=engine)
    print("Database tables created successfully!")


def create_admin_user(username: str = "admin", password: str = "admin123"):
    db = SessionLocal()
    try:
        existing_user = db.query(User).filter(User.username == username).first()
        if existing_user:
            print(f"Admin user '{username}' already exists!")
            return

        admin = User(
            username=username,
            password_hash=get_password_hash(password),
            role=UserRole.admin
        )
        db.add(admin)
        db.commit()
        print(f"Admin user created successfully!")
        print(f"Username: {username}")
        print(f"Password: {password}")
        print("Please change the password after first login!")
    except Exception as e:
        print(f"Error creating admin user: {e}")
        db.rollback()
    finally:
        db.close()


if __name__ == "__main__":
    print("Initializing database...")
    init_db()
    print("\nCreating admin user...")
    create_admin_user()
    print("\nInitialization complete!")
