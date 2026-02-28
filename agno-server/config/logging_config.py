"""
Centralized logging configuration for the Cyrano Agent system.

All modules should import their logger from here:
    from config.logging_config import get_logger
    logger = get_logger(__name__)
"""
import logging
import sys
from pathlib import Path

from config.settings import DATA_DIR

# Log file path
LOG_FILE = str(DATA_DIR / "cyrano.log")

# Whether logging has been configured
_configured = False


def setup_logging(level: int = logging.INFO):
    """
    Configure logging for the entire application.

    Call once at startup (main.py or server.py).
    Safe to call multiple times -- only configures on first call.

    Args:
        level: Logging level (default: INFO)
    """
    global _configured
    if _configured:
        return
    _configured = True

    # Log format: timestamp | level | logger name | message
    formatter = logging.Formatter(
        fmt="%(asctime)s | %(levelname)-7s | %(name)-20s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    # Console handler (stdout)
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)
    console_handler.setLevel(level)

    # File handler (append mode, persistent across sessions)
    file_handler = logging.FileHandler(LOG_FILE, mode="a", encoding="utf-8")
    file_handler.setFormatter(formatter)
    file_handler.setLevel(logging.DEBUG)  # File captures everything

    # Root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)
    root_logger.addHandler(console_handler)
    root_logger.addHandler(file_handler)

    # Quiet down noisy libraries
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("sentence_transformers").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    """
    Get a named logger.

    Usage:
        from config.logging_config import get_logger
        logger = get_logger(__name__)
        logger.info("Something happened")

    Args:
        name: Logger name (typically __name__)

    Returns:
        Configured logger instance
    """
    return logging.getLogger(name)
