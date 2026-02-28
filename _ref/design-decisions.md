# Design Decisions -- Farmer Conversational AI PoC

This document records specific design decisions made during architecture planning. These decisions should be treated as requirements by Claude Code when implementing.

---

## DD-01: Mood Agent Prompt Injection Mechanism

**Decision:** Option B -- Prepend to user message as a system note.

**How it works:** When the Mood Agent produces an instruction (anything other than CONTINUE), the orchestrator prepends it to the next user message before passing it to the Talk Agent. Format:

```
[System guidance: {mood_agent_instruction}]

{actual farmer message}
```

The Talk Agent sees this as context before the farmer's words. It does not say "the system told me" or reference the guidance to the farmer. It simply adjusts its behavior accordingly.

**Why:** Simplest approach for the prototype. No agent reconfiguration, no shared state plumbing, no custom middleware. Just string prepending in the orchestrator. Can be replaced with a more sophisticated mechanism later if needed.

---

## DD-02: Background Agent Trigger Mechanism

**Decision:** Primary -- Agno post-hook with `@hook(run_in_background=True)`. Fallback -- asyncio tasks.

**How it works:** A post-hook is registered on the Talk Agent. After each Talk Agent response, the hook fires in the background and runs the three background agents sequentially:

1. Extract Agent (reads session, writes to Main DB)
2. Data Agent (reads Main DB, fills Form DBs, writes questions)
3. Mood Agent (reads session, produces mood assessment)

The post-hook does not block the Talk Agent's response to the farmer.

```python
@hook(run_in_background=True)
async def process_background(run_output, agent, session):
    await run_extraction(session.session_id)
    await run_data_routing(session.session_id)
    mood_result = await assess_mood(session.session_id, agent.user_id)
    # Store mood_result for next turn
```

**Fallback:** If post-hooks prove unreliable during development, switch to manually spawning an asyncio task in the orchestrator after the Talk Agent responds.

**Why:** Post-hooks are the Agno-native mechanism for exactly this pattern. They keep the background logic attached to the agent rather than in external orchestration code. The asyncio fallback is there because the briefing notes mention that some Agno mechanisms can behave unexpectedly.

---

## DD-03: Questions Vector DB Clearing

**Decision:** Clear in the orchestrator during session creation, not via a hook.

**How it works:** When the orchestrator creates a new session (which happens every time the system starts), it explicitly calls `clear_session_questions()` before the first Talk Agent turn. This wipes all existing questions.

After clearing, the Data Agent runs its full scan of all Form Databases and regenerates fresh questions based on current database state.

```python
def start_new_session(user_id: str) -> str:
    session_id = generate_session_id()
    clear_session_questions(session_id=None)  # Clear ALL questions
    # Data Agent will regenerate on first background run
    return session_id
```

**Why:** Explicit clearing in the orchestrator is more predictable than relying on hook timing. The orchestrator is the one component that definitively knows a new session is starting.

---

## DD-04: Background Agent Sequencing

**Decision:** Sequential execution -- Extract Agent, then Data Agent, then Mood Agent. No parallelism in the prototype.

**How it works:** Within the post-hook (or asyncio task), the three agents run one after another:

1. **Extract Agent** runs first because it writes new facts to the Main DB.
2. **Data Agent** runs second because it depends on the Extract Agent's output (reads unrouted facts from Main DB).
3. **Mood Agent** runs third. It only reads the session context and is independent of the other two, but running it last keeps the logic simple.

**Why:** The Data Agent depends on Extract Agent output, so those two must be sequential. The Mood Agent could run in parallel with both, but for prototype simplicity, sequential execution avoids concurrency complexity. Can be optimized later.

---

## DD-05: Session Management

**Decision:** Every system start creates a new session. No session resumption.

**How it works:**

- When the farmer starts the system, a new `session_id` is generated.
- The `user_id` persists across sessions (same farmer).
- The Questions Vector DB is cleared.
- The Data Agent does a full scan of Form Databases and regenerates questions.
- There is no mechanism to resume a previous session.
- Previous sessions are retained in the Sessions Table (they are not deleted). The Extract Agent and Data Agent only process the current session.

**Why:** Keeps the prototype simple. Session resumption introduces complexity around state management, partial questions, and stale context. The Main DB and Form Databases persist across sessions, so no data is lost. The only thing that resets is the conversation context and the questions queue.

---

## DD-06: Mood Agent Memory Persistence

**Decision:** The Mood Agent maintains its own persistent memory across sessions using Agno's `update_memory_on_run=True`.

**How it works:** The Mood Agent has its own database session, separate from the Talk Agent's session. It uses Agno's built-in memory system to remember patterns about the farmer:

- "This farmer typically disengages after 20 minutes"
- "This farmer gets irritable when asked about finances"
- "This farmer is most engaged when talking about weather"

These memories persist across sessions and inform the Mood Agent's assessments over time. The Mood Agent becomes better at reading this specific farmer the more they interact.

**Why:** The whole point of the Mood Agent is empathy and adaptation. Without persistent memory, it would start from zero every session. A farmer who has used the system 20 times should get a more attuned experience than one using it for the first time.

---

## DD-07: Form Databases Are Prototype Stand-ins

**Decision:** The three Form Databases (Agricultural Data, Scheduling, Planning) are built and owned by us for the prototype but designed to be swappable.

**How it works:**

- The Data Agent's tool functions abstract the Form Database schemas. The agent uses tools like `create_field()`, `create_crop()`, `create_event()` rather than writing SQL directly.
- The Form Database schemas are not hardcoded into agent instructions. The Data Agent discovers what's available via `get_database_summary()` and the tool function signatures.
- In production, these tool functions would be replaced with API calls to whatever external system the customer uses (e.g., a real agro-tracking app, a real calendar system).

**Why:** The core value of the system is the conversational data capture layer (Talk Agent + Extract Agent + Main DB). The Form Databases are integration targets, not the product. Designing them as swappable from the start means the prototype demonstrates the real architecture, not a simplified version of it.

---

## DD-08: Embedding Strategy

**Decision:** Lock the embedding model early. Use a 768-dimensional embedder for the Questions Vector DB.

**Candidates:** BAAI/bge-base-v1.5 or intfloat/e5-base-v2 (both 768-dim).

**How it works:** A shared embedding utility function is used by both the Data Agent (when writing questions) and the Talk Agent (when searching for relevant questions). Both must use the same embedder.

```python
# tools/questions_tools.py
def generate_embedding(text: str) -> list[float]:
    # Uses the locked embedder model
    # Returns a 768-dimensional vector
    ...
```

**Why:** Changing the embedder later requires re-embedding all vectors in the Questions Vector DB. Since the Questions DB is illusory (cleared each session), this is less painful than it would be for a permanent vector store, but consistency between write and read is still essential.

**Note for prototype:** If a local or lightweight embedding approach is easier to set up initially, use it. The Questions DB is ephemeral, so re-embedding cost on model change is low. The important thing is that the same function is used for both writing and searching.

---

## DD-09: Simplified Database Stack (No Docker)

**Decision:** Replace PostgreSQL + pgvector (Docker) with SQLite + LanceDB (embedded, file-based).

**How it works:**

Three storage components, all file-based, all in a local `data/` directory:

1. **SQLite** (`data/cyrano.db`) for all relational tables: Main DB (`extracted_facts`), Agricultural DB (`fields`, `crops`, `inputs`, `yields`, `weather_observations`), Scheduling DB (`events`), Planning DB (`plans`).

2. **Agno SqliteDb** (`data/agno_sessions.db`) for Agno's built-in session persistence. Uses `agno.db.sqlite.SqliteDb` instead of `agno.db.postgres.PostgresDb`.

3. **LanceDB** (`data/questions_vectordb/`) for the Questions Vector DB. Embedded vector database with built-in similarity search. Replaces the `session_questions` PostgreSQL table with pgvector extension.

**Type mapping from PostgreSQL to SQLite:**

| PostgreSQL Type | SQLite Replacement | Notes |
|---|---|---|
| `UUID(as_uuid=True)` | `String(36)` | UUIDs stored as text strings |
| `JSONB` | `JSON` (SQLAlchemy) | Stored as TEXT in SQLite |
| `ARRAY(String)` | `Text` | JSON-serialized list |
| `Vector(768)` | N/A | Moved to LanceDB entirely |

**Why:** The prototype does not need a database server. SQLite handles all relational queries the system needs. LanceDB provides vector similarity search without any external process or extension. The entire database layer becomes "install pip packages and run `python -m db.init_db`" with zero infrastructure dependencies. Docker is no longer required for any part of the system.

**Trade-offs accepted:**
- SQLite has limited concurrency (single writer at a time). Acceptable for a single-user prototype where background agents run sequentially (DD-04).
- LanceDB is less mature than pgvector for production workloads. Acceptable because the Questions DB is ephemeral (cleared each session) and the prototype is single-user.
- No network-accessible database. Acceptable for a prototype that runs locally.

**Migration path to production:** When moving to production, swap `SqliteDb` back to `PostgresDb` and `LanceDB` to `PgVector` (or any managed vector DB). The tool function signatures and agent code remain unchanged. Only `db/connection.py`, `config/settings.py`, and `tools/questions_tools.py` need updating.
