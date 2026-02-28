# System Architecture -- Conversational AI for Smallholder Farmers
## Agno Framework Proof of Concept

---

## Overview

A conversational AI system that allows smallholder farmers to populate agricultural databases through natural voice dialogue. The farmer talks. The system listens, extracts structured data, fills external databases, and identifies what information is still missing -- all invisibly.

The core product is the conversational data capture layer. The downstream databases are swappable integration points that can be replaced by whatever systems the customer actually uses.

---

## Design Principles

1. **The farmer never sees a form.** The interface is conversation. The system adapts to the farmer, not the other way around.
2. **Separation of capture and categorization.** The Extract Agent captures raw structured data. The Data Agent categorizes and routes it. These are different jobs.
3. **The Main DB is the system's memory.** It is permanent, uncategorized (by downstream schema), and belongs to this system. The Form Databases are external products.
4. **Questions are ephemeral.** The Questions Vector DB is cleared between sessions. The Data Agent regenerates questions fresh each time based on the current state of all databases.
5. **Background processing never blocks the conversation.** The Talk Agent's job is the conversation. Everything else runs asynchronously.

---

## Agents

### Talk Agent (Front-of-house)

**Role:** Hold a natural, fluid conversation with the farmer.

**Reads from:** Questions Vector DB (via periodic vector similarity checks against current conversation context)

**Writes to:** Sessions Table (all conversation context)

**Behavior:**
- Engages naturally. Does not interrogate.
- Follows the farmer's lead.
- Periodically checks the Questions Vector DB, running a vector search against the current conversation to find relevant questions.
- Works those questions into the conversation at natural moments.
- Receives direct prompt injections from the Mood Agent to adjust behavior or wrap up.

**Agno implementation:** Agent with `db=` for session persistence, `add_history_to_context=True`. Custom tool functions to query the Questions Vector DB. Prompt is dynamically modified by the Mood Agent.

---

### Extract Agent (Background)

**Role:** Read the session context and extract structured information relevant to the Form Database schemas.

**Reads from:** Sessions Table

**Writes to:** Main DB

**Behavior:**
- Triggered asynchronously after Talk Agent turns (post-hook or short polling interval -- TBD).
- Knows the schemas of all Form Databases so it knows what to look for.
- Extracts structured records from the conversation: crop names, dates, field sizes, yields, plans, scheduled events, etc.
- Each record carries metadata: source session ID, timestamp, confidence level, verification status.
- Does not categorize into Form Database schemas. That is the Data Agent's job.
- Writes to the Main DB, which is permanent and append-only.

**Agno implementation:** Agent triggered via post-hook on Talk Agent or background workflow step. Reads shared session by session_id. Writes to Main DB (PostgreSQL).

---

### Data Agent (Background)

**Role:** Take extracted data from the Main DB, route it into the correct Form Databases, and identify gaps.

**Reads from:** Main DB, Form Databases (to assess current state)

**Writes to:** Form Databases (Agricultural Data, Scheduling, Planning), Questions Vector DB

**Behavior:**
- Reads new records from the Main DB.
- Maps each record against the Form Database schemas to determine where it belongs.
- Fills Form Database records as completely as possible.
- Identifies gaps: required fields that are empty, ambiguous data, contradictions with existing records.
- Writes natural-language questions into the Questions Vector DB for each gap identified.
- The Questions Vector DB is illusory -- cleared at the start of each new session and regenerated fresh based on current database state.

**Agno implementation:** Agent in a background Workflow, running after Extract Agent completes. Schema-aware via instructions or tool functions that expose Form Database structures. Writes questions to PgVector table.

---

### Mood Agent (Background)

**Role:** Monitor the conversation for emotional and engagement signals. Instruct the Talk Agent to adjust or end the conversation when needed.

**Reads from:** Sessions Table (conversation context)

**Writes to:** Talk Agent prompt (direct injection), its own persistent memory

**Behavior:**
- Runs in parallel with the conversation, reading session context.
- Tracks: anger, fatigue, disengagement, unresponsiveness, confusion, frustration.
- Maintains its own persistent session memory across conversations. Learns patterns over time (e.g., "this farmer disengages after 20 minutes," "this farmer gets irritable when asked about finances").
- When it detects a signal, it directly injects instructions into the Talk Agent's prompt: adjust tone, change topic, wrap up gracefully, schedule a continuation.

**Agno implementation:** Separate Agent with its own `db=` for persistent memory (`update_memory_on_run=True`). Communicates with Talk Agent via shared state or direct prompt modification mechanism (design TBD -- may require a custom middleware or shared session state object).

---

## Data Stores

### Sessions Table
- **Type:** Relational (PostgreSQL, `agno_sessions`)
- **Lifecycle:** Append-only during session, retained across sessions
- **Written by:** Talk Agent
- **Read by:** Extract Agent, Mood Agent, Talk Agent (own history)
- **Contains:** Full conversation history, turn-by-turn

### Main DB
- **Type:** Relational (PostgreSQL)
- **Lifecycle:** Permanent, append-only
- **Written by:** Extract Agent
- **Read by:** Data Agent
- **Contains:** Every structured fact extracted from conversations, with metadata (source session, timestamp, confidence, verification status, relevant domain tags)
- **Purpose:** The system's permanent knowledge store. This is what the system "knows" about the farmer.

### Questions Vector DB
- **Type:** Vector (PgVector)
- **Lifecycle:** Illusory -- cleared at the start of each new session
- **Written by:** Data Agent
- **Read by:** Talk Agent (via vector similarity search against current conversation)
- **Contains:** Natural-language questions representing data gaps in the Form Databases
- **Purpose:** Gives the Talk Agent contextually relevant questions to weave into conversation

### Form Databases (Prototype)
- **Type:** Relational (PostgreSQL)
- **Lifecycle:** Persistent, updated by Data Agent
- **Written by:** Data Agent
- **Read by:** Data Agent (to assess current state and identify gaps), external products (future)

Three databases for the prototype:

1. **Agricultural Data DB** -- Crop/planting/harvest/yield data, field information, inputs, weather observations. The data any agro-tracking product would need.

2. **Scheduling DB** -- Meetings, deliveries, shipping dates, market days, equipment bookings, labor coordination, recurring events. Calendar-oriented.

3. **Planning DB** -- Future intentions: planned crops, land use plans, budget intentions, timelines, methods, resource needs. Forward-looking data for projections and advice.

**Key design note:** These three databases are stand-ins. In production, they would be replaced by whatever external systems the customer uses. The Data Agent is an integration layer that adapts to the target schemas.

---

## System Flow

```
1. Farmer speaks (text input for PoC, voice later)
         |
         v
2. Talk Agent holds natural conversation
   - Reads from Questions Vector DB for relevant prompts
   - Receives Mood Agent instructions via prompt injection
   - Writes everything to Sessions Table
         |
         v
3. Sessions Table (permanent conversation record)
         |
         +-------> Extract Agent (async, background)
         |              |
         |              v
         |         Main DB (permanent structured extractions)
         |              |
         |              v
         |         Data Agent (async, background)
         |              |
         |              +---> Agricultural Data DB
         |              +---> Scheduling DB
         |              +---> Planning DB
         |              |
         |              +---> Questions Vector DB (illusory)
         |                         |
         |                         v
         |              Talk Agent reads questions into conversation
         |
         +-------> Mood Agent (async, parallel)
                        |
                        v
                   Monitors engagement, fatigue, anger
                   Injects instructions into Talk Agent prompt
                   Maintains own persistent memory
```

---

## Technology Stack (PoC)

- **Framework:** Agno (Python, `pip install agno`)
- **LLM Provider:** Anthropic (Claude) for all agents
- **Database:** PostgreSQL + PgVector
- **Runtime:** AgentOS (FastAPI)
- **Voice:** Deferred (text input/output for PoC)
- **iOS Client:** Deferred (server-side only for PoC)

---

## Open Design Questions

1. **Mood Agent prompt injection mechanism:** How does the Mood Agent modify the Talk Agent's prompt in real time within Agno? Options include shared session state, a custom tool, or a middleware layer. Needs prototyping.

2. **Background trigger mechanism:** Post-hooks after each Talk Agent turn vs. short polling interval vs. continuous workflow. Post-hooks are cleanest in Agno but need to be tested for reliability.

3. **Main DB record schema:** Defined separately (see schema document).

4. **Form Database schemas:** Defined separately (see schema document).

5. **Questions Vector DB clearing mechanism:** How and when exactly is the vector DB cleared between sessions? On session creation? Via a pre-hook on the Talk Agent?

---

## What Was Removed (and Why)

- **Questions Agent:** Merged into the Data Agent. The Data Agent identifies gaps as it fills Form Databases, which is the natural place to generate questions.
- **Conflict/TRM Agent:** Removed for PoC simplicity. Conflict resolution between contradictory data points is a future enhancement.
- **TTS/STT Agents:** Deferred. PoC is text-based. Voice layer will be added later.
- **iOS Client Integration:** Deferred. PoC is server-side only. The iOS client architecture exists in `ios-client/` for future integration.
