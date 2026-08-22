from datetime import datetime
from pydantic import BaseModel, EmailStr


class signup(BaseModel):
    name: str
    email: EmailStr
    password: str


class signupResponse(BaseModel):
    id: str
    name: str
    email: str

    class Config:
        from_attributes = True


class login(BaseModel):
    email: EmailStr
    password: str


class token(BaseModel):
    access_token: str
    token_type: str


# ── new ──────────────────────────────────────────────────────────

class MessageOut(BaseModel):
    id: str
    chat_id: str
    sender_id: str
    content: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


class ChatOut(BaseModel):
    id: str
    name: str | None
    is_group: bool
    created_at: datetime

    class Config:
        from_attributes = True