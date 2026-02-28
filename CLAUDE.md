# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cyrano Agent is a conversational AI system that captures agricultural data through natural dialogue with smallholder farmers. The farmer never sees forms or databases—data capture happens invisibly through conversation.

## Architecture

Four specialized agents communicate through shared databases:

1. **Cyrano (Talk Agent)** - Front-of-house conversational partner. Never gives advice, praise, or instructions. Asks one natural question at a time.
2. **Extract Agent** - Background: Extracts structured facts from conversation into Main DB
3. **Data Agent** - Background: Routes facts to Form DBs, generates natural-language questions for gaps
4. **Mood Agent** - Background: Monitors emotional state, injects behavioral guidance via DD-01

**Data Flow Per Turn:**
```
Farmer message → [Mood instruction prepended] → Cyrano responds →
Background: Extract Agent → Data Agent → Mood Agent → [instruction stored for next turn]
```

## Commands

```bash
cd agno-server

# Setup
pip install -r requirements.txt
cp .env.example .env  # Add ANTHROPIC_API_KEY
python -m db.init_db

# Run conversation
python -m main [user_id] [session_id]

# Run AgentOS server (monitoring dashboard)
python -m server
# Then open http://localhost:7777 for the dashboard
# API docs at http://localhost:7777/docs

# Test individual agents
python -m agents.talk_agent [user_id] [session_id]
python -m agents.extract_agent <session_id>
python -m agents.data_agent <session_id>
python -m agents.mood_agent <session_id> <user_id>
```

## Key Files

| Path | Purpose |
|------|---------|
| `agno-server/server.py` | AgentOS server for monitoring dashboard |
| `agno-server/agents/orchestrator.py` | Main entry point, ties agents together |
| `agno-server/agents/talk_agent.py` | Cyrano personality and conversation |
| `agno-server/tools/questions_tools.py` | LanceDB vector search for gap questions |
| `agno-server/tools/form_db_tools.py` | CRUD for all Form Database tables |
| `agno-server/config/settings.py` | DB paths, API keys, embedding model |
| `_ref/talk-agent-personality.md` | Cyrano's complete behavioral specification |
| `_ref/design-decisions.md` | DD-01 through DD-09 architectural decisions |

## Database Structure

All local, no Docker required:

- `data/cyrano.db` - SQLite: Main DB (extracted_facts) + Form DBs (fields, crops, inputs, yields, weather_observations, events, plans)
- `data/agno_sessions.db` - Agno session persistence
- `data/questions_vectordb/` - LanceDB: 768-dim vectors for gap questions (cleared each session)

## Critical Design Decisions

- **DD-01**: Mood Agent injects instructions via `[System guidance: ...]` prepended to user message
- **DD-05**: Every system start = new session (no resumption)
- **DD-07**: Form DBs are swappable stand-ins for external APIs
- **DD-09**: SQLite + LanceDB (no PostgreSQL/Docker)

## Agent Patterns

Uses Agno framework:
- `SqliteDb` for session persistence
- `add_history_to_context=True` to read prior turns
- Background agents via `ThreadPoolExecutor` (non-blocking)
- Mood Agent uses `update_memory_on_run=True` for cross-session learning

## Reference Documentation

- `_ref/system-architecture.md` - Complete technical blueprint
- `_ref/database-schemas.md` - All 8 table schemas
- `_ref/claude-code-instructions.md` - Phased implementation guide
- `.claude/skills/agno/SKILL.md` - Agno framework patterns
