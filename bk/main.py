from sqlalchemy import func
from datetime import datetime, timezone
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from auth import create_access_token, verify_access_token
from db import engine, get_db
from model import Message, MessageStatus, User
import model
from schema_pydantic import login, signup, token
from security import hash_password, verify_password
from fastapi import WebSocket,Query
from ws_chat import manager, handle_chat_ws
from model import Chat, ChatMember
from uuid import UUID
from sqlalchemy import func
from sqlalchemy import func as sqlfunc



model.Base.metadata.create_all(bind=engine)

app = FastAPI()
bearer = HTTPBearer()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
    db: Session = Depends(get_db),
):
    payload = verify_access_token(credentials.credentials)
    user = db.query(User).filter(User.email == payload["sub"]).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@app.post("/signup", response_model=token, status_code=status.HTTP_201_CREATED)
def sign_up(user: signup, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == user.email).first():
        raise HTTPException(status_code=409, detail="Email already registered")
    new_user = User(
        name=user.name,
        email=user.email,
        password=hash_password(user.password),
    )
    db.add(new_user)
    db.commit()
    access_token = create_access_token({"sub": new_user.email})
    return {"access_token": access_token, "token_type": "bearer"}


@app.post("/login", response_model=token)
def login_user(user: login, db: Session = Depends(get_db)):

    db_user = db.query(User).filter(User.email == user.email).first()

    if not db_user or not verify_password(user.password, db_user.password):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    access_token = create_access_token({"sub": db_user.email})

    return {"access_token": access_token, "token_type": "bearer"}


@app.get("/me")
def me(current_user: User = Depends(get_current_user)):
    return {
        "id": str(current_user.id),
        "name": current_user.name,
        "email": current_user.email,
        "about": current_user.about or "Hey there! I am using ChatApp"
    }

@app.websocket("/ws/chat")
async def chat_ws(
    websocket: WebSocket,
    token: str = Query(...),
    db: Session = Depends(get_db),
):
    try:
        payload = verify_access_token(token)
        user = db.query(User).filter(User.email == payload["sub"]).first()
        
        if not user:
            await websocket.close(code=4001)
            return
        
    except Exception:
        await websocket.close(code=4001)
        return

    await handle_chat_ws(websocket, user, db)


@app.post("/chats")
def create_direct_chat(
    other_user_email: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    other = db.query(User).filter(User.email == other_user_email).first()
    if not other:
        raise HTTPException(status_code=404, detail="User not found")

    if other.id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot chat with yourself")

    # check if chat already exists — return it instead of error
    my_chats = db.query(ChatMember).filter(
        ChatMember.user_id == current_user.id
    ).all()

    for m in my_chats:
        other_in_chat = db.query(ChatMember).filter(
            ChatMember.chat_id == m.chat_id,
            ChatMember.user_id == other.id,
        ).first()
        if other_in_chat:
            return {"chat_id": str(m.chat_id)}  # already exists, return it

    # create new chat
    chat = Chat(is_group=False)
    db.add(chat)
    db.flush()
    db.add(ChatMember(chat_id=chat.id, user_id=current_user.id))
    db.add(ChatMember(chat_id=chat.id, user_id=other.id))
    db.commit()
    db.refresh(chat)
    return {"chat_id": str(chat.id)}

@app.get("/chats")
def get_my_chats(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    ):
    memberships = db.query(ChatMember).filter(
        ChatMember.user_id == current_user.id
    ).all()

    result = []
    seen_chats = set()

    for m in memberships:
        if m.chat_id in seen_chats:
            continue
        seen_chats.add(m.chat_id)

        chat = db.query(Chat).filter(Chat.id == m.chat_id).first()
        if not chat:
            continue

        other_member = db.query(ChatMember).filter(
            ChatMember.chat_id == chat.id,
            ChatMember.user_id != current_user.id,
        ).first()
        if not other_member:
            continue

        other_user = db.query(User).filter(
            User.id == other_member.user_id
        ).first()
        if not other_user:
            continue

        last_msg = db.query(Message).filter(
            Message.chat_id == chat.id
        ).order_by(Message.created_at.desc()).first()

        my_membership = db.query(ChatMember).filter(
            ChatMember.chat_id == chat.id,
            ChatMember.user_id == current_user.id,
        ).first()

        if my_membership and my_membership.last_read_at:
            unread = db.query(func.count(Message.id)).filter(
                Message.chat_id == chat.id,
                Message.created_at > my_membership.last_read_at,
            ).scalar()
        else:
            unread = db.query(func.count(Message.id)).filter(
                Message.chat_id == chat.id,
            ).scalar()

        result.append({
            "chat_id":      str(chat.id),
            "name":         other_user.name,
            "email":        other_user.email,
            "last_message": last_msg.content if last_msg else "No messages yet",
            "last_time":    last_msg.created_at.isoformat() if last_msg else "",
            "unread_count": unread,
        })

    result.sort(
        key=lambda x: x['last_time'] if x['last_time'] else '',
        reverse=True,
    )

    return result


@app.get("/messages/{chat_id}")
def get_messages(
    chat_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
        ):
    from model import Message
    msgs = db.query(Message).filter(
        Message.chat_id == UUID(chat_id)
    ).order_by(Message.created_at.asc()).all()

    return [
        {
            "id":         str(m.id),
            "chat_id":    str(m.chat_id),
            "sender_id":  str(m.sender_id),
            "content":    m.content,
            "status":     m.status.value, 
            "status":     m.status.value,
            "created_at": m.created_at.isoformat(),
        }
        for m in msgs
    ]    

@app.get("/users")
def get_all_users(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    users = db.query(User).filter(User.id != current_user.id).all()
    return [
        {
            "id":    str(u.id),
            "name":  u.name,
            "email": u.email,
        }
        for u in users
    ]    


@app.post("/chats/{chat_id}/read")
def mark_as_read(
    chat_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from datetime import datetime, timezone

    # update last_read_at
    member = db.query(ChatMember).filter(
        ChatMember.chat_id == UUID(chat_id),
        ChatMember.user_id == current_user.id,
    ).first()
    if member:
        member.last_read_at = datetime.now(timezone.utc)

    # update all messages from other person to read
    db.query(Message).filter(
        Message.chat_id == UUID(chat_id),
        Message.sender_id != current_user.id,
        Message.status != MessageStatus.read,
    ).update({"status": MessageStatus.read})

    db.commit()
    return {"status": "ok"}



@app.get("/users/{user_id}/status")
def get_user_status(
    user_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == UUID(user_id)).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return {
        "is_online": user.is_online,
        "last_seen": user.last_seen.isoformat() if user.last_seen else None,
    }

@app.get("/chats/{chat_id}/member")
def get_other_member(
    chat_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    other = db.query(ChatMember).filter(
        ChatMember.chat_id == UUID(chat_id),
        ChatMember.user_id != current_user.id,
    ).first()
    if not other:
        raise HTTPException(status_code=404, detail="Member not found")
    return {"other_user_id": str(other.user_id)}

@app.patch("/me/about")
def update_about(
    payload: dict,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    current_user.about = payload.get("about", current_user.about)
    db.commit()
    return {"about": current_user.about}