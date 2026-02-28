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

### Cyrano -- Talk Agent (Front-of-house)

**Name:** Cyrano
**Role:** Conversation partner to the farmer. Not an assistant, not a service. A neighbor who is genuinely curious about farming.

**Full personality and conversation design:** See `_ref/talk-agent-personality.md`

**Reads from:** Questions Vector DB (via periodic vector similarity checks against current conversation context)

**Writes to:** Sessions Table (all conversation context)

**Key behavioral rules:**
- Engages naturally. Does not interrogate.
- Follows the farmer's lead. Matches their energy and register.
- Never gives advice, never praises, never instructs, never corrects.
- Periodically checks the Questions Vector DB (roughly every 3-4 exchanges) and works relevant questions into the conversation naturally.
- Receives Mood Agent instructions via prepended system notes (DD-01) and adjusts without acknowledging the guidance.
- Speaks plainly. Short responses. One question at a time. Never references the system or the data capture.

**Agno implementation:** Agent with `db=` for session persistence, `add_history_to_context=True`. Custom tool functions to query the Questions Vector DB. Mood Agent instructions prepended to user messages by the orchestrator.

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

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FRONT OF HOUSE                               │
│                                                                     │
│   Farmer  ──text──>  ORCHESTRATOR  ──text──>  Farmer                │
│                          │    ▲                                     │
│                          │    │                                     │
│                          ▼    │                                     │
│                       ┌──────────┐                                  │
│                       │  CYRANO  │◄─── Questions Vector DB          │
│                       │  (Talk   │     (illusory -- cleared         │
│                       │  Agent)  │      each session)               │
│                       └────┬─────┘                                  │
│                            │                                        │
│                            ▼                                        │
│                     Sessions Table                                  │
│                     (permanent)                                     │
│                                                                     │
├─ ── ── ── ── ── ── ── ── ─┼── ── ── ── ── ── ── ── ── ── ── ── ──┤
│                            │                                        │
│                     BACKGROUND                                      │
│                     (post-hook, async,                               │
│                      does not block                                  │
│                      conversation)                                  │
│                            │                                        │
│              ┌─────────────┼──────────────┐                         │
│              │             │              │                          │
│              ▼             │              ▼                          │
│       ┌────────────┐       │       ┌────────────┐                   │
│       │  EXTRACT   │       │       │    MOOD    │                   │
│       │   AGENT    │       │       │   AGENT    │                   │
│       └─────┬──────┘       │       └─────┬──────┘                   │
│             │              │             │                          │
│             ▼              │             ▼                          │
│        ┌─────────┐         │       Mood Memory                     │
│        │ MAIN DB │         │       (persistent)                    │
│        │ (perm.) │         │             │                          │
│        └────┬────┘         │             ▼                          │
│             │              │       [System guidance]                │
│             ▼              │       prepended to next                │
│       ┌────────────┐       │       farmer message                  │
│       │   DATA     │       │       (DD-01)                         │
│       │   AGENT    │       │                                        │
│       └──┬───┬───┬─┘       │                                        │
│          │   │   │         │                                        │
│          ▼   ▼   ▼         │                                        │
│      ┌────┐┌────┐┌────┐    │                                        │
│      │ Ag ││Sch.││Plan│    │                                        │
│      │ DB ││ DB ││ DB │    │                                        │
│      └────┘└────┘└────┘    │                                        │
│      (Form Databases --    │                                        │
│       swappable)           │                                        │
│          │                 │                                        │
│          ▼                 │                                        │
│    Questions Vector DB ────┘                                        │
│    (illusory)                                                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Detailed Conversation Turn Cycle

```
TURN N:
========

  ┌─ Farmer sends message
  │
  ▼
  Orchestrator receives message
  │
  ├── Has Mood instruction from Turn N-1?
  │     YES: Prepend [System guidance: ...] to message (DD-01)
  │     NO:  Pass message unchanged
  │
  ▼
  Cyrano (Talk Agent) receives message
  │
  ├── Reads conversation history from Sessions Table
  ├── Every 3-4 turns: searches Questions Vector DB
  │     └── Vector similarity against current conversation
  │         └── Returns top questions that fit naturally
  ├── Generates response
  │     └── Natural, conversational, no advice, no praise
  │         └── May weave in a question from the queue
  │
  ▼
  Response returned to farmer
  │
  ▼
  Post-hook fires (background, non-blocking)  ──────────────────┐
  │                                                              │
  │  STEP 1: Extract Agent                                      │
  │  ├── Reads Sessions Table (shared session_id)               │
  │  ├── Identifies new agricultural facts                      │
  │  ├── Writes structured records to Main DB                   │
  │  └── Each record: raw_text, extracted_fact, domain,         │
  │       confidence, verification_status                       │
  │                                                              │
  │  STEP 2: Data Agent                                         │
  │  ├── Reads unrouted facts from Main DB                      │
  │  ├── Routes each fact to correct Form Database table        │
  │  │     ├── Agricultural DB (fields, crops, inputs,          │
  │  │     │    yields, weather)                                │
  │  │     ├── Scheduling DB (events)                           │
  │  │     └── Planning DB (plans)                              │
  │  ├── Marks each fact as routed                              │
  │  ├── Scans Form DBs for gaps (NULL fields, missing data)    │
  │  ├── Generates natural questions for each gap               │
  │  └── Writes questions to Questions Vector DB                │
  │       └── Available for Cyrano on next turn                 │
  │                                                              │
  │  STEP 3: Mood Agent                                         │
  │  ├── Reads Sessions Table                                   │
  │  ├── Assesses: fatigue, anger, disengagement,               │
  │  │    confusion, frustration                                │
  │  ├── Updates its own persistent memory                      │
  │  │    (learns this farmer's patterns over time)             │
  │  └── Outputs action:                                        │
  │       ├── CONTINUE      -> no instruction stored            │
  │       ├── ADJUST_TONE   -> instruction stored for Turn N+1  │
  │       ├── CHANGE_TOPIC  -> instruction stored for Turn N+1  │
  │       ├── WRAP_UP       -> instruction stored for Turn N+1  │
  │       └── END_NOW       -> instruction stored for Turn N+1  │
  │                                                              │
  └──────────────────────────────────────────────────────────────┘

  Farmer sends next message... (Turn N+1)
```

### Session Lifecycle

```
SESSION START (every system start = new session)
================================================

  1. Orchestrator generates new session_id
  2. user_id persists (same farmer)
  3. Clear Questions Vector DB (DD-03)
  4. Create Cyrano (Talk Agent) -- reused for entire session (DD-02)
  5. Check: new farmer or returning?
       │
       ├── NEW (no facts in Main DB for this user_id):
       │     Cyrano: "Hey, I'm Cyrano. I'm here to chat about
       │              what's going on with your farm whenever
       │              you've got a few minutes. No agenda, just
       │              conversation. What are you working on
       │              these days?"
       │
       └── RETURNING (facts exist in Main DB):
             Cyrano: "Good to talk again. Last time you mentioned
                      [references something from previous sessions]
                      -- how's that coming along?"

  6. Enter conversation turn cycle
  7. Background agents run after each turn (DD-02, DD-04)
  8. Session ends when farmer exits or Mood Agent triggers END_NOW


SESSION END
===========

  1. Wait for background tasks to complete
  2. Sessions Table retained (permanent)
  3. Main DB retained (permanent)
  4. Form Databases retained (permanent)
  5. Mood Agent memory retained (permanent)
  6. Questions Vector DB will be cleared on next session start


WHAT PERSISTS ACROSS SESSIONS:
==============================

  ┌──────────────────────┬────────────┐
  │ Data Store           │ Persists?  │
  ├──────────────────────┼────────────┤
  │ Sessions Table       │ Yes        │
  │ Main DB              │ Yes        │
  │ Agricultural Data DB │ Yes        │
  │ Scheduling DB        │ Yes        │
  │ Planning DB          │ Yes        │
  │ Mood Agent Memory    │ Yes        │
  │ Questions Vector DB  │ No (reset) │
  └──────────────────────┴────────────┘
```

### Data Flow: From Conversation to Database

```
EXAMPLE: Farmer says "I planted two hectares of maize in the north field last Tuesday"

  Farmer's words
       │
       ▼
  Cyrano responds naturally
  ("Two hectares of maize, that's a solid planting.
   How's the soil up in the north field?")
       │
       ▼
  Sessions Table records the full exchange
       │
       ▼
  Extract Agent processes the session
       │
       ├── Fact 1: {crop_type: "maize", action: "planted",
       │            field: "north field", date: "last Tuesday"}
       │            domain: ["agricultural"]
       │            confidence: "high"
       │
       ├── Fact 2: {field: "north field", size: "two hectares"}
       │            domain: ["agricultural"]
       │            confidence: "high"
       │
       ▼
  Main DB now has 2 new records (permanent)
       │
       ▼
  Data Agent reads unrouted facts
       │
       ├── Routes Fact 1 to:
       │     crops table: {crop_type: "maize", field_id: <north_field>,
       │                   planting_date: <resolved_date>, status: "planted"}
       │
       ├── Routes Fact 2 to:
       │     fields table: UPDATE north_field SET size_hectares = 2.0
       │
       ├── Scans for gaps:
       │     crops: variety = NULL, expected_harvest_date = NULL,
       │            seed_source = NULL
       │     fields: soil_type = NULL, irrigation_method = NULL
       │
       ├── Generates questions:
       │     "What variety of maize did you go with?"        (high)
       │     "When are you expecting to harvest the maize?"  (medium)
       │     "What's the soil like up in the north field?"   (medium)
       │
       ▼
  Questions Vector DB now has 3 questions
       │
       ▼
  Next turn: Cyrano searches Questions Vector DB
  and naturally asks about the maize variety or soil type
  when the moment fits
```

---

## Technology Stack (PoC)

- **Framework:** Agno (Python, `pip install agno`)
- **LLM Provider:** Anthropic (Claude) for all agents
- **Relational Database:** SQLite (file-based, no server) for Main DB + Form Databases + Agno sessions
- **Vector Database:** LanceDB (embedded, file-based) for Questions Vector DB
- **Runtime:** AgentOS (FastAPI)
- **Voice:** Deferred (text input/output for PoC)
- **iOS Client:** Deferred (server-side only for PoC)
- **Infrastructure:** Zero external dependencies. No Docker, no database server. All data in local `data/` directory.

---

## Design Decisions (Resolved)

All design decisions are documented in detail in `_ref/design-decisions.md`. Summary:

1. **Mood Agent prompt injection (DD-01):** Prepend instruction to user message as a system note. No agent reconfiguration needed.
2. **Background trigger mechanism (DD-02):** Agno post-hook (`@hook(run_in_background=True)`) as primary. Asyncio tasks as fallback.
3. **Questions Vector DB clearing (DD-03):** Explicit clearing in the orchestrator during session creation. Not via hooks.
4. **Background agent sequencing (DD-04):** Sequential -- Extract Agent, then Data Agent, then Mood Agent. No parallelism in prototype.
5. **Session management (DD-05):** Every system start creates a new session. No session resumption. User_id persists across sessions.
6. **Mood Agent memory (DD-06):** Persistent memory via `update_memory_on_run=True`, separate from Talk Agent session.
7. **Form Databases (DD-07):** Prototype stand-ins, designed to be swappable. Tool functions abstract the schemas.
8. **Embedding strategy (DD-08):** 768-dim embedder, shared utility function for write and search consistency.

Schemas are defined in `_ref/database-schemas.md`.
Implementation instructions are in `_ref/claude-code-instructions.md`.

---

## What Was Removed (and Why)

- **Questions Agent:** Merged into the Data Agent. The Data Agent identifies gaps as it fills Form Databases, which is the natural place to generate questions.
- **Conflict/TRM Agent:** Removed for PoC simplicity. Conflict resolution between contradictory data points is a future enhancement.
- **TTS/STT Agents:** Deferred. PoC is text-based. Voice layer will be added later.
- **iOS Client Integration:** Deferred. PoC is server-side only. The iOS client architecture exists in `ios-client/` for future integration.
