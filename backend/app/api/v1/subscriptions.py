from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import PlainTextResponse, Response
from sqlalchemy.orm import Session
from app.db.session import get_db
from app.services.subscription_service import SubscriptionService

router = APIRouter()


@router.get("/{token}")
async def get_subscription(
    token: str,
    format: str = Query("base64", regex="^(base64|clash|singbox)$"),
    db: Session = Depends(get_db)
):
    service = SubscriptionService(db)
    subscription = service.get_subscription_by_token(token)

    if not subscription:
        raise HTTPException(status_code=404, detail="Subscription not found or inactive")

    if format == "base64":
        content = service.build_base64_subscription(subscription)
        return PlainTextResponse(
            content=content,
            headers={
                "Content-Disposition": f"attachment; filename=subscription.txt",
                "Subscription-Userinfo": f"upload=0; download=0; total=107374182400; expire=0"
            }
        )
    elif format == "clash":
        content = service.build_clash_subscription(subscription)
        return Response(
            content=content,
            media_type="text/yaml",
            headers={
                "Content-Disposition": f"attachment; filename=clash.yaml",
                "Subscription-Userinfo": f"upload=0; download=0; total=107374182400; expire=0"
            }
        )
    elif format == "singbox":
        content = service.build_singbox_subscription(subscription)
        return Response(
            content=content,
            media_type="application/json",
            headers={
                "Content-Disposition": f"attachment; filename=singbox.json",
                "Subscription-Userinfo": f"upload=0; download=0; total=107374182400; expire=0"
            }
        )
