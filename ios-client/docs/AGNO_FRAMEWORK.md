# Agno Agent Framework

Comprehensive research on the Agno agent framework (formerly Phidata), covering its architecture, capabilities, voice support, and current state as of February 2026.

## Overview

**Agno** (from Greek "agnos," meaning "pure") is an open-source Python agent framework, formerly known as Phidata. The rebrand occurred around January 2025.

- **Current Version**: v2.5.3 (February 19, 2026)
- **Language**: Python 3.12+
- **License**: Open source
- **GitHub**: github.com/agno-agi/agno
- **Description**: "The runtime for agentic software"

## Core Architecture

### Three Fundamental Abstractions

1. **Agent**: Atomic unit with instructions, tools, context
2. **Team**: Coordinated agents that plan, communicate, and delegate
3. **Workflow**: Structured multi-step pipelines with conditions, loops, and parallelism

### Key Design Principles

- **Stateless runtime**: All state lives in the database; agents are pure execution engines
- **Session-scoped**: FastAPI backend is horizontally scalable
- **Model-agnostic**: Works with 40+ models across 20+ providers

### Performance Benchmarks (Apple M4 MacBook Pro, 1000 runs)

| Metric | Agno | LangGraph | PydanticAI | CrewAI |
|--------|------|-----------|------------|--------|
| Instantiation | ~2 us | ~1058 us | ~114 us | ~140 us |
| Memory per agent | ~3.75 KiB | ~180 KiB | ~14.5 KiB | ~37 KiB |

Agno is 529x faster than LangGraph and uses 24x less memory.

## Capabilities

### Tools & MCP
- 100+ built-in tool integrations
- Full Model Context Protocol (MCP) support
- `MCPTools` and `MultiMCPTools` for connecting to external servers
- Supports stdio, Streamable HTTP, and SSE transports

### Memory
- **Session memory**: Conversation history within a session
- **Long-term memory**: Cross-session recall of user facts/preferences
- **Storage backends**: PostgreSQL, MongoDB, SQLite, DynamoDB, Redis

### Knowledge Bases (RAG)
- Vector stores: PgVector, ChromaDB, Pinecone, Qdrant, Milvus, Weaviate, LanceDB, and more
- Data readers: PDF, Excel, CSV, website crawling

### Reasoning
- Reasoning agents (use one model to reason, another to generate)
- ReasoningTools for "think" and "analyze" steps
- Structured output with Pydantic validation

### Guardrails
- Built-in and custom guardrails
- JSON/structured output validation
- Runtime approval enforcement (pause for human review)

### Workflows 2.0
- `Step`: Single unit of work
- `Loop`: Repetition
- `Parallel`: Concurrent execution
- `Condition`: Conditional logic
- `Router`: Branching based on selector functions
- `session_state`: Shared memory across steps

## Voice/Audio Support

### What Exists Today

- **Multimodal I/O**: Handles text, images, audio, and video
- **Audio streaming**: Support for OpenAI `gpt-4o-audio-preview` with PCM16
- **Cartesia TTS integration**: Built-in `CartesiaTools` for text-to-speech
- **Audio output generation**: Agents can produce audio responses

### Community Voice Implementations

- **Vocal-Agent**: Open-source real-time cascading speech-to-speech chatbot combining Whisper (STT) + Silero VAD + Agno (LLM) + Kokoro ONNX (TTS)
- **Agno + Mem0 + Cartesia**: Voice-enabled conversational AI with long-term memory

### What's Missing

- **No native real-time voice pipeline**: Open GitHub issues (#6017, #3108) requesting this
- **No end-to-end voice pipeline**: Voice requires assembling STT + Agent + TTS manually
- **No native speech-to-speech support**: No GPT-4o Realtime API integration

## Local Model Support (Server-Side)

Agno supports local models, but only on a server/desktop, not on mobile:

- **Ollama**: First-class integration for local model serving
- **llama.cpp**: Direct support via the `Llama` model class for GGUF models
- **Together AI, Groq**: Various inference providers

"Local" in Agno means local to a Python runtime on a computer, not local to a mobile device.

## Ecosystem

- **AgentOS**: Production FastAPI runtime for agents
- **Agent UI**: Next.js/Tailwind chat interface (github.com/agno-agi/agent-ui)
- **Agent API**: Minimal FastAPI + Postgres setup (github.com/agno-agi/agent-api)
- **Agno Playground**: Web-based testing environment

## Key Dependencies

- Python 3.12+
- Pydantic (data validation)
- FastAPI (HTTP serving)
- httpx/aiohttp (async HTTP)
- PostgreSQL (recommended storage)
- Optional: `openai`, `anthropic`, `google-generativeai`, etc.

## Recent Features (v2.5.x)

- Async database operations (MongoDB, SQLite, PostgreSQL)
- Provider-specific JSON schemas
- Workflows 2.0 with Condition, Parallel, Loop, Router
- MCP bidirectional support (client and server)
- Runtime approval enforcement
- ExcelReader with sheet filtering
- Website content deduplication
