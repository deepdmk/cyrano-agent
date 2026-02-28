# Claude Code Implementation Instructions
## Farmer Conversational AI -- Agno Framework PoC

---

## How To Use This Document

This document contains phased instructions for Claude Code to build the Farmer Conversational AI system. Each phase is a self-contained set of instructions. Feed one phase at a time to Claude Code along with the reference documents:

- `_ref/system-architecture.md` -- system design
- `_ref/database-schemas.md` -- all table schemas
- `_ref/agno-farmer-concept.md` -- project concept note
- `_ref/agno-farmer-agent-briefing.md` -- research and decisions from prior sessions

Claude Code also has access to these tools and skills:

- **Agno Claude Code Skill** (`.claude/skills/agno/SKILL.md`) -- Quick reference for Agno patterns (agents, teams, workflows, MCP, tools). Has detailed reference files in `.claude/skills/agno/references/` covering agents, teams, workflows, MCP, tools, learning, and models.
- **Context7 MCP Server** (configured in `.mcp.json`) -- Live API doc lookup for Agno. Use `resolve-library-id` then `query-docs` for current Agno patterns.

Always point Claude Code to the reference documents before giving it a phase. Example prompt prefix:

> Read the following reference documents first:
> - `_ref/system-architecture.md`
> - `_ref/database-schemas.md`
> - `.claude/skills/agno/SKILL.md` (and relevant reference files in `.claude/skills/agno/references/`)
> Use Context7 to verify any Agno API patterns you're unsure about.
> Then proceed with Phase X below.

---

## Phase 1: Project Setup and Database Infrastructure

### Objective
Set up the Python project structure, install dependencies, configure PostgreSQL with PgVector, and create all database tables.

### Instructions for Claude Code

```
Read _ref/system-architecture.md and _ref/database-schemas.md for full context.

Set up the Agno PoC project in this repository:

1. PROJECT STRUCTURE
   Create the following directory structure at the repo root:

   agno-server/
   ├── agents/
   │   ├── __init__.py
   │   ├── talk_agent.py
   │   ├── extract_agent.py
   │   ├── data_agent.py
   │   └── mood_agent.py
   ├── db/
   │   ├── __init__.py
   │   ├── connection.py        # Shared database connection config
   │   ├── models.py            # SQLAlchemy models for all tables
   │   └── init_db.py           # Script to create all tables
   ├── tools/
   │   ├── __init__.py
   │   ├── main_db_tools.py     # Tools for reading/writing Main DB
   │   ├── form_db_tools.py     # Tools for reading/writing Form Databases
   │   └── questions_tools.py   # Tools for reading/writing Questions Vector DB
   ├── config/
   │   ├── __init__.py
   │   └── settings.py          # Environment variables, DB URL, API keys
   ├── scripts/
   │   └── seed_test_data.py    # Optional: seed test data for development
   ├── requirements.txt
   ├── .env.example
   └── README.md

2. DEPENDENCIES (requirements.txt)
   agno
   anthropic
   psycopg[binary]
   sqlalchemy
   pgvector
   python-dotenv
   pydantic

3. DATABASE CONNECTION (db/connection.py)
   - Read DB URL from environment variable DATABASE_URL
   - Default: postgresql+psycopg://ai:ai@localhost:5532/ai
   - Create a shared PostgresDb instance from agno.db.postgres
   - Create a shared SQLAlchemy engine for custom tables

4. DATABASE MODELS (db/models.py)
   Create SQLAlchemy models for ALL tables defined in _ref/database-schemas.md:

   Main DB:
   - extracted_facts (with JSONB for extracted_fact, VARCHAR[] for domain)

   Agricultural Data DB:
   - fields
   - crops (FK to fields)
   - inputs (FK to fields, optional FK to crops)
   - yields (FK to crops, FK to fields)
   - weather_observations (optional FK to fields)

   Scheduling DB:
   - events

   Planning DB:
   - plans (optional FK to fields)

   Questions Vector DB:
   - session_questions (with VECTOR(768) column for embeddings)

   Use UUIDs for all primary keys. Include created_at and updated_at
   timestamps where specified in the schema doc.

5. DB INITIALIZATION (db/init_db.py)
   - Script that creates all tables if they don't exist
   - Ensures pgvector extension is enabled: CREATE EXTENSION IF NOT EXISTS vector
   - Can be run standalone: python -m db.init_db

6. ENVIRONMENT (.env.example)
   DATABASE_URL=postgresql+psycopg://ai:ai@localhost:5532/ai
   ANTHROPIC_API_KEY=your-key-here

7. README.md
   Brief setup instructions: install deps, set up Postgres with pgvector,
   copy .env.example to .env, run db init script.

Do NOT create any agent logic yet. This phase is infrastructure only.
Use the Agno PostgresDb class for session storage.
Use SQLAlchemy for all custom tables (Main DB, Form DBs, Questions).
```

---

## Phase 2: Agent Tool Functions

### Objective
Create the tool functions that agents will use to read from and write to the databases. These are plain Python functions decorated for Agno tool use.

### Instructions for Claude Code

```
Read _ref/system-architecture.md and _ref/database-schemas.md for full context.
Read the existing code in agno-server/db/ to understand the models and connection.

Create tool functions that agents will use to interact with the databases.
These are standard Python functions that the Agno agents will call as tools.

1. MAIN DB TOOLS (tools/main_db_tools.py)

   write_extracted_fact(
       session_id: str,
       raw_text: str,
       extracted_fact: dict,
       domain: list[str],
       confidence: str
   ) -> str
   # Writes a new record to extracted_facts. Returns the record ID.
   # verification_status defaults to 'unverified', routed defaults to False.

   get_unrouted_facts() -> list[dict]
   # Returns all extracted_facts where routed = False.
   # Used by the Data Agent to pick up new extractions.

   mark_fact_routed(fact_id: str) -> str
   # Sets routed = True on a specific record.
   # Called by Data Agent after processing.

2. FORM DATABASE TOOLS (tools/form_db_tools.py)

   For each Form Database table, create:
   - A create function (e.g., create_field, create_crop, create_event, create_plan)
   - An update function (e.g., update_field, update_crop)
   - A get-all function (e.g., get_all_fields, get_all_crops)
   - A get-by-id function (e.g., get_field, get_crop)

   Tables: fields, crops, inputs, yields, weather_observations, events, plans

   Each create function should accept all columns as parameters (except id,
   created_at, updated_at which are auto-generated). Return the new record ID.

   Each update function should accept the record ID and any fields to update
   as keyword arguments. Return confirmation.

   Each get-all function returns a list of dicts representing all records.
   Each get-by-id returns a single dict.

   Also create:

   get_database_summary() -> dict
   # Returns a summary of all Form Databases: how many records in each table,
   # and for each table, which records have NULL values in key fields.
   # This is what the Data Agent uses to identify gaps.

3. QUESTIONS VECTOR DB TOOLS (tools/questions_tools.py)

   write_question(
       session_id: str,
       question_text: str,
       source_database: str,
       source_table: str,
       source_field: str,
       source_record_id: str | None,
       priority: str,
       embedding: list[float]
   ) -> str
   # Writes a question to session_questions. Returns record ID.

   search_questions(
       query_embedding: list[float],
       session_id: str,
       limit: int = 5
   ) -> list[dict]
   # Vector similarity search. Returns the top N questions most similar
   # to the query embedding. Only returns questions for the given session_id.

   clear_session_questions(session_id: str) -> str
   # Deletes all questions for a given session_id.
   # Called at the start of each new session.

All tool functions should:
- Use the shared SQLAlchemy engine from db/connection.py
- Handle errors gracefully and return meaningful error messages
- Use type hints throughout
- Include docstrings that describe what the function does (Agno uses these
  for tool descriptions)
```

---

## Phase 3: Talk Agent

### Objective
Create the Talk Agent -- the front-of-house conversational agent that talks to the farmer.

### Instructions for Claude Code

```
Read _ref/system-architecture.md for full context on the Talk Agent's role.
Read the existing code in agno-server/ to understand the project structure,
db connection, and tool functions.

Create the Talk Agent in agents/talk_agent.py:

1. AGENT CONFIGURATION

   from agno.agent import Agent
   from agno.models.anthropic import Claude
   from agno.db.postgres import PostgresDb

   The Talk Agent should:
   - Use Claude (claude-sonnet-4-5-20250929) as its model
   - Use PostgresDb for session persistence
   - Have add_history_to_context=True
   - Have the search_questions tool from tools/questions_tools.py available
   - Accept a user_id and session_id at creation time

2. SYSTEM INSTRUCTIONS

   The Talk Agent's instructions should convey:

   - You are having a natural conversation with a smallholder farmer.
   - You are warm, patient, and genuinely interested in their work.
   - You never interrogate. You never ask rapid-fire questions.
   - You follow the farmer's lead. If they want to talk about weather,
     you talk about weather.
   - You have access to a tool that searches for questions the system
     needs answers to. Periodically (not every turn -- roughly every
     3-4 exchanges), use this tool to check if there are relevant
     questions that fit naturally into the current conversation.
   - When you find a relevant question, weave it into the conversation
     naturally. Do not say "the system needs to know" or "I have a
     question from the database." Just ask it as part of normal dialogue.
   - If the conversation is flowing well on a topic, do not interrupt
     with unrelated questions. Wait for a natural pause or transition.
   - Keep responses conversational. Short to medium length. Not formal.
   - If the farmer seems done talking, let them go. Do not push for
     more information.

3. TOOL INTEGRATION

   The Talk Agent needs a custom tool function that:
   - Takes no arguments (it uses the current conversation context internally)
   - Generates an embedding of a summary of the recent conversation
     (last 3-4 turns)
   - Calls search_questions with that embedding and the current session_id
   - Returns the top questions found (or "no questions available")

   Note: For the prototype, use a simple embedding approach. We can
   refine the embedder choice later. If needed, use OpenAI's embedding
   API or a local model. Document any embedding dependency clearly.

4. ENTRY POINT

   Create a simple way to run the Talk Agent in a terminal for testing:

   if __name__ == "__main__":
       # Create agent with a test user_id and session_id
       # Run an interactive loop: read user input, get agent response, repeat
       # Print agent responses to terminal

   This should be runnable as: python -m agents.talk_agent

Do NOT implement the Extract Agent, Data Agent, or Mood Agent yet.
Do NOT implement background processing yet.
The Talk Agent should work standalone for testing conversations.
The questions tool will return empty results until the Data Agent
populates the Questions Vector DB -- that is fine for this phase.
```

---

## Phase 4: Extract Agent

### Objective
Create the Extract Agent that reads session context and writes structured facts to the Main DB.

### Instructions for Claude Code

```
Read _ref/system-architecture.md and _ref/database-schemas.md for full context.
Read the existing code in agno-server/ to understand agents/, tools/, and db/.

Create the Extract Agent in agents/extract_agent.py:

1. AGENT CONFIGURATION

   The Extract Agent should:
   - Use Claude (claude-sonnet-4-5-20250929) as its model
   - Use PostgresDb for session persistence (shared session_id with Talk Agent)
   - Have add_history_to_context=True (so it can read the conversation)
   - Have the write_extracted_fact tool from tools/main_db_tools.py available
   - Accept a session_id at creation time (same session as the Talk Agent)

2. SYSTEM INSTRUCTIONS

   The Extract Agent's instructions should convey:

   - You are a data extraction specialist. You read conversations between
     a farmer and an AI assistant.
   - Your job is to identify any factual agricultural information in the
     conversation and record it as structured data.
   - You are looking for information relevant to three downstream databases:

     Agricultural Data: fields/plots, crops, planting/harvest details,
     inputs (fertilizer, pesticide), yields, weather observations,
     livestock, soil information.

     Scheduling: meetings, deliveries, market days, equipment bookings,
     labor arrangements, veterinary visits, any calendar events.

     Planning: future intentions about planting, expansion, investment,
     crop rotation, techniques to try, resource needs, timelines.

   - For each piece of information you extract, call the write_extracted_fact
     tool with:
     - raw_text: the farmer's actual words (quote or close paraphrase)
     - extracted_fact: a structured JSON object with relevant fields
       (e.g., {"crop_type": "maize", "action": "planted", "field": "north field", "date": "last Tuesday"})
     - domain: which database(s) this relates to (list of: "agricultural", "scheduling", "planning")
     - confidence: "high" if stated clearly, "medium" if somewhat ambiguous,
       "low" if inferred or very vague

   - Extract ONLY what the farmer actually said or clearly implied.
     Do not invent or assume information.
   - If the farmer mentions something you've already extracted in a
     previous run, do not duplicate it. Only extract NEW information.
   - Process the entire conversation history and extract everything relevant.

3. RUNNING THE EXTRACT AGENT

   The Extract Agent is triggered after the Talk Agent completes a turn.
   For now, create a function that can be called manually:

   def run_extraction(session_id: str) -> list[str]:
       # Creates the Extract Agent with the given session_id
       # Runs it with a prompt like: "Review the conversation and extract
       #   all agricultural information. Use the write_extracted_fact tool
       #   for each piece of information found."
       # Returns list of fact IDs that were created

   Also create a test entry point:

   if __name__ == "__main__":
       # Accept a session_id as argument
       # Run extraction
       # Print what was extracted

Do NOT implement background/async triggering yet. That comes later.
The Extract Agent should work when called manually against an existing session.
```

---

## Phase 5: Data Agent

### Objective
Create the Data Agent that reads the Main DB, fills Form Databases, and generates questions.

### Instructions for Claude Code

```
Read _ref/system-architecture.md and _ref/database-schemas.md for full context.
Read the existing code in agno-server/ to understand agents/, tools/, and db/.

Create the Data Agent in agents/data_agent.py:

1. AGENT CONFIGURATION

   The Data Agent should:
   - Use Claude (claude-sonnet-4-5-20250929) as its model
   - Have ALL form database tools available (create, update, get functions
     from tools/form_db_tools.py)
   - Have get_unrouted_facts and mark_fact_routed from tools/main_db_tools.py
   - Have write_question from tools/questions_tools.py
   - Have get_database_summary from tools/form_db_tools.py

2. SYSTEM INSTRUCTIONS

   The Data Agent's instructions should convey:

   - You are a data routing and gap analysis specialist.
   - Your job has two parts:

   Part 1 -- Route extracted facts to Form Databases:
   - Call get_unrouted_facts to get new extractions from the Main DB.
   - For each fact, determine which Form Database table(s) it belongs in.
   - Use the appropriate create or update tool to write the data.
   - If a record already exists (e.g., a field called "north field" is
     already in the fields table), UPDATE it rather than creating a duplicate.
   - After processing each fact, call mark_fact_routed to mark it done.

   Part 2 -- Identify gaps and generate questions:
   - Call get_database_summary to see the current state of all Form Databases.
   - Look for records with NULL values in important fields.
   - Look for logical gaps (e.g., a crop record with no planting date,
     a field with no size, a plan with no timeline).
   - For each gap, call write_question with:
     - question_text: a natural, conversational question the Talk Agent
       could ask (e.g., "How large is the north field?" not "Field size
       is NULL for record xyz")
     - source_database, source_table, source_field: where the gap is
     - source_record_id: which record if applicable
     - priority: "high" for critical missing data (crop type, field name),
       "medium" for useful but not essential, "low" for nice-to-have
     - embedding: generate an embedding of the question_text

   - Questions should sound like things a friend would ask, not a form
     would demand.

3. EMBEDDING GENERATION

   The Data Agent needs to generate embeddings for questions it writes.
   Create a utility function in tools/questions_tools.py:

   def generate_embedding(text: str) -> list[float]:
       # For prototype, use whatever embedding approach was set up in Phase 3
       # Must produce 768-dimensional vectors
       # Must be the SAME embedder used by the Talk Agent for search

   This function is shared between the Data Agent (writing) and the
   Talk Agent (searching).

4. RUNNING THE DATA AGENT

   Create a function that can be called manually:

   def run_data_routing(session_id: str) -> dict:
       # Creates the Data Agent
       # First clears the Questions Vector DB for this session
       # Runs Part 1: route unrouted facts
       # Runs Part 2: scan databases and generate questions
       # Returns summary: facts routed, questions generated

   Also create a test entry point:

   if __name__ == "__main__":
       # Accept a session_id as argument
       # Run data routing
       # Print summary

Do NOT implement background/async triggering yet.
The Data Agent should work when called manually after the Extract Agent has run.
```

---

## Phase 6: Mood Agent

### Objective
Create the Mood Agent that monitors conversation context and can inject instructions into the Talk Agent.

### Instructions for Claude Code

```
Read _ref/system-architecture.md for full context on the Mood Agent's role.
Read the existing code in agno-server/.

Create the Mood Agent in agents/mood_agent.py:

1. AGENT CONFIGURATION

   The Mood Agent should:
   - Use Claude (claude-sonnet-4-5-20250929) as its model
   - Use PostgresDb for its OWN session persistence (separate from Talk Agent)
   - Have update_memory_on_run=True (learns patterns across sessions)
   - Have add_history_to_context=True (reads the shared conversation)
   - Accept a user_id (same farmer) and the Talk Agent's session_id

2. SYSTEM INSTRUCTIONS

   The Mood Agent's instructions should convey:

   - You are an empathy and engagement specialist.
   - You read conversations between a farmer and an AI assistant.
   - Your job is to assess the farmer's emotional state and engagement level.
   - You track: energy level, patience, interest, frustration, confusion,
     fatigue, anger, disengagement.
   - You remember patterns across conversations. If this farmer typically
     gets tired after 15 minutes, note that. If they get frustrated when
     asked about money, note that.
   - Based on your assessment, output ONE of these instruction types:

     CONTINUE -- conversation is going well, no intervention needed
     ADJUST_TONE -- farmer seems [specific emotion], Talk Agent should
       [specific adjustment]
     CHANGE_TOPIC -- current topic is causing [specific issue], suggest
       moving to [alternative]
     WRAP_UP -- farmer is [specific signal], Talk Agent should begin
       closing the conversation gracefully
     END_NOW -- farmer is clearly done/upset/disengaged, end immediately
       with warmth

   - Always explain your reasoning briefly.
   - Your output will be injected directly into the Talk Agent's context.

3. MOOD STATE OUTPUT

   The Mood Agent should return a structured response:

   {
       "action": "CONTINUE" | "ADJUST_TONE" | "CHANGE_TOPIC" | "WRAP_UP" | "END_NOW",
       "reasoning": "Brief explanation of what signals you detected",
       "instruction_for_talk_agent": "Direct instruction text to inject into
         the Talk Agent's prompt, or null if CONTINUE"
   }

   Use Pydantic output schema to enforce this structure.

4. RUNNING THE MOOD AGENT

   def assess_mood(session_id: str, user_id: str) -> dict:
       # Creates the Mood Agent
       # Runs it against the current session
       # Returns the structured mood assessment

   if __name__ == "__main__":
       # Accept session_id and user_id as arguments
       # Run assessment
       # Print result

5. INTEGRATION POINT (do not implement yet, just document)

   Add a comment/docstring explaining how this will integrate:
   - The Mood Agent runs after each Talk Agent turn (or every N turns)
   - If action is not CONTINUE, the instruction_for_talk_agent text
     is prepended to the Talk Agent's next system prompt
   - This injection mechanism will be built in the orchestration phase
```

---

## Phase 7: Orchestration -- Tying It All Together

### Objective
Wire all agents together into the conversation loop described in the system architecture.

### Instructions for Claude Code

```
Read _ref/system-architecture.md for the full system flow.
Read all existing agent code in agno-server/agents/.
Read all tool functions in agno-server/tools/.

Create the orchestration layer that ties all agents into the conversation loop.

1. CONVERSATION LOOP (agents/orchestrator.py or main.py)

   Create a main conversation loop that implements this cycle:

   a. Accept user input (text for PoC)
   b. Check if Mood Agent has an instruction to inject
   c. Run the Talk Agent with the user input
      (plus any Mood Agent instruction prepended to context)
   d. Return the Talk Agent's response to the user
   e. In the background (async), trigger:
      - Extract Agent: process the new conversation turns
      - Data Agent: route new facts and generate questions
      - Mood Agent: assess current emotional state
   f. Store any Mood Agent instruction for the next turn
   g. Loop back to (a)

   The background agents (e, f) should not block the conversation.
   Use asyncio or Agno's post-hook mechanism to run them after the
   Talk Agent responds.

2. SESSION MANAGEMENT

   - At the start of a new session, clear the Questions Vector DB
     for the session using clear_session_questions
   - Generate a new session_id for each conversation session
   - The user_id persists across sessions (same farmer)
   - The Mood Agent uses its own session for memory persistence

3. MOOD AGENT INJECTION MECHANISM

   Design a way to inject the Mood Agent's instructions into the
   Talk Agent's prompt. Options to consider:

   Option A: Modify the Talk Agent's instructions list before each run,
   appending the Mood Agent's instruction as an additional instruction.

   Option B: Use Agno's session_state or a shared state object that
   the Talk Agent reads at the start of each turn.

   Option C: Prepend the Mood Agent instruction to the user message
   as a system note (e.g., "[System note: the farmer seems tired,
   begin wrapping up the conversation]").

   Choose whichever approach works cleanly with Agno's current API.
   Document the choice and reasoning.

4. BACKGROUND PROCESSING

   Use Agno's post-hook mechanism if possible:

   @hook(run_in_background=True)
   async def process_background(run_output, agent, session):
       # Run Extract Agent
       # Run Data Agent
       # Run Mood Agent

   If post-hooks don't work cleanly for this use case, use asyncio
   tasks triggered after the Talk Agent responds.

5. CLI ENTRY POINT

   Create a command-line interface for testing:

   python -m agno-server.main

   - Prompts for user_id (or uses a default test user)
   - Creates a new session
   - Enters the conversation loop
   - Prints Talk Agent responses
   - Runs background agents silently
   - Type "quit" or "exit" to end

This is the integration phase. All individual agents should already
work from previous phases. This phase connects them.
```

---

## Phase 8: Testing and Validation

### Objective
Test the full system with realistic farmer conversations and verify data flows correctly through all components.

### Instructions for Claude Code

```
Read _ref/system-architecture.md and _ref/database-schemas.md.
Read all code in agno-server/.

Create tests and validation scripts:

1. CONVERSATION SIMULATION (scripts/test_conversation.py)

   Create a script that simulates a farmer conversation by feeding
   pre-written messages through the orchestrator:

   Test messages should include:
   - Greetings and small talk ("Hello, how are you today?")
   - Crop information ("I planted maize in my north field last month")
   - Field details ("The north field is about two hectares")
   - Scheduling ("I have a delivery of fertilizer coming next Tuesday")
   - Planning ("Next season I want to try growing beans in the south field")
   - Weather ("We had heavy rain last week, some flooding near the river")
   - Emotional signals ("I'm tired of all this, nothing works anymore")

   After running the simulation, print:
   - Number of facts extracted to Main DB
   - Records created in each Form Database table
   - Questions generated in the Questions Vector DB
   - Mood Agent assessments

2. DATA FLOW VALIDATION (scripts/validate_data_flow.py)

   Create a script that checks:
   - Every extracted_fact in the Main DB has been routed (routed = True)
   - Every Form Database record traces back to a Main DB fact
   - The Questions Vector DB contains questions that reference real gaps
     in the Form Databases
   - No duplicate records in Form Databases

3. INDIVIDUAL AGENT TESTS

   For each agent, create a simple test that verifies:
   - Talk Agent: can hold a multi-turn conversation, responds naturally
   - Extract Agent: given a known conversation, extracts expected facts
   - Data Agent: given known facts, routes to correct tables and generates
     sensible questions
   - Mood Agent: given a conversation with clear emotional signals,
     produces appropriate assessments
```

---

## Notes for All Phases

### Agno Patterns to Follow

- Use `from agno.models.anthropic import Claude` with `Claude(id="claude-sonnet-4-5-20250929")`
- Use `from agno.db.postgres import PostgresDb` for session storage
- Agent tools are Python functions passed in the `tools=[]` parameter
- Custom tools use the `@tool` decorator from `agno.tools.decorator`
- Use `add_history_to_context=True` for agents that need conversation history
- Use `update_memory_on_run=True` for the Mood Agent's persistent memory
- For structured output, use `output_schema=` with a Pydantic BaseModel
- Post-hooks use the `@hook(run_in_background=True)` decorator from `agno.hooks`
- For background workflows, use `from agno.workflow import Workflow, Step`
- Never create agents inside loops -- reuse agent instances
- Both sync and async methods exist -- async variants are prefixed with `a` (e.g., `aprint_response`)

### Reference Resources Available to Claude Code

- `.claude/skills/agno/SKILL.md` -- Quick reference with code examples
- `.claude/skills/agno/references/agents.md` -- Full agent parameters and config
- `.claude/skills/agno/references/tools.md` -- Custom tool creation patterns
- `.claude/skills/agno/references/workflows.md` -- Workflow step types
- `.claude/skills/agno/references/learning.md` -- LearningMachine and memory
- `.claude/skills/agno/references/models.md` -- Model provider config
- Context7 MCP server -- live Agno doc lookups via `resolve-library-id` + `query-docs`

When unsure about an Agno API pattern, ALWAYS check the skill references and Context7 before guessing.

### What NOT to Do

- Do not use Teams for the background pipeline. Use Workflows or manual orchestration. Team coordination is LLM-driven and not deterministic.
- Do not put Workflows inside Teams directly. Agno does not support this.
- Do not use `enable_agentic_memory=True` unless explicitly needed. It is expensive (loads all memories into context on every update).
- Do not hardcode Form Database schemas into agent instructions. Use tool functions that expose the schema dynamically so the system remains adaptable.

### Environment Assumptions

- PostgreSQL with pgvector extension running locally (or provide connection string)
- ANTHROPIC_API_KEY set in environment
- Python 3.12+
- All work happens in the agno-server/ directory
