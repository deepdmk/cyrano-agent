# Database Schemas -- Farmer Conversational AI PoC

---

## Overview

The system uses five persistent data stores and one ephemeral vector store:

1. **Sessions Table** -- conversation history (managed by Agno)
2. **Main DB** -- permanent store of all extracted facts
3. **Agricultural Data DB** -- Form Database 1 (prototype stand-in for an agro-tracking product)
4. **Scheduling DB** -- Form Database 2 (prototype stand-in for a calendar/logistics product)
5. **Planning DB** -- Form Database 3 (prototype stand-in for a planning/projection product)
6. **Questions Vector DB** -- ephemeral, cleared between sessions

---

## Sessions Table

Managed by Agno's built-in session persistence (`agno_sessions`). No custom schema needed. Stores full conversation history turn-by-turn, keyed by session_id.

---

## Main DB

The system's permanent knowledge store. Every structured fact extracted from conversations lives here. Append-only. The Extract Agent writes to it; the Data Agent reads from it.

### Table: `extracted_facts`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Unique identifier |
| session_id | VARCHAR | Which conversation session this was extracted from |
| timestamp | TIMESTAMP | When the extraction occurred |
| raw_text | TEXT | The farmer's actual words that this fact was derived from |
| extracted_fact | JSONB | Structured representation of the information (flexible key-value) |
| domain | VARCHAR[] | Which Form Database(s) this relates to: 'agricultural', 'scheduling', 'planning' (can be multiple) |
| confidence | VARCHAR | How clearly the farmer stated this: 'high', 'medium', 'low' |
| verification_status | VARCHAR | 'unverified', 'confirmed', 'contradicted' |
| routed | BOOLEAN | Whether the Data Agent has processed this record (default: false) |

**Notes:**
- `extracted_fact` is JSONB to allow flexible structure. The Extract Agent writes whatever fields are relevant (crop_type, date, quantity, etc.) without being locked to a rigid schema.
- `domain` is an array because a single fact can be relevant to multiple Form Databases (e.g., "I'm planning to plant maize next season in the north field" is both agricultural and planning).
- `routed` allows the Data Agent to pick up only new/unprocessed records.

---

## Agricultural Data DB (Form Database 1)

Prototype stand-in for an agro-tracking product. Five tables covering fields, crops, inputs, yields, and weather.

### Table: `fields`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Unique identifier |
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
| id | UUID | Unique identifier |
| field_id | UUID | FK to fields |
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
| id | UUID | Unique identifier |
| field_id | UUID | FK to fields |
| crop_id | UUID | FK to crops (optional -- input may be field-level) |
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
| id | UUID | Unique identifier |
| crop_id | UUID | FK to crops |
| field_id | UUID | FK to fields |
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
| id | UUID | Unique identifier |
| date | DATE | Date of observation |
| observation_type | VARCHAR | 'rain', 'drought', 'frost', 'flood', 'hail', 'heat', 'wind', 'other' |
| severity | VARCHAR | 'mild', 'moderate', 'severe' |
| description | TEXT | Farmer's own description |
| impact | TEXT | How it affected crops or activities |
| field_id | UUID | FK to fields (optional -- may be general) |
| notes | TEXT | |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

---

## Scheduling DB (Form Database 2)

Prototype stand-in for a calendar/logistics product. One table.

### Table: `events`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Unique identifier |
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
| id | UUID | Unique identifier |
| category | VARCHAR | 'planting', 'expansion', 'investment', 'rotation', 'technique', 'infrastructure', 'other' |
| description | TEXT | What the farmer plans to do |
| target_season | VARCHAR | e.g., 'next rainy season', 'dry season 2026', 'March planting' |
| target_year | INTEGER | Year if specified |
| field_id | UUID | FK to agricultural fields table (optional) |
| resources_needed | TEXT | What they need to execute this plan |
| estimated_cost | DECIMAL | Budget if mentioned |
| currency | VARCHAR | |
| status | VARCHAR | 'intended', 'in_progress', 'completed', 'abandoned' |
| notes | TEXT | |
| created_at | TIMESTAMP | |
| updated_at | TIMESTAMP | |

---

## Questions Vector DB

Ephemeral PgVector table. Cleared at the start of each new session.

### Table: `session_questions`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Unique identifier |
| session_id | VARCHAR | Current session (for cleanup) |
| question_text | TEXT | Natural-language question for the Talk Agent to weave into conversation |
| source_database | VARCHAR | Which Form Database this gap was identified in |
| source_table | VARCHAR | Which table the gap is in |
| source_field | VARCHAR | Which field is missing or unclear |
| source_record_id | UUID | Which record the gap relates to (optional) |
| priority | VARCHAR | 'high', 'medium', 'low' |
| embedding | VECTOR(768) | Vector embedding for similarity search |
| created_at | TIMESTAMP | |

**Notes:**
- The Talk Agent queries this table via vector similarity search against its current conversation context to find questions that fit naturally.
- Embedding dimension (768) assumes a base embedder like BAAI/bge-base-v1.5 or intfloat/e5-base-v2. Must be locked early -- changing embedders later requires re-embedding everything.
- All records for a session_id are deleted at the start of a new session.
- The Data Agent regenerates questions fresh each session based on current database state.
