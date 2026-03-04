#!/bin/bash

set -e

echo "========================================="
echo "Xray Traffic Monitor - Setup Script"
echo "========================================="
echo ""

cd "$(dirname "$0")/.."

if [ ! -f ".env" ]; then
    echo "Creating .env file from .env.example..."
    cp .env.example .env
    echo "Please edit .env file to configure your settings!"
    echo ""
fi

echo "Installing Python dependencies..."
pip install -r requirements.txt

echo ""
echo "Running database migrations..."
alembic upgrade head

echo ""
echo "Initializing database and creating admin user..."
python scripts/init_db.py

echo ""
echo "========================================="
echo "Setup complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Edit .env file to configure your settings"
echo "2. Update SERVER_NODES in app/core/config.py"
echo "3. Start the server: uvicorn app.main:app --reload"
echo ""
