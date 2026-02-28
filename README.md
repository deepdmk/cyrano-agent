# Cyrano Agent

![Python](https://img.shields.io/badge/Python-3.12+-blue)
![Claude](https://img.shields.io/badge/Claude-Sonnet%204.5-orange?logo=anthropic)
![Agno](https://img.shields.io/badge/Framework-Agno-purple)
![License](https://img.shields.io/badge/License-MIT-green)

A multi-agent conversational AI system that captures agricultural data through natural dialogue with smallholder farmers. The farmer never sees forms or databases—data capture happens invisibly through conversation.

## Problem Statement

Most digital agriculture tools ask farmers to adapt to technology: fill out forms, answer structured questions, log data into systems designed for desk workers. That is the wrong direction. People give better information in natural conversation than they do on forms—more detail, more context, more of the connections between things.

Cyrano solves this with four specialized Claude agents. The front-of-house agent focuses entirely on being a good conversation partner, while background agents extract structured facts, route them to databases, and identify gaps to fill naturally in future conversations. The farmer answers without knowing they just filled in a database field.

## Architecture

```mermaid
graph TB
    Farmer(["FARMER"])

    subgraph Orchestrator["ORCHESTRATOR"]
        Cyrano["CYRANO\nConversation Agent"]

        subgraph Pipeline["BACKGROUND PIPELINE"]
            ExtractAgent["EXTRACT\nAGENT"]
            DataAgent["DATA\nAGENT"]
            MoodAgent["MOOD\nAGENT"]
        end
    end

    QuestionsDB[("Questions\nVector DB")]
    MainDB[("Main DB")]
    FormDBs[("Form DBs")]

    Farmer <--> Cyrano
    Cyrano --> QuestionsDB
    ExtractAgent --> MainDB
    DataAgent --> FormDBs
    DataAgent --> QuestionsDB
    MoodAgent -.-> Cyrano
```

**Four Specialized Agents:**

| Agent | Role |
|-------|------|
| **Cyrano** | Front-of-house conversational partner. Listens, follows up naturally, never advises or interrogates. |
| **Extract Agent** | Pulls structured facts from conversation into Main DB. |
| **Data Agent** | Routes facts to Form DBs, generates natural-language questions for gaps. |
| **Mood Agent** | Monitors engagement, nudges Cyrano to adjust pace or wrap up warmly. |

## Features

- Natural conversation that feels like talking to a neighbor
- Invisible data capture—no forms, no structured questions
- Vector-based question surfacing when conversation drifts near data gaps
- Mood-aware engagement that respects the farmer's energy
- Swappable form databases as integration points for external products
- Local-first: SQLite + LanceDB, no Docker required

## Quick Start

### Prerequisites

- Python 3.12+
- Anthropic API key

### Installation

```bash
cd agno-server
pip install -r requirements.txt
cp .env.example .env  # Add your ANTHROPIC_API_KEY
python -m db.init_db
```

### Run

```bash
# CLI conversation
python -m main [user_id] [session_id]

# Web API server (port 8080)
python run_server.py

# Monitoring dashboard (port 7777)
python -m server
```

## External Services

| Service | Purpose |
|---------|---------|
| **Anthropic API** | Claude LLM for all agents |
| **Hugging Face Hub** | Embedding model (downloaded once, cached locally) |

All other dependencies run locally with no external network calls.

## Project Structure

```
cyrano-agent/
├── agno-server/          # Python backend
│   ├── agents/           # Four Claude agents + orchestrator
│   ├── api/              # FastAPI web server
│   ├── tools/            # Agent tool functions
│   ├── db/               # Database models
│   └── config/           # Settings and logging
├── ios-client/           # iOS app (Swift)
├── web-client/           # Web frontend
└── _ref/                 # Design docs and specifications
```

## Beyond Agriculture

This pattern applies anywhere people communicate naturally but would benefit from structured digital records:

- A patient describing symptoms
- A social worker conducting a home visit
- A refugee explaining their situation
- A non-literate artisan negotiating with a buyer

For populations that current digital tools exclude by design, the answer is not a simpler interface—it is no interface at all. Just conversation.

## Skills Demonstrated

- Multi-agent orchestration with Claude
- Agno framework for agent persistence and tooling
- Vector similarity search for contextual question surfacing
- Background processing with ThreadPoolExecutor
- SSE streaming for real-time responses

## License

MIT

## Acknowledgments

- Built with [Agno](https://github.com/agno-ai/agno) agent framework
- Powered by [Claude](https://anthropic.com) from Anthropic
- Embeddings via [Sentence Transformers](https://www.sbert.net/)
