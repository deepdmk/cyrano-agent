# Database Schemas -- Farmer Conversational AI PoC

---

## Overview

All data is stored locally in the `data/` directory. No Docker or database server required (DD-09).

The system uses five persistent data stores and one ephemeral vector store:

1. **Sessions Table** -- conversation history (managed by Agno SqliteDb, `data/agno_sessions.db`)
2. **Main DB** -- permanent store of all extracted facts (SQLite, `data/cyrano.db`)
3. **Agricultural Data DB** -- Form Database 1, prototype stand-in (SQLite, `data/cyrano.db`)
4. **Scheduling DB** -- Form Database 2, prototype stand-in (SQLite, `data/cyrano.db`)
5. **Planning DB** -- Form Database 3, prototype stand-in (SQLite, `data/cyrano.db`)
6. **Questions Vector DB** -- ephemeral, cleared between sessions (LanceDB, `data/questions_vectordb/`)

---

## Sessions Table

Managed by Agno's built-in session persistence (`agno_sessions`). No custom schema needed. Stores full conversation history turn-by-turn, keyed by session_id.

---

## Main DB

The system's permanent knowledge store. Every structured fact extracted from conversations lives here. Append-only. The Extract Agent writes to it; the Data Agent reads from it.

### Table: `extracted_facts`

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT (UUID) | Unique identifier |
| session_id | VARCHAR | Which conversation session this was extracted from |
| timestamp | TIMESTAMP | When the extraction occurred |
| raw_text | TEXT | The farmer's actual words that this fact was derived from |
| extracted_fact | JSON (TEXT) | Structured representation of the information (flexible key-value) |
| domain | TEXT (JSON list) | Which Form Database(s) this relates to: 'agricultural', 'scheduling', 'planning' (can be multiple, stored as JSON array string) |
| confidence | VARCHAR | How clearly the farmer stated this: 'high', 'medium', 'low' |
| verification_status | VARCHAR | 'unverified', 'confirmed', 'contradicted' |
| routed | BOOLEAN | Whether the Data Agent has processed this record (default: false) |

**Notes:**
- `extracted_fact` is JSON (stored as TEXT in SQLite) to allow flexible structure. The Extract Agent writes whatever fields are relevant (crop_type, date, quantity, etc.) without being locked to a rigid schema.
- `domain` is stored as a JSON-serialized list (e.g., `'["agricultural", "planning"]'`) because a single fact can be relevant to multiple Form Databases. Tool functions handle serialization/deserialization.
- `routed` allows the Data Agent to pick up only new/unprocessed records.

---

## Agricultural Data DB (Form Database 1)

Prototype stand-in for an agro-tracking product. Five tables covering fields, crops, inputs, yields, and weather.

### Table: `fields`

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT (UUID) | Unique identifier |
| name | VARCHAR | Farmer's name for this plot (e.g., "north field", "the plot by the river") |
| size_hectares | DECIMAL | Area in hectares |
| location_description | TEXT | How the farmer describes where it is |
| soil_type | VARCHAR | Soil type if known |
| irrigation_method | VARCHAR | Rainfed, drip, canal, well, etc. |
| notes | TEXT | Anything else mentioned about this field |
| created_at | TIMESTAMP | When this record was first created |
| updated_at | TIMESTAMP | Last update |

### Table: `crops`

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT (UUID) | Unique identifier |
| field_id | TEXT (UUID) | FK to fields |
| crop_type | VARCHAR | e.g., maize, rice, beans, cassava |
| variety | VARCHAR | Specific variety if mentioned |
| planting_date | DATE | When planted |
| expected_harvest_date | DATE | When the farmer expects to harvest |
| actual_harvest_date | DATE | When actually harvested |
| seed_source | VARCHAR | Where seeds came from |
| seed_quantity | VARCHAR | Amount of seed used (with units) |
| status | VARCHAR | 'planted', 'growing', 'harvested', 'failed' |
| notes | TEXT | |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

### Table: `inputs`

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT (UUID) | Unique identifier |
| field_id | TEXT (UUID) | FK to fields |
| crop_id | TEXT (UUID) | FK to crops (optional -- input may be field-level) |
| input_type | VARCHAR | 'fertilizer', 'pesticide', 'herbicide', 'seed_treatment', 'other' |
| product_name | VARCHAR | Brand or generic name if mentioned |
| quantity | DECIMAL | Amount applied |
| unit | VARCHAR | kg, liters, bags, etc. |
| date_applied | DATE | When applied |
| cost | DECIMAL | Cost if mentioned |
| currency | VARCHAR | Local currency |
| notes | TEXT | |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

### Table: `yields`

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT (UUID) | Unique identifier |
| crop_id | TEXT (UUID) | FK to crops |
| field_id | TEXT (UUID) | FK to fields |
| harvest_date | DATE | When harvested |
| quantity | DECIMAL | Amount harvested |
| unit | VARCHAR | kg, tons, bags, bushels, etc. |
| quality_notes | TEXT | Farmer's assessment of quality |
| sale_price | DECIMAL | Price per unit if sold |
| currency | VARCHAR | |
| buyer | VARCHAR | Who bought it |
| notes | TEXT | |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

### Table: `weather_observations`

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT (UUID) | Unique identifier |
| date | DATE | Date of observation |
| observation_type | VARCHAR | 'rain', 'drought', 'frost', 'flood', 'hail', 'heat', 'wind', 'other' |
| severity | VARCHAR | 'mild', 'moderate', 'severe' |
| description | TEXT | Farmer's own description |
| impact | TEXT | How it affected crops or activities |
| field_id | TEXT (UUID) | FK to fields (optional -- may be general) |
| notes | TEXT | |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

---

## Scheduling DB (Form Database 2)

Prototype stand-in for a calendar/logistics product. One table.

### Table: `events`

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT (UUID) | Unique identifier |
| event_type | VARCHAR | 'meeting', 'delivery', 'market', 'equipment', 'labor', 'veterinary', 'training', 'other' |
| description | TEXT | What this event is about |
| date | DATE | When it happens |
| time | TIME | Time if specified |
| location | VARCHAR | Where it happens |
| people_involved | TEXT | Names or roles of people involved |
| is_recurring | BOOLEAN | Whether this repeats |
| recurrence_frequency | VARCHAR | 'daily', 'weekly', 'monthly', 'seasonal', etc. |
| status | VARCHAR | 'planned', 'completed', 'cancelled' |
| notes | TEXT | |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

---

## Planning DB (Form Database 3)

Prototype stand-in for a planning/projection product. One table.

### Table: `plans`

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT (UUID) | Unique identifier |
| category | VARCHAR | 'planting', 'expansion', 'investment', 'rotation', 'technique', 'infrastructure', 'other' |
| description | TEXT | What the farmer plans to do |
| target_season | VARCHAR | e.g., 'next rainy season', 'dry season 2026', 'March planting' |
| target_year | INTEGER | Year if specified |
| field_id | TEXT (UUID) | FK to agricultural fields table (optional) |
| resources_needed | TEXT | What they need to execute this plan |
| estimated_cost | DECIMAL | Budget if mentioned |
| currency | VARCHAR | |
| status | VARCHAR | 'intended', 'in_progress', 'completed', 'abandoned' |
| notes | TEXT | |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

---

## Questions Vector DB

Ephemeral LanceDB table. Cleared at the start of each new session. Stored in `data/questions_vectordb/`.

### LanceDB Table: `session_questions`

| Column | Type | Description |
|--------|------|-------------|
| id | STRING | UUID as string |
| session_id | STRING | Current session (for filtering and cleanup) |
| question_text | STRING | Natural-language question for the Talk Agent to weave into conversation |
| source_database | STRING | Which Form Database this gap was identified in |
| source_table | STRING | Which table the gap is in |
| source_field | STRING | Which field is missing or unclear |
| source_record_id | STRING | Which record the gap relates to (optional, empty string if N/A) |
| priority | STRING | 'high', 'medium', 'low' |
| vector | FLOAT32[768] | Embedding vector for similarity search |
| created_at | STRING | ISO timestamp |

**Notes:**
- Uses LanceDB's built-in vector similarity search (no pgvector extension needed).
- The Talk Agent queries this table via `.search(embedding).where(session_filter).limit(n)` to find questions that fit naturally into the current conversation.
- Embedding dimension (768) assumes BAAI/bge-base-v1.5 (DD-08). Must be locked early -- changing embedders later requires re-embedding everything.
- The entire table is dropped and recreated at the start of each new session (simplest clearing approach for LanceDB).
- The Data Agent regenerates questions fresh each session based on current database state.
