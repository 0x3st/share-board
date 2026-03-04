from fastapi import APIRouter
from .auth import router as auth_router
from .usage import router as usage_router
from .subscriptions import router as subscriptions_router
from .admin import router as admin_router

api_router = APIRouter()

api_router.include_router(auth_router, prefix="/auth", tags=["auth"])
api_router.include_router(usage_router, tags=["usage"])
api_router.include_router(subscriptions_router, prefix="/subscriptions", tags=["subscriptions"])
api_router.include_router(admin_router, tags=["admin"])
