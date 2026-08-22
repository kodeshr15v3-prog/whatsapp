import uuid
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey, Text, Enum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum

from db import Base


class User(Base):
    __tablename__ = "users"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name       = Column(String, nullable=False)
    email      = Column(String, unique=True, nullable=False, index=True)
    password   = Column(String, nullable=False)
    avatar_url = Column(String, nullable=True)
    is_active  = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    is_online   = Column(Boolean, default=False)
    last_seen   = Column(DateTime(timezone=True), nullable=True)
    about = Column(String, default="Hey there! I am using ChatApp")

    memberships = relationship("ChatMember", back_populates="user")
    messages    = relationship("Message", back_populates="sender")


class Chat(Base):
    __tablename__ = "chats"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name       = Column(String, nullable=True)   # None for direct (1:1) chats
    is_group   = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    members  = relationship("ChatMember", back_populates="chat")
    messages = relationship("Message", back_populates="chat")


class ChatMember(Base):
    __tablename__ = "chat_members"

    id        = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    chat_id   = Column(UUID(as_uuid=True), ForeignKey("chats.id"), nullable=False)
    user_id   = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    is_admin  = Column(Boolean, default=False)
    joined_at = Column(DateTime(timezone=True), server_default=func.now())
    last_read_at = Column(DateTime(timezone=True), nullable=True)  # ← add this


    chat = relationship("Chat", back_populates="members")
    user = relationship("User", back_populates="memberships")



class MessageStatus(str, enum.Enum):
    sent      = "sent"
    delivered = "delivered"
    read      = "read"


class Message(Base):
    __tablename__ = "messages"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    chat_id    = Column(UUID(as_uuid=True), ForeignKey("chats.id"), nullable=False)
    sender_id  = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    content    = Column(Text, nullable=False)
    status     = Column(Enum(MessageStatus), default=MessageStatus.sent)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    chat   = relationship("Chat", back_populates="messages")
    sender = relationship("User", back_populates="messages")