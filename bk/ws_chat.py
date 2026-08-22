import json
from uuid import UUID
from fastapi import WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from model import Message, MessageStatus, ChatMember


class ConnectionManager:
    def __init__(self):
        self.active: dict[str, WebSocket] = {}

    async def connect(self, user_id: str, websocket: WebSocket):
        await websocket.accept()
        self.active[user_id] = websocket

    def disconnect(self, user_id: str):
        self.active.pop(user_id, None)

    async def send_to_user(self, user_id: str, data: dict):
        ws = self.active.get(user_id)
        if ws:
            await ws.send_text(json.dumps(data))


manager = ConnectionManager()


async def handle_chat_ws(
    websocket: WebSocket,
    current_user,
    db: Session,
):
    user_id = str(current_user.id)
    await manager.connect(user_id, websocket)

    current_user.is_online = True
    db.commit()

    try:
        while True:
            raw  = await websocket.receive_text()
            data = json.loads(raw)

            event   = data.get("event", "message")
            chat_id = data.get("chat_id")

            # ── typing ────────────────────────────────────────
            if event in ("typing", "stop_typing"):
                members = db.query(ChatMember).filter(
                    ChatMember.chat_id == UUID(chat_id),
                    ChatMember.user_id != current_user.id,
                ).all()
                for member in members:
                    await manager.send_to_user(str(member.user_id), {
                        "event":     event,
                        "chat_id":   chat_id,
                        "user_name": current_user.name,
                    })
                continue

            # ── delivered ack ─────────────────────────────────
            if event == "delivered":
                msg_id    = data.get("msg_id")
                sender_id = data.get("sender_id")
                await manager.send_to_user(sender_id, {
                    "event":  "delivered",
                    "msg_id": msg_id,
                })
                continue

            # ── read ack ──────────────────────────────────────
            if event == "read":
                msg_ids   = data.get("msg_ids", [])
                sender_id = data.get("sender_id")
                await manager.send_to_user(sender_id, {
                    "event":   "read",
                    "msg_ids": msg_ids,
                })
                continue

            # ── normal message ────────────────────────────────
            content = data.get("content")
            if not chat_id or not content:
                continue

            msg = Message(
                chat_id=UUID(chat_id),
                sender_id=current_user.id,
                content=content,
                status=MessageStatus.sent,
            )
            db.add(msg)
            db.commit()
            db.refresh(msg)

            payload = {
                "event":      "message",
                "id":         str(msg.id),
                "chat_id":    str(msg.chat_id),
                "sender_id":  str(msg.sender_id),
                "content":    msg.content,
                "status":     "sent",
                "created_at": msg.created_at.isoformat(),
            }

            members = db.query(ChatMember).filter(
                ChatMember.chat_id == UUID(chat_id)
            ).all()
            for member in members:
                await manager.send_to_user(str(member.user_id), payload)

    except WebSocketDisconnect:
        manager.disconnect(user_id)
        current_user.is_online = False
        from datetime import datetime, timezone
        current_user.last_seen = datetime.now(timezone.utc)
        db.commit()
    except Exception as e:
        print(f"[WS] error: {e}")
        manager.disconnect(user_id)
        current_user.is_online = False
        from datetime import datetime, timezone
        current_user.last_seen = datetime.now(timezone.utc)
        db.commit()