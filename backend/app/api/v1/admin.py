from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field
from datetime import datetime
import re

from ...db.session import get_db
from ...db.models import MonthlyCost, User, UserRole
from ...core.security import decode_token


router = APIRouter(prefix="/admin", tags=["admin"])

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


class MonthlyCostRequest(BaseModel):
    month: str = Field(..., pattern=r'^\d{4}-\d{2}$')
    total_cost_cents: int = Field(..., ge=0)
    currency: str = Field(default="USD", max_length=3)


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> User:
    payload = decode_token(token)
    if not payload or payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    username = payload.get("sub")
    if not username:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = db.query(User).filter(User.username == username).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != UserRole.admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required"
        )
    return user


@router.post("/monthly-cost", status_code=status.HTTP_201_CREATED)
def set_monthly_cost(
    request: MonthlyCostRequest,
    db: Session = Depends(get_db),
    _: User = Depends(require_admin)
):
    if not re.match(r'^\d{4}-(0[1-9]|1[0-2])$', request.month):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid month format. Use YYYY-MM"
        )

    existing = db.query(MonthlyCost).filter(MonthlyCost.month == request.month).first()

    if existing:
        existing.total_cost_cents = request.total_cost_cents
        existing.currency = request.currency
        existing.updated_at = datetime.utcnow()
    else:
        monthly_cost = MonthlyCost(
            month=request.month,
            total_cost_cents=request.total_cost_cents,
            currency=request.currency
        )
        db.add(monthly_cost)

    db.commit()

    return {
        "month": request.month,
        "total_cost_cents": request.total_cost_cents,
        "currency": request.currency
    }
