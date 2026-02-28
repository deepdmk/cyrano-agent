"""
Thread-safe session manager for Orchestrator instances across HTTP requests.
"""
import threading
import time
from typing import Optional

from agents.orchestrator import Orchestrator


class SessionManager:
    """Manages Orchestrator instances keyed by session_id."""

    def __init__(self, ttl_seconds: int = 3600):
        self._sessions: dict[str, tuple[Orchestrator, float]] = {}
        self._lock = threading.Lock()
        self._ttl = ttl_seconds

    def get_or_create(self, user_id: str, session_id: Optional[str] = None) -> Orchestrator:
        """Get existing session or create a new one."""
        with self._lock:
            if session_id and session_id in self._sessions:
                orch, _ = self._sessions[session_id]
                self._sessions[session_id] = (orch, time.time())
                return orch

            orch = Orchestrator(user_id=user_id, session_id=session_id)
            orch.start_session()
            self._sessions[orch.session_id] = (orch, time.time())
            return orch

    def get_existing(self, session_id: str) -> Optional[Orchestrator]:
        """Get an existing session by ID, or None."""
        with self._lock:
            entry = self._sessions.get(session_id)
            if entry:
                orch, _ = entry
                self._sessions[session_id] = (orch, time.time())
                return orch
            return None

    def cleanup_expired(self):
        """Remove sessions that have exceeded TTL."""
        now = time.time()
        with self._lock:
            expired = [sid for sid, (_, ts) in self._sessions.items()
                       if now - ts > self._ttl]
            for sid in expired:
                orch, _ = self._sessions.pop(sid)
                orch.shutdown()
