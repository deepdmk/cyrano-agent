# Update Instructions 04: Python Logging

## Context

The system currently uses `print()` statements throughout. This update replaces them with Python's `logging` module, providing structured output with timestamps, agent names, and log levels. Logs go to both the console and a persistent log file at `data/cyrano.log`.

Read these documents before making changes:
- `_ref/system-architecture.md`
- `_ref/design-decisions.md`
- `CLAUDE.md`

---

## Update 1: Create Logging Configuration Module

**File:** `agno-server/config/logging_config.py` (NEW)

Create this file:

```python
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
```

---

## Update 2: Add Logging to the Orchestrator

**File:** `agno-server/agents/orchestrator.py`

Add the import at the top (after existing imports):

```python
from config.logging_config import get_logger

logger = get_logger("orchestrator")
```

Replace every `print()` call with the appropriate logger call. Here are the specific replacements:

**Line 86** -- `print(f"Session started: {self.state.session_id}")`
Replace with:
```python
logger.info("Session started: %s (user: %s)", self.state.session_id, self.state.user_id)
```

**Line 202** -- `print(f"  [Background] Extracted {len(fact_ids)} facts")`
Replace with:
```python
logger.info("Extract Agent: %d facts extracted", len(fact_ids))
```

**Lines 207-208** -- the routing print
Replace with:
```python
logger.info("Data Agent: routed %d facts, generated %d questions",
            routing_results['facts_routed'], routing_results['questions_generated'])
```

**Line 215** -- `print(f"  [Background] Error in pipeline: {e}")`
Replace with:
```python
logger.error("Background pipeline error: %s", e, exc_info=True)
```

**Line 240** -- the mood print
Replace with:
```python
logger.info("Mood Agent: %s - %s", assessment.action.value, assessment.reasoning[:80])
```

**Line 245** -- `print(f"  [Background] Mood assessment error: {e}")`
Replace with:
```python
logger.error("Mood assessment error: %s", e, exc_info=True)
```

**Line 263** -- `print(f"Background task error: {e}")`
Replace with:
```python
logger.error("Background task error: %s", e, exc_info=True)
```

**Lines 283-290** -- the CLI startup banner. Keep these as `print()` since they are user-facing terminal output, not logs.

**Line 296** -- `print(f"Cyrano: {initial_response}\n")` -- Keep as `print()` (user-facing).

**Lines 306-319** -- the user-facing conversation loop prints. Keep these as `print()`.

**Lines 322-326** -- Keep as `print()` (user-facing goodbye).

Add logging for the conversation turn itself. Inside `process_message`, after `self.state.turn_count += 1`, add:

```python
logger.debug("Turn %d: user message (%d chars)", self.state.turn_count, len(user_message))
```

After `response_text = response.content`, add:

```python
logger.debug("Turn %d: Cyrano response (%d chars)", self.state.turn_count, len(response_text))
```

If a mood instruction is being prepended, log it. After the `if self.state.mood_instruction:` block, add:

```python
if self.state.mood_instruction:
    logger.info("Mood injection: %s", self.state.mood_instruction[:80])
```

---

## Update 3: Add Logging to Talk Agent

**File:** `agno-server/agents/talk_agent.py`

Add the import at the top:

```python
from config.logging_config import get_logger

logger = get_logger("talk_agent")
```

In the `create_talk_agent` function, after the agent is created, add:

```python
logger.debug("Talk agent created for session %s, user %s", session_id, user_id)
```

Keep all `print()` calls in the `if __name__ == "__main__"` block (direct testing mode) as-is since those are user-facing CLI output.

---

## Update 4: Add Logging to Extract Agent

**File:** `agno-server/agents/extract_agent.py`

Add the import at the top:

```python
from config.logging_config import get_logger

logger = get_logger("extract_agent")
```

In the `run_extraction` function, add logging:
- At the start: `logger.debug("Running extraction for session %s", session_id)`
- After facts are extracted: `logger.info("Extracted %d facts from session %s", len(fact_ids), session_id)`
- On error: `logger.error("Extraction failed for session %s: %s", session_id, e, exc_info=True)`

Keep `print()` calls in the `if __name__ == "__main__"` block as-is.

---

## Update 5: Add Logging to Data Agent

**File:** `agno-server/agents/data_agent.py`

Add the import at the top:

```python
from config.logging_config import get_logger

logger = get_logger("data_agent")
```

In `run_data_routing`, add logging:
- At the start: `logger.debug("Running data routing for session %s", session_id)`
- After routing: `logger.info("Data routing complete: %d routed, %d questions", results['facts_routed'], results['questions_generated'])`

Replace the `print()` calls in the data routing function body (not the `__main__` block) with logger calls.

Keep `print()` calls in the `if __name__ == "__main__"` block as-is.

---

## Update 6: Add Logging to Mood Agent

**File:** `agno-server/agents/mood_agent.py`

Add the import at the top:

```python
from config.logging_config import get_logger

logger = get_logger("mood_agent")
```

In the `assess_mood` function, add logging:
- At the start: `logger.debug("Assessing mood for session %s, user %s", session_id, user_id)`
- After assessment: `logger.info("Mood assessment: action=%s, engagement=%s", assessment.action.value, assessment.engagement_level)`

Keep `print()` calls in the `if __name__ == "__main__"` block as-is.

---

## Update 7: Add Logging to Tools

**File:** `agno-server/tools/main_db_tools.py`

Add the import at the top:

```python
from config.logging_config import get_logger

logger = get_logger("tools.main_db")
```

Add logging to `write_extracted_fact`:
```python
logger.debug("Writing fact to session %s: domain=%s, confidence=%s", session_id, domain, confidence)
```

**File:** `agno-server/tools/form_db_tools.py`

Add the import at the top:

```python
from config.logging_config import get_logger

logger = get_logger("tools.form_db")
```

Add logging to create/update functions:
```python
logger.debug("Created %s record: %s", table_name, record_id)
logger.debug("Updated %s record: %s", table_name, record_id)
```

**File:** `agno-server/tools/questions_tools.py`

Add the import at the top:

```python
from config.logging_config import get_logger

logger = get_logger("tools.questions")
```

Add logging to key functions:
```python
# In write_question:
logger.debug("Question written: table=%s, field=%s, priority=%s", source_table, source_field, priority)

# In search_questions:
logger.debug("Searching questions: session=%s, limit=%d, results=%d", session_id, limit, len(results))

# In clear_session_questions:
logger.info("Cleared questions for session %s", session_id)
```

---

## Update 8: Initialize Logging at Entry Points

**File:** `agno-server/main.py`

Add at the very top of the file (after imports):

```python
from config.logging_config import setup_logging

setup_logging()
```

**File:** `agno-server/server.py`

Add at the top of the file (after imports):

```python
from config.logging_config import setup_logging

setup_logging()
```

---

## Update 9: Add Logging to Database Initialization

**File:** `agno-server/db/init_db.py`

Add the import at the top:

```python
from config.logging_config import get_logger, setup_logging

logger = get_logger("db.init")
```

At the start of the init function, call `setup_logging()` (in case init_db is run directly).

Replace the `print()` calls with logger calls:
- `print("SQLite tables created successfully")` -> `logger.info("SQLite tables created successfully")`
- Table listing prints -> `logger.info("Created table: %s", table_name)`
- LanceDB prints -> `logger.info("LanceDB initialized at: %s", LANCEDB_DIR)`
- Final print -> `logger.info("Database initialization complete")`

---

## Update 10: Add Log File to .gitignore

**File:** `agno-server/.gitignore` (or project root `.gitignore`)

Add:

```
data/cyrano.log
```

---

## Update 11: Update CLAUDE.md

**File:** `CLAUDE.md` (project root)

Add to the Key Files table:

```
| `agno-server/config/logging_config.py` | Centralized logging configuration |
```

Add a new section after Database Structure:

```
## Logging

All modules use Python's `logging` module via the centralized config:

    from config.logging_config import get_logger
    logger = get_logger(__name__)

Logs go to both the console and `data/cyrano.log`. The log file persists across sessions and captures DEBUG-level detail. Console output defaults to INFO level.

Log format: `timestamp | level | module | message`

To view logs in real time: `tail -f data/cyrano.log`
```

---

## Summary of Changes

| File | What Changes | Why |
|------|-------------|-----|
| config/logging_config.py | New file | Centralized logging setup |
| agents/orchestrator.py | Replace prints with logger | Structured pipeline logging |
| agents/talk_agent.py | Add logger | Agent activity logging |
| agents/extract_agent.py | Add logger | Extraction logging |
| agents/data_agent.py | Add logger | Routing logging |
| agents/mood_agent.py | Add logger | Mood assessment logging |
| tools/main_db_tools.py | Add logger | DB write logging |
| tools/form_db_tools.py | Add logger | Form DB logging |
| tools/questions_tools.py | Add logger | Vector search logging |
| main.py | Call setup_logging() | Initialize on CLI start |
| server.py | Call setup_logging() | Initialize on server start |
| db/init_db.py | Replace prints, add logger | Init logging |
| .gitignore | Add cyrano.log | Keep logs out of git |
| CLAUDE.md | Add logging docs | Documentation |

---

## What You Get After This Update

**Console output** during a conversation will look like:

```
2026-02-28 14:23:01 | INFO    | orchestrator         | Session started: abc-123 (user: test_farmer)
2026-02-28 14:23:05 | INFO    | orchestrator         | Extract Agent: 3 facts extracted
2026-02-28 14:23:06 | INFO    | orchestrator         | Data Agent: routed 3 facts, generated 5 questions
2026-02-28 14:23:07 | INFO    | orchestrator         | Mood Agent: CONTINUE - Farmer seems engaged and responsive
```

**Log file** (`data/cyrano.log`) captures the same plus DEBUG-level detail:

```
2026-02-28 14:23:01 | DEBUG   | tools.questions      | Cleared questions for session abc-123
2026-02-28 14:23:01 | DEBUG   | talk_agent           | Talk agent created for session abc-123, user test_farmer
2026-02-28 14:23:01 | INFO    | orchestrator         | Session started: abc-123 (user: test_farmer)
2026-02-28 14:23:03 | DEBUG   | orchestrator         | Turn 1: user message (52 chars)
2026-02-28 14:23:04 | DEBUG   | orchestrator         | Turn 1: Cyrano response (145 chars)
2026-02-28 14:23:05 | DEBUG   | extract_agent        | Running extraction for session abc-123
2026-02-28 14:23:05 | DEBUG   | tools.main_db        | Writing fact to session abc-123: domain=['agricultural'], confidence=high
2026-02-28 14:23:05 | INFO    | extract_agent        | Extracted 3 facts from session abc-123
2026-02-28 14:23:06 | DEBUG   | tools.form_db        | Created fields record: f7a2...
2026-02-28 14:23:06 | DEBUG   | tools.questions      | Question written: table=crops, field=crop_type, priority=high
2026-02-28 14:23:06 | INFO    | data_agent           | Data routing complete: 3 routed, 5 questions
2026-02-28 14:23:07 | INFO    | mood_agent           | Mood assessment: action=CONTINUE, engagement=high
```

**Monitor in real time** in a separate terminal:

```bash
tail -f data/cyrano.log
```

---

## Validation After Changes

1. Run `python -m db.init_db` -- should see logger-formatted output instead of plain prints
2. Run `python -m main` -- console should show timestamped log lines alongside the normal conversation
3. Check `data/cyrano.log` exists and contains DEBUG-level entries
4. Run `python -m server` -- should also log through the same system
5. Verify the CLI conversation still displays user-facing output (Cyrano responses, prompts) as plain text, not wrapped in log format
