# Cyrano: Conversational Data Capture for Smallholder Farmers

A farmer sits on their porch after a long day and talks to Cyrano the way they would talk to a neighbor who stopped by. They mention the corn is looking good this year, that the rain came late but came hard, that they are thinking about trying garlic on that south plot next spring. Cyrano listens, asks about the soil down there, laughs at the right moments, remembers that last time they talked the frost had hit the berries. It feels like catching up. It feels like a conversation worth having. What the farmer does not see is that behind every exchange, their crop records are being updated, their planting calendar is filling in, and the system is quietly learning what questions to ask next time the conversation drifts toward the right topic.

Most digital agriculture tools ask farmers to adapt to technology: fill out forms, answer structured questions, log data into systems designed for desk workers. That is the wrong direction. People give better information in natural conversation than they do on forms. They share more detail, more context, more of the connections between things. A farmer describing their season in their own words, at their own pace, in response to someone who is actually listening, produces richer, more accurate, more complete information than the same farmer staring at blank fields on a screen. The problem has never been the quality of human communication. It has been our inability to receive it.

Cyrano solves this with four specialized Claude agents built on the Agno framework. The front-of-house agent, Cyrano, focuses entirely on being a good conversation partner. It listens, follows up naturally, matches the farmer's energy, and never advises, praises, or interrogates. Because it carries no data collection agenda, the farmer talks freely and openly, and the quality of information is higher for it. Behind the conversation, an Extract Agent uses Claude to pull structured facts from the dialogue. A Data Agent routes those facts into downstream product databases and identifies gaps in the data, generating natural-language questions stored with vector embeddings. When Cyrano's conversation drifts near a topic where information is missing, the embedding distance closes, the question surfaces, and Cyrano weaves it in naturally. The farmer answers without knowing they just filled in a database field. A Mood Agent monitors engagement, detects fatigue or disengagement, and tells Cyrano when to ease off or wrap up warmly, so the farmer is never pushed past their natural limit. The form databases behind the Data Agent are designed as swappable integration points. Any external product -- an agriculture management system, a market platform, a logistics scheduler, a microfinance application -- can sit behind it as a target. Define the schema, provide the tools, and the conversational layer begins populating it.

This pattern is not limited to agriculture. Anywhere people communicate naturally but would benefit from structured digital records, this architecture applies: a patient describing symptoms, a non-literate artisan negotiating with a buyer, a social worker conducting a home visit, a refugee explaining their situation. In every case, open engaged conversation produces higher quality information than structured intake -- more detail, more honesty, more of the context that makes data meaningful. This matters most for populations that current digital tools exclude by design: people who are non-literate, people without smartphones, people whose social context is oral and relational. For these populations, the answer was never a simpler interface. It is no interface at all. Just conversation, with Claude providing the intelligence to extract structured value from it.

---

## Architecture

```
                    ┌───────────────────────────┐
                    │          FARMER           │
                    │   (natural conversation)  │
                    └─────────┬─────┬───────────┘
                              │     ▲
                     speaks   │     │  responds
                              ▼     │
┌─────────────────────────────────────────────────────────────────┐
│                        ORCHESTRATOR                             │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    CYRANO (Claude)                        │  │
│  │           Front-of-House Conversation Agent               │  │
│  │                                                           │  │
│  │  - Listens, follows up, matches energy                    │  │
│  │  - Never advises, praises, or interrogates                │  │
│  │  - Weaves in questions when embedding distance is close   │  │
│  │  - Adjusts behavior based on Mood Agent nudges            │  │
│  └──────────┬────────────────────────────────┬───────────────┘  │
│             │                                │                  │
│             │ reads questions                │ writes session   │
│             │ (similarity search)            │                  │
│             ▼                                ▼                  │
│  ┌────────────────────┐           ┌────────────────────┐       │
│  │  Questions Vector  │           │  Sessions Table    │       │
│  │  DB (LanceDB)      │           │  (Agno SqliteDb)   │       │
│  │                    │           │                    │       │
│  │  768-dim vectors   │           │  Full conversation │       │
│  │  Cleared/session   │           │  history           │       │
│  └─────────▲──────────┘           └─────────┬──────────┘       │
│            │                                │                  │
│            │ writes questions               │ reads session    │
│            │ with embeddings                │                  │
│            │                                ▼                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │          BACKGROUND PIPELINE (after each turn)          │   │
│  │                                                         │   │
│  │  ┌────────────────┐  ┌────────────────┐  ┌───────────┐  │   │
│  │  │ EXTRACT AGENT  │  │  DATA AGENT    │  │ MOOD      │  │   │
│  │  │ (Claude)       │  │  (Claude)      │  │ AGENT     │  │   │
│  │  │                ├─▶│                │  │ (Claude)  │  │   │
│  │  │ Reads session  │  │ Routes facts   │  │           │  │   │
│  │  │ Extracts facts │  │ to form DBs    │  │ Detects   │  │   │
│  │  │ from natural   │  │ Identifies     │  │ fatigue,  │  │   │
│  │  │ speech         │  │ gaps           │  │ disengage │  │   │
│  │  │                │  │ Generates Qs   │  │           │  │   │
│  │  │                │  │ with vectors   │  │ Nudges    │  │   │
│  │  │                │  │                │  │ Cyrano    │  │   │
│  │  └───────┬────────┘  └───┬────────┬───┘  └───────────┘  │   │
│  │          │               │        │                     │   │
│  │          │ writes        │ routes │ writes              │   │
│  │          ▼               ▼ facts  ▼ questions           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                │
└────────────────────────────────────────────────────────────────┘
              │                  │
              ▼                  ▼
  ┌─────────────────┐  ┌─────────────────────────────────────────┐
  │   MAIN DB       │  │      FORM DATABASES (swappable)         │
  │   (SQLite)      │  │                                         │
  │                 │  │  ┌────────────┐ ┌─────────┐ ┌────────┐  │
  │ Permanent store │  │  │Agricultural│ │Schedules│ │Planning│  │
  │ of all facts    │  │  │            │ │         │ │        │  │
  │ extracted from  │  │  │ fields     │ │ events  │ │ plans  │  │
  │ conversation    │  │  │ crops      │ │         │ │        │  │
  │                 │  │  │ inputs     │ │         │ │        │  │
  │ Written by      │  │  │ yields     │ │         │ │        │  │
  │ Extract Agent   │  │  │ weather    │ │         │ │        │  │
  │                 │  │  └────────────┘ └─────────┘ └────────┘  │
  │ Read by         │  │                                         │
  │ Data Agent      │  │  These are integration points.          │
  │                 │  │  Swap in any external product:          │
  └─────────────────┘  │  ag management, market software,        │
                       │  logistics, microfinance, etc.          │
                       └─────────────────────────────────────────┘
```
