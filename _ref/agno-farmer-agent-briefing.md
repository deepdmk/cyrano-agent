# Agent Briefing: Agno Framework Research & Farmer Voice AI System

**Purpose:** This document orients an agent to the research, decisions, and design work completed across multiple sessions on the Agno framework and a proof-of-concept agricultural AI system.

---

## What We Are Building

A conversational AI system that allows smallholder farmers to populate agricultural databases through natural voice dialogue -- no forms, no structured data entry, no interface to learn. The farmer talks. The system listens, extracts, and builds structured records invisibly in the background.

The core insight driving the design: the barrier to agricultural digitization is not technology, it is the interface. Farmers already communicate everything we need to know. The system should fit their practice, not demand they fit ours.

Two deliverables have been produced so far:
- A concept note (`agno-farmer-concept.md`) suitable for stakeholder communication
- A system architecture diagram (`agno-farmer-architecture.mermaid`)

---

## The Agno Framework -- What We Know

Agno is an open-source Python framework (founded 2023, rebranded from Phidata in early 2025) for building production multi-agent systems. It has three layers:

- **Framework** -- Python library (`pip install agno`)
- **AgentOS** -- FastAPI runtime that serves agents as a scalable API
- **Control Plane** -- Browser UI at os.agno.com for monitoring and management

Key characteristics: stateless horizontal scaling, database-backed persistence, 40+ model providers, native multimodal (TTS/STT), and tight integration with Claude.

---

## Core Primitives

### Agents
The base unit. Each agent has a model, tools, instructions, memory, and knowledge. Agents are stateless at runtime -- all state lives in the database.

### Teams
A group of agents (or other teams) coordinated by a leader. Three modes:
- **Route** -- leader acts as a router, sends request to the best-fit member
- **Coordinate** -- leader delegates sequentially, members share context, leader synthesizes output
- **Tasks** -- leader decomposes a goal into tasks, executes autonomously across members

Teams can be nested. A `Team` instance can be placed inside another `Team`'s `members` list. The outer leader treats the inner team as a single callable unit.

**Important caveat:** `TeamMode.coordinate` produces sequential-ish behavior but sequencing is LLM-driven, not deterministic. Community users report occasional out-of-order execution even with coordination flags set.

### Workflows
Step-based execution pipelines with deterministic ordering. Each step can be an `Agent`, a `Team`, or a plain Python function. Purpose-built for guaranteed sequential execution.

Available step constructs:
- `Step` -- single unit of work
- `Parallel` -- concurrent execution
- `Condition` -- conditional branching
- `Loop` -- repetition
- `Router` -- dynamic path selection

**Rule of thumb:** Use Teams when you need intelligent, flexible coordination. Use Workflows when the order of operations is non-negotiable.

**Note on Workflows as Team members:** Workflows cannot currently be placed directly inside a Team's `members` list -- only `Agent` and `Team` instances are accepted. A thin wrapper Agent is needed if you want a Workflow inside a Team.

---

## Database & Memory Architecture

### Four Table Types

| Table | Created By | Purpose |
|---|---|---|
| `agno_sessions` | `db=` parameter on Agent/Team | Full conversation history and session state |
| `agno_memories` | `update_memory_on_run=True` | Long-term user facts extracted from conversations |
| Vector knowledge tables | `PgVector(table_name=...)` | Semantic search / RAG layer |
| Traces table | `AgentOS(tracing=True)` | Observability and eval data |

### Memory Control

Memory extraction is handled by a `MemoryManager` -- itself an LLM-powered agent making nested calls. Three operating modes:

1. **Automatic** (`update_memory_on_run=True`) -- fires after every run, uses `memory_capture_instructions` to guide what gets stored
2. **Agentic** (`enable_agentic_memory=True`) -- agent decides when to create/update/delete memories using a tool
3. **Manual** -- full CRUD via `AgentOSClient` API, bypasses agent entirely

**Token cost warning:** With agentic memory enabled and 100 existing memories, each memory update loads all 100 into a nested LLM context. A 10-message conversation triggering 7 memory updates can cost 8x the tokens of the same conversation without memory.

### Multi-Layer Vector Architecture

We designed separate vector tables by content type to avoid retrieval pollution:

| Layer | Table | Lifecycle | Written By |
|---|---|---|---|
| Sessions | Relational | Append-only | Talk Agent |
| Memories | Relational | Durable | Memory Agent |
| Questions | Vector | Short -- marked resolved when answered | Question Formation Agent |
| Issues | Vector | Medium -- blockers and gaps | Issue Agent |
| Insights | Vector | Long -- behavioral patterns | Insight Agent |
| Knowledge | Vector | Permanent -- reference documents | Manual / admin |
| Syntheses | Vector | Nightly -- cross-session patterns | Synthesis Agent |

The Talk Agent reads from multiple vector layers via custom tool functions (Agno's native `knowledge=` parameter only accepts one knowledge base, so additional layers are accessed as tools).

---

## Role Separation Pattern

A key architectural decision: the Talk Agent and Memory Agent are separate agents sharing a session ID.

**Talk Agent** -- handles conversation only, writes to session table, never extracts memories.

**Memory Agent** -- reads the same session after Talk Agent completes, distills the conversation to memories.

The link between them is a shared `session_id`. The Memory Agent is triggered asynchronously -- either via a background post-hook on the Talk Agent or on a cron schedule -- so it never blocks the farmer's conversation.

```python
# Talk Agent -- sessions only
talk_agent = Agent(db=db, add_history_to_context=True)

# Memory Agent -- reads sessions, writes memories
memory_agent = Agent(
    db=db,
    add_history_to_context=True,   # reads shared session
    update_memory_on_run=True,      # writes memories
    memory_manager=memory_manager
)
```

---

## Background Processing Architecture

Two mechanisms for async background work:

**Post-hooks (event-driven):**
```python
@hook(run_in_background=True)
async def extract_memories(run_output, agent, session):
    # Fires after Talk Agent responds, runs in separate async task
    memory_manager.create_user_memories(...)

talk_agent = Agent(post_hooks=[extract_memories])
```

**Cron scheduler (time-based):**
```python
agent_os = AgentOS(agents=[talk_agent, memory_agent], scheduler=True)
schedule_manager.create_schedule(
    agent_id="memory_agent",
    cron="0 * * * *",
    message="Process recent sessions"
)
```

Both approaches are fully isolated from the Talk Agent's request/response loop.

---

## Farmer System Architecture

```
Farmer (voice)
    |
    v
Voice Interface (TTS/STT)
    |
    v
Talk Agent  <---  Guide Agent (monitoring tone, fatigue, engagement)
    |
    v
Session Table
    |
    +-- [post-hook, async] --> Extraction Agent --> Memory Table
                                                         |
                                                         +--> Database Agent --> Farm Production DB
                                                         |                   --> Crop Growth DB
                                                         |                   --> Scheduler DB
                                                         |
                                                         +--> Question Formation Agent --> Question Queue (vector)
                                                         |
                                                         +--> Validation Agent --> Validation Queue (vector)
                                                              |
                                                              v
                                              Talk Agent reads questions naturally into conversation
```

**The Guide Agent** monitors the conversation in parallel, tracking tone, engagement, and fatigue signals. It signals the Talk Agent to wrap up gracefully when the farmer is tiring. The Talk Agent never interrogates -- it finds natural moments in conversation to surface questions from the queue.

---

## Implementation Notes & Decisions

**Embedder fine-tuning:** Recommended base model is `BAAI/bge-base-v1.5` or `intfloat/e5-base-v2` (768-dim). Training data: 2,000--5,000 retrieval triplets generated synthetically from existing knowledge base content. Critical: switching embedders later requires full re-embedding of all vector tables -- dimension consistency must be locked early.

**AgentOS API triggers:** Six mechanisms for invoking agents -- direct Python call, HTTP API via AgentOS, cron scheduler, tool calls (LLM-initiated), interface integrations (Slack, WhatsApp, AG-UI), and team/workflow orchestration.

**Open WebUI integration:** Community pipe function exists for using Agno agents as selectable models in Open WebUI. Uses `host.docker.internal` for Docker-to-Docker networking. Limitation: tool call traces don't render natively in Open WebUI.

**Claude Skills for Agno (agno-skills):** A Claude Code skill (`agno-agi/agno-skills`) that gives Claude Code live API reference for Agno agents, teams, workflows, MCP, tools, and models. This is a developer productivity tool, not a runtime component -- it helps write better Agno code but does not control agent behavior at runtime.

**Sequential execution in background pipeline:** The background processing layer (Extraction → Validation → Database → Question Formation) should use a `Workflow` with sequential `Step` objects, not a `Team`. Team coordination is LLM-driven and not guaranteed to be strictly sequential. Workflow steps are deterministic.

---

## Open Questions

- Voice interface implementation specifics -- ElevenLabs vs OpenAI audio, latency targets for field conditions
- Guide Agent monitoring mechanism -- does it read the same session in real-time or receive signals via a shared state object?
- Local language support -- target dialects for initial proof of concept
- Database schema for the three agricultural databases (Farm Production, Crop Growth, Scheduler)
- Offline/low-connectivity resilience -- queue-and-sync pattern for rural field conditions

---

## Key Source

Official Agno documentation: `docs.agno.com`. The framework rebranded from Phidata in early 2025 and the API shifted notably -- always verify against current docs rather than cached blog posts or older tutorials.
