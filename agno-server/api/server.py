"""
FastAPI web server for the Cyrano multi-agent system.

Exposes the Orchestrator over HTTP with SSE streaming.
"""
import json
import traceback
from typing import Optional

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from api.session_manager import SessionManager
from config.logging_config import setup_logging

# Initialize logging before anything else
setup_logging()

app = FastAPI(title="Cyrano Agno Server", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://localhost:3000",
        "http://localhost:4173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

session_mgr = SessionManager()


class ChatRequest(BaseModel):
    message: str
    user_id: str = "web_user"
    session_id: Optional[str] = None


@app.get("/health")
def health():
    return {"status": "ok", "service": "cyrano-agno-server"}


@app.post("/chat")
def chat(req: ChatRequest):
    def generate():
        try:
            orch = session_mgr.get_or_create(
                user_id=req.user_id,
                session_id=req.session_id,
            )

            yield f"event: session\ndata: {json.dumps({'session_id': orch.session_id})}\n\n"

            for chunk in orch.process_message_stream(req.message):
                yield f"event: token\ndata: {json.dumps({'content': chunk, 'isDone': False})}\n\n"

            yield f"event: done\ndata: {json.dumps({'content': '', 'isDone': True, 'stopReason': 'end_turn'})}\n\n"

        except Exception as e:
            traceback.print_exc()
            yield f"event: error\ndata: {json.dumps({'error': str(e)})}\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")


@app.get("/session/{session_id}")
def get_session(session_id: str):
    orch = session_mgr.get_existing(session_id)
    if not orch:
        return {"error": "Session not found"}
    return orch.get_conversation_summary()


@app.on_event("shutdown")
def shutdown_event():
    """Gracefully shutdown all active sessions."""
    session_mgr.shutdown_all()
