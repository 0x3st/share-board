import logging
import sys
import asyncio

import structlog
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.config import settings
from app.api.v1 import api_router
from app.workers.poller import run_polling_loop
from app.middleware.error_handler import (
    error_handler_middleware,
    http_exception_handler,
    validation_exception_handler,
)


def configure_logging():
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            logging.getLevelName(settings.LOG_LEVEL)
        ),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
        cache_logger_on_first_use=True,
    )


configure_logging()
logger = structlog.get_logger()

app = FastAPI(
    title="FQ Backend API",
    description="Backend API for FQ traffic monitoring and billing system",
    version="0.1.0",
    openapi_tags=[
        {
            "name": "auth",
            "description": "Authentication and authorization operations"
        },
        {
            "name": "usage",
            "description": "Traffic usage monitoring and statistics"
        },
        {
            "name": "subscriptions",
            "description": "Subscription management and configuration export"
        },
        {
            "name": "admin",
            "description": "Administrative operations (admin only)"
        }
    ]
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=settings.CORS_ALLOW_CREDENTIALS,
    allow_methods=settings.CORS_ALLOW_METHODS,
    allow_headers=settings.CORS_ALLOW_HEADERS,
)

app.middleware("http")(error_handler_middleware)
app.add_exception_handler(StarletteHTTPException, http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)

app.include_router(api_router, prefix="/api/v1")

poller_task = None


@app.on_event("startup")
async def startup_event():
    global poller_task
    logger.info("application_startup", log_level=settings.LOG_LEVEL)
    poller_task = asyncio.create_task(run_polling_loop(interval_seconds=60))
    logger.info("poller_started", interval_seconds=60)


@app.on_event("shutdown")
async def shutdown_event():
    global poller_task
    logger.info("application_shutdown")
    if poller_task:
        poller_task.cancel()
        try:
            await poller_task
        except asyncio.CancelledError:
            logger.info("poller_stopped")


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "fq-backend",
        "version": "0.1.0",
    }
