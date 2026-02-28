# Update Instructions 03: AgentOS Integration (Monitoring Dashboard)

## Context

The system currently runs as a CLI application through `main.py` and `orchestrator.py`. This update adds AgentOS, Agno's built-in FastAPI runtime, so we can monitor agent activity through a web dashboard and API endpoints.

AgentOS gives us, with minimal code, a web interface showing every agent run, every input/output, session history, execution traces, and agent memory. This is valuable both for development debugging and for demonstrating the system at the hackathon.

Read these documents before making changes:
- `_ref/system-architecture.md` -- Overall architecture
- `_ref/design-decisions.md` -- All design decisions
- `.claude/skills/agno/SKILL.md` and reference files for Agno patterns
- Use Context7 to verify AgentOS API patterns if needed

**Important Agno references to check:**
- `agno.os.AgentOS` -- the main class
- `agno.db.sqlite.SqliteDb` -- session persistence (already in use)

---

## Design Approach

We take the **simpler path**: keep the existing orchestrator and expose all four agents through AgentOS individually. The CLI conversation mode continues to work as before. AgentOS runs alongside it as a monitoring and API layer.

This means:
- The orchestrator is unchanged -- it still coordinates the conversation loop
- AgentOS registers the four agents so their runs, sessions, and outputs are visible in the dashboard
- A new `server.py` file starts AgentOS
- The CLI mode (`python -m main`) and the server mode (`python -m server`) are separate entry points

---

## Update 1: New File -- AgentOS Server

**File:** `agno-server/server.py` (NEW)

Create this file:

```python
"""
AgentOS server for monitoring and API access to all agents.

Provides a web dashboard and REST API for inspecting agent runs,
sessions, traces, and outputs.

Run with: python -m server
"""
from agno.os import AgentOS
from agno.agent import Agent
from agno.models.anthropic import Claude
from agno.db.sqlite import SqliteDb

from config.settings import DEFAULT_MODEL_ID, AGNO_DB_FILE
from agents.talk_agent import CYRANO_INSTRUCTIONS
from agents.extract_agent import EXTRACT_AGENT_INSTRUCTIONS
from agents.data_agent import DATA_AGENT_INSTRUCTIONS
from agents.mood_agent import MOOD_AGENT_INSTRUCTIONS, MoodAssessment

# Import tools so agents can be fully configured
from tools.questions_tools import generate_embedding, search_questions
from tools.main_db_tools import (
    write_extracted_fact, get_unrouted_facts, mark_fact_routed,
    get_facts_by_session, get_recent_fact_for_user
)
from tools.form_db_tools import (
    create_field, update_field, get_all_fields, get_field, get_field_by_name,
    create_crop, update_crop, get_all_crops, get_crop, get_crops_by_field,
    create_input, update_input, get_all_inputs, get_input,
    create_yield, update_yield, get_all_yields, get_yield,
    create_weather_observation, update_weather_observation, get_all_weather_observations,
    create_event, update_event, get_all_events, get_event,
    create_plan, update_plan, get_all_plans, get_plan,
    get_database_summary
)
from tools.questions_tools import (
    write_question, clear_session_questions, generate_embedding, get_question_count
)
from agno.tools.decorator import tool


# Shared database for session persistence
db = SqliteDb(db_file=AGNO_DB_FILE)


# ============================================================
# Agent Definitions for AgentOS
# ============================================================

# Note: These are "registration" instances for AgentOS visibility.
# The orchestrator creates its own working instances separately.
# These let AgentOS track runs and provide the monitoring dashboard.

# --- Cyrano (Talk Agent) ---

@tool
def find_relevant_questions(conversation_summary: str) -> str:
    """
    Search for questions that fit naturally into the current conversation.

    Args:
        conversation_summary: Brief summary of recent conversation context

    Returns:
        Relevant questions or a message that none are available
    """
    embedding = generate_embedding(conversation_summary)
    questions = search_questions(
        query_embedding=embedding,
        session_id="server",  # Placeholder for server-mode runs
        limit=3
    )
    if not questions:
        return "No relevant questions at this time."
    result = "Questions that might fit the conversation:\n\n"
    for q in questions:
        result += f"- {q['question_text']} (about: {q['source_table']}.{q['source_field']}, priority: {q['priority']})\n"
    return result


cyrano_agent = Agent(
    name="Cyrano",
    model=Claude(id=DEFAULT_MODEL_ID),
    db=db,
    instructions=[CYRANO_INSTRUCTIONS],
    tools=[find_relevant_questions],
    add_history_to_context=True,
    num_history_runs=10,
    add_datetime_to_context=True,
    markdown=False,
)


# --- Extract Agent ---

@tool
def extract_fact(
    raw_text: str,
    extracted_fact: dict,
    domain: list[str],
    confidence: str
) -> str:
    """
    Write an extracted fact to the Main DB.

    Args:
        raw_text: The farmer's actual words
        extracted_fact: Structured JSON object with relevant fields
        domain: List of: "agricultural", "scheduling", "planning"
        confidence: "high", "medium", or "low"

    Returns:
        Confirmation with created fact ID
    """
    fact_id = write_extracted_fact(
        session_id="server",
        raw_text=raw_text,
        extracted_fact=extracted_fact,
        domain=domain,
        confidence=confidence
    )
    return f"Fact recorded with ID: {fact_id}"


extract_agent = Agent(
    name="Extract Agent",
    model=Claude(id=DEFAULT_MODEL_ID),
    db=db,
    instructions=[EXTRACT_AGENT_INSTRUCTIONS],
    tools=[extract_fact],
    add_history_to_context=True,
    num_history_runs=20,
    markdown=False,
)


# --- Data Agent ---

@tool
def add_question(
    question_text: str,
    source_database: str,
    source_table: str,
    source_field: str,
    priority: str,
    source_record_id: str = None
) -> str:
    """
    Write a question to the Questions Vector DB.

    Args:
        question_text: Natural-language conversational question
        source_database: "agricultural", "scheduling", or "planning"
        source_table: Table name (e.g., "fields", "crops")
        source_field: Field name that is missing
        priority: "high", "medium", or "low"
        source_record_id: Optional UUID of the record with the gap

    Returns:
        Confirmation message
    """
    embedding = generate_embedding(question_text)
    question_id = write_question(
        session_id="server",
        question_text=question_text,
        source_database=source_database,
        source_table=source_table,
        source_field=source_field,
        priority=priority,
        embedding=embedding,
        source_record_id=source_record_id
    )
    return f"Question recorded with ID: {question_id}"


@tool
def create_embedding(text: str) -> list[float]:
    """Generate an embedding vector for text."""
    return generate_embedding(text)


data_agent = Agent(
    name="Data Agent",
    model=Claude(id=DEFAULT_MODEL_ID),
    db=db,
    instructions=[DATA_AGENT_INSTRUCTIONS],
    tools=[
        get_unrouted_facts, mark_fact_routed,
        create_field, update_field, get_all_fields, get_field, get_field_by_name,
        create_crop, update_crop, get_all_crops, get_crop, get_crops_by_field,
        create_input, update_input, get_all_inputs, get_input,
        create_yield, update_yield, get_all_yields, get_yield,
        create_weather_observation, update_weather_observation, get_all_weather_observations,
        create_event, update_event, get_all_events, get_event,
        create_plan, update_plan, get_all_plans, get_plan,
        get_database_summary,
        add_question, create_embedding,
    ],
    markdown=False,
)


# --- Mood Agent ---

mood_agent = Agent(
    name="Mood Agent",
    model=Claude(id=DEFAULT_MODEL_ID),
    db=db,
    instructions=[MOOD_AGENT_INSTRUCTIONS],
    output_schema=MoodAssessment,
    add_history_to_context=True,
    num_history_runs=5,
    markdown=False,
)


# ============================================================
# AgentOS Setup
# ============================================================

agent_os = AgentOS(
    id="cyrano-os",
    name="Cyrano Agent System",
    description="Conversational data capture for smallholder farmers. "
                "Four Claude agents: Cyrano (conversation), Extract (fact extraction), "
                "Data (routing and gap analysis), Mood (engagement monitoring).",
    agents=[cyrano_agent, extract_agent, data_agent, mood_agent],
    db=db,
    tracing=True,          # Enable execution traces
    auto_provision_dbs=True,
)

app = agent_os.get_app()


if __name__ == "__main__":
    agent_os.serve(
        app="server:app",
        host="0.0.0.0",
        port=7777,
        reload=True,
    )
```

**What this does:**
- Registers all four Claude agents with AgentOS
- Each agent has its full instruction set and tools, so it can be run independently through the API
- `tracing=True` enables detailed execution traces (what tools were called, inputs/outputs, timing)
- The server starts on port 7777 with auto-reload for development
- `app = agent_os.get_app()` creates the FastAPI application

---

## Update 2: Connect the Orchestrator to AgentOS Agents

**File:** `agno-server/agents/orchestrator.py`

This is optional but recommended. If you want the orchestrator's agent runs to show up in AgentOS traces, you can modify the orchestrator to use the same agent instances that are registered with AgentOS, rather than creating its own.

However, for the simplest path, **leave the orchestrator unchanged**. The CLI mode and the server mode can coexist. The CLI creates its own agent instances. The server exposes the agents for API interaction and monitoring. Both write to the same databases, so data flows are visible either way.

If you want both modes to share agents (so CLI runs appear in the AgentOS dashboard), add an optional import in `orchestrator.py`:

```python
# At the top of orchestrator.py, add:
import os as _os

# In the Orchestrator.__init__ method, add an option:
def __init__(self, user_id: str, session_id: Optional[str] = None, use_server_agents: bool = False):
    ...
    self._use_server_agents = use_server_agents
```

This is a future enhancement. For now, keeping them separate is fine.

---

## Update 3: Update Requirements

**File:** `agno-server/requirements.txt`

Add `uvicorn` if it is not already installed as a dependency of agno:

```
uvicorn[standard]
```

Check first: `pip show uvicorn`. Agno may already pull it in. If it does, skip this.

The final requirements.txt should be:

```
agno
anthropic
sqlalchemy
lancedb
pyarrow
python-dotenv
pydantic
sentence-transformers
uvicorn[standard]
```

---

## Update 4: Update CLAUDE.md

**File:** `CLAUDE.md` (project root)

Add the server command to the Commands section:

Under `# Run conversation`, add:

```bash
# Run AgentOS server (monitoring dashboard)
python -m server
# Then open http://localhost:7777 for the dashboard
# API docs at http://localhost:7777/docs
```

Add to the Key Files table:

```
| `agno-server/server.py` | AgentOS server for monitoring dashboard |
```

---

## Summary of Changes

| File | What Changes | Why |
|------|-------------|-----|
| server.py | New file -- AgentOS entry point | Monitoring dashboard and API |
| requirements.txt | Add uvicorn (if needed) | Server runtime |
| CLAUDE.md | Add server command | Documentation |

---

## What You Get After This Update

Start the server with `python -m server` and open `http://localhost:7777`:

**Dashboard features:**
- See all four agents listed (Cyrano, Extract Agent, Data Agent, Mood Agent)
- Run any agent individually through the API
- View session history for each agent
- Inspect execution traces showing tool calls, inputs, and outputs
- View agent memory state
- OpenAPI docs at `/docs` for programmatic access

**For the hackathon demo:**
- Run the CLI conversation in one terminal (`python -m main`)
- Open the AgentOS dashboard in a browser
- Show the judges the agent activity in real time: facts being extracted, data being routed, questions being generated, mood assessments being produced

**API endpoints available:**
- `GET /agents` -- list all registered agents
- `POST /agents/{agent_id}/run` -- run an agent with a message
- `GET /sessions` -- list all sessions
- `GET /traces` -- view execution traces with filtering

---

## Validation After Changes

1. Start the server: `python -m server`
2. Open `http://localhost:7777` -- should see the AgentOS dashboard with four agents listed
3. Open `http://localhost:7777/docs` -- should see the Swagger API documentation
4. Send a test message to Cyrano through the API: `POST /agents/cyrano/run` with a message body
5. Check that the run appears in the traces view
6. Verify the CLI still works independently: `python -m main` in a separate terminal

---

## Future Enhancement: Unified Mode

A more advanced integration would merge the orchestrator into AgentOS as a Workflow, where:
- The conversation turn is a Workflow with sequential steps
- Cyrano runs as the first step
- Extract, Data, and Mood run as parallel or sequential follow-up steps
- AgentOS manages the full pipeline visibility

This would require restructuring the orchestrator into Agno's Workflow primitive. Worth doing after the hackathon, but not necessary for monitoring visibility now.
