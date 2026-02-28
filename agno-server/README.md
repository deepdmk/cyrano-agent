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

## Running

Start the main conversation loop:
```bash
python -m main
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
├── db/               # Database configuration and models
│   ├── connection.py
│   ├── models.py
│   └── init_db.py
├── tools/            # Agent tool functions
│   ├── main_db_tools.py
│   ├── form_db_tools.py
│   └── questions_tools.py
├── config/           # Configuration settings
│   └── settings.py
├── scripts/          # Test and validation scripts
└── main.py           # Entry point
```
