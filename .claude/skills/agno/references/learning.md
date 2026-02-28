# Learning Reference

## Overview

The LearningMachine enables persistent learning across sessions through five distinct storage mechanisms:

1. **User Profile** - Structured user data (name, preferences, custom fields)
2. **User Memory** - Unstructured observations about users
3. **Session Context** - Current session state (goal, plan, progress)
4. **Entity Memory** - Facts about third-party entities
5. **Learned Knowledge** - Reusable insights and patterns

## Learning Modes

- `ALWAYS` - Automatic extraction after every response
- `AGENTIC` - Agent-triggered learning (more efficient)
- `PROPOSE` - Agent proposes, human confirms

## Basic Setup

```python
from agno.agent import Agent
from agno.db.postgres import PostgresDb
from agno.learn import LearningMachine, LearningMode, UserProfileConfig
from agno.models.google import Gemini

db = PostgresDb(db_url="postgresql+psycopg://ai:ai@localhost:5532/ai")

agent = Agent(
    model=Gemini(id="gemini-3-flash-preview"),
    db=db,
    learning=LearningMachine(
        user_profile=UserProfileConfig(mode=LearningMode.ALWAYS),
    ),
    markdown=True,
)

agent.print_response("Hi! I'm Alice, call me Ali.", user_id="alice@example.com", stream=True)
```

## Quick Setup

For minimal configuration with all stores enabled:

```python
agent = Agent(
    model=Gemini(id="gemini-3-flash-preview"),
    db=db,
    learning=True,  # Enable all stores with defaults
)
```

## User Profile Store

Captures structured profile fields automatically.

```python
from agno.learn import LearningMachine, UserProfileConfig, LearningMode
from pydantic import BaseModel

class CustomProfile(BaseModel):
    name: str = ""
    preferred_name: str = ""
    occupation: str = ""
    interests: list[str] = []

learning = LearningMachine(
    user_profile=UserProfileConfig(
        mode=LearningMode.ALWAYS,
        schema=CustomProfile,
    ),
)
```

## User Memory Store

Stores unstructured observations about users.

```python
from agno.learn import LearningMachine, UserMemoryConfig, LearningMode

learning = LearningMachine(
    user_memory=UserMemoryConfig(
        mode=LearningMode.AGENTIC,
        can_add=True,
        can_update=True,
        can_delete=True,      # Individual deletions
        can_bulk_delete=False, # Restrict bulk deletion
    ),
)
```

## Session Context Store

Tracks goal, plan, and progress for the current session.

```python
from agno.learn import LearningMachine, SessionContextConfig, LearningMode

learning = LearningMachine(
    session_context=SessionContextConfig(
        mode=LearningMode.ALWAYS,
        enable_planning=True,
    ),
)
```

## Entity Memory Store

Stores facts, events, and relationships about external entities.

```python
from agno.learn import LearningMachine, EntityMemoryConfig, LearningMode

learning = LearningMachine(
    entity_memory=EntityMemoryConfig(
        mode=LearningMode.AGENTIC,
    ),
)
```

## Learned Knowledge Store

Requires vector database integration for semantic search.

```python
from agno.learn import LearningMachine, LearnedKnowledgeConfig, LearningMode
from agno.vectordb.pgvector import PgVector

learning = LearningMachine(
    learned_knowledge=LearnedKnowledgeConfig(
        mode=LearningMode.AGENTIC,
        vectordb=PgVector(
            table_name="learned_knowledge",
            db_url="postgresql+psycopg://ai:ai@localhost:5532/ai",
        ),
    ),
)
```

## Accessing Stored Data

```python
# Print user profile
agent.learning_machine.user_profile_store.print(user_id="alice@example.com")

# Print user memories
agent.learning_machine.user_memory_store.print(user_id="alice@example.com")

# Print session context
agent.learning_machine.session_context_store.print(
    user_id="alice@example.com",
    session_id="my-session",
)

# Print entity memory
agent.learning_machine.entity_memory_store.print(user_id="alice@example.com")
```

## Full Example

```python
from agno.agent import Agent
from agno.db.postgres import PostgresDb
from agno.learn import (
    LearningMachine,
    LearningMode,
    UserProfileConfig,
    UserMemoryConfig,
    SessionContextConfig,
    EntityMemoryConfig,
)
from agno.models.google import Gemini

db = PostgresDb(db_url="postgresql+psycopg://ai:ai@localhost:5532/ai")

agent = Agent(
    model=Gemini(id="gemini-3-flash-preview"),
    db=db,
    learning=LearningMachine(
        user_profile=UserProfileConfig(mode=LearningMode.ALWAYS),
        user_memory=UserMemoryConfig(mode=LearningMode.AGENTIC),
        session_context=SessionContextConfig(
            mode=LearningMode.ALWAYS,
            enable_planning=True,
        ),
        entity_memory=EntityMemoryConfig(mode=LearningMode.AGENTIC),
    ),
    markdown=True,
)

# Agent learns about user across conversations
agent.print_response(
    "I'm Alice, a data scientist interested in ML.",
    user_id="alice@example.com",
    session_id="onboarding",
    stream=True,
)
```
