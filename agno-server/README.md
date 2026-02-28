# Farmer Conversational AI - Agno Server

A conversational AI system that allows smallholder farmers to populate agricultural databases through natural dialogue.

## Architecture

The system consists of 4 agents working in concert:

- **Talk Agent** - Front-of-house conversation with farmers
- **Extract Agent** - Extracts structured facts from conversations
- **Data Agent** - Routes facts to databases, generates questions for gaps
- **Mood Agent** - Monitors emotional state, injects behavioral instructions

## External Services

| Service | Purpose | When Called |
|---------|---------|-------------|
| **Anthropic API** | Claude LLM (`claude-sonnet-4-5-20250929`) | Every agent turn |
| **Hugging Face Hub** | Embedding model (`BAAI/bge-base-en-v1.5`) | First run only (cached locally) |

All other dependencies (SQLite, LanceDB, FastAPI) run locally with no external network calls.

## Setup

### Prerequisites

- Python 3.12+
- Anthropic API key

### Installation

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Copy environment file and configure:
```bash
cp .env.example .env
# Edit .env with your ANTHROPIC_API_KEY
```

3. Initialize the database:
```bash
python -m db.init_db
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key for Claude |
| `DATA_DIR` | No | Override default data directory (default: `data/`) |
| `LOG_PROMPTS` | No | Set to `1` to log full prompts sent to Cyrano |

## Running

```bash
# CLI conversation
python -m main [user_id] [session_id]

# Web API server (for web/mobile clients, port 8080)
python run_server.py [--port 8080] [--host 0.0.0.0]

# AgentOS monitoring dashboard (port 7777)
python -m server

# Health check (diagnostics)
python -m health_check
```

## Testing Individual Agents

```bash
# Talk Agent
python -m agents.talk_agent

# Extract Agent (requires session_id)
python -m agents.extract_agent <session_id>

# Data Agent (requires session_id)
python -m agents.data_agent <session_id>

# Mood Agent (requires session_id and user_id)
python -m agents.mood_agent <session_id> <user_id>
```

## Project Structure

```
agno-server/
├── agents/           # Agent implementations
│   ├── talk_agent.py
│   ├── extract_agent.py
│   ├── data_agent.py
│   ├── mood_agent.py
│   └── orchestrator.py
├── api/              # Web API server
│   ├── server.py     # FastAPI routes with SSE streaming
│   └── session_manager.py
├── db/               # Database configuration and models
│   ├── connection.py
│   ├── models.py
│   └── init_db.py
├── tools/            # Agent tool functions
│   ├── main_db_tools.py
│   ├── form_db_tools.py
│   └── questions_tools.py
├── config/           # Configuration settings
│   ├── settings.py
│   └── logging_config.py
├── main.py           # CLI entry point
├── server.py         # AgentOS monitoring dashboard
├── run_server.py     # Web API server entry point
└── health_check.py   # Diagnostic tool
```
