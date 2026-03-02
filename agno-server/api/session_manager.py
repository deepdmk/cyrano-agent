"""
Thread-safe session manager for Orchestrator instances across HTTP requests.
"""
import threading
import time
from typing import Optional

from agents.orchestrator import Orchestrator
from config.logging_config import get_logger

logger = get_logger("session_manager")


class SessionManager:
    """Manages Orchestrator instances keyed by session_id."""

    def __init__(self, ttl_seconds: int = 3600, cleanup_interval: int = 300):
        self._sessions: dict[str, tuple[Orchestrator, float]] = {}
        self._lock = threading.Lock()
        self._ttl = ttl_seconds
        self._cleanup_interval = cleanup_interval
        self._cleanup_thread: Optional[threading.Thread] = None
        self._shutdown_event = threading.Event()
        self._start_cleanup_thread()

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
                logger.info("Cleaning up expired session: %s", sid)
                orch.shutdown()
        return len(expired)

    def _start_cleanup_thread(self):
        """Start the background cleanup thread."""
        self._cleanup_thread = threading.Thread(
            target=self._cleanup_loop,
            daemon=True,
            name="session-cleanup"
        )
        self._cleanup_thread.start()
        logger.debug("Session cleanup thread started (interval: %ds)", self._cleanup_interval)

    def _cleanup_loop(self):
        """Background loop that periodically cleans up expired sessions."""
        while not self._shutdown_event.wait(timeout=self._cleanup_interval):
            try:
                expired_count = self.cleanup_expired()
                if expired_count > 0:
                    logger.info("Cleaned up %d expired sessions", expired_count)
            except Exception as e:
                logger.error("Error during session cleanup: %s", e)

    def shutdown_all(self):
        """Shutdown all active sessions and stop cleanup thread."""
        logger.info("Shutting down SessionManager...")
        self._shutdown_event.set()

        with self._lock:
            session_ids = list(self._sessions.keys())

        for sid in session_ids:
            try:
                with self._lock:
                    entry = self._sessions.pop(sid, None)
                if entry:
                    orch, _ = entry
                    logger.debug("Shutting down session: %s", sid)
                    orch.shutdown()
            except Exception as e:
                logger.error("Error shutting down session %s: %s", sid, e)

        logger.info("SessionManager shutdown complete (%d sessions closed)", len(session_ids))
