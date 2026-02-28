# Cyrano Chat — Client Specification v1.0

> Canonical reference for building platform clients (iOS, Web, Android, Desktop).
> The iOS app at `ios-client/CyranoChat/` is the reference implementation.

---

## 1. Application Overview

**Name:** Cyrano Chat
**Type:** AI chat assistant with voice support
**LLM Backend:** Anthropic Claude API (streaming)
**Voice Pipeline:** STT (speech-to-text) + TTS (text-to-speech) + VAD (voice activity detection)
**Architecture:** Protocol-based services, swappable providers

---

## 2. Data Models

### 2.1 ChatMessage

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | UUID / string | auto-generated | Unique message identifier |
| `role` | enum: `user`, `assistant`, `system` | required | Message author |
| `content` | string | required | Message text |
| `timestamp` | ISO 8601 datetime | current time | When message was created |
| `isStreaming` | boolean | `false` | True while LLM is still appending tokens |

### 2.2 VoiceState

Enum representing the current voice pipeline state:

| Value | Description |
|-------|-------------|
| `idle` | No voice activity |
| `listening` | Microphone active, STT processing audio |
| `processing` | STT finalizing transcript |
| `generating` | LLM streaming response |
| `speaking` | TTS audio playing |

### 2.3 Application Settings

| Key | Type | Default | Storage |
|-----|------|---------|---------|
| `apiKey` | string | none | Secure storage (Keychain / encrypted localStorage) |
| `selectedModel` | string | `"claude-sonnet-4-20250514"` | Preferences (UserDefaults / localStorage) |
| `systemPrompt` | string | `"You are a helpful AI assistant. Keep responses concise and conversational."` | Preferences |

### 2.4 Available Models

| Identifier | Display Name |
|------------|-------------|
| `claude-sonnet-4-20250514` | Claude Sonnet 4 |
| `claude-haiku-4-20250414` | Claude Haiku 4 |
| `claude-opus-4-20250514` | Claude Opus 4 |

---

## 3. API Integration — Anthropic Messages API

### 3.1 Endpoint

```
POST https://api.anthropic.com/v1/messages
```

### 3.2 Request Headers

| Header | Value |
|--------|-------|
| `x-api-key` | `{apiKey}` |
| `anthropic-version` | `2023-06-01` |
| `content-type` | `application/json` |

### 3.3 Request Body

```json
{
  "model": "{selectedModel}",
  "max_tokens": 4096,
  "temperature": 0.7,
  "stream": true,
  "system": "{systemPrompt}",
  "messages": [
    { "role": "user", "content": "..." },
    { "role": "assistant", "content": "..." }
  ]
}
```

**Message construction rules:**
- Extract any `system` role messages from the conversation → place in top-level `"system"` field
- Include the last **20** non-system messages in `"messages"` array
- Only `user` and `assistant` roles go in the messages array
- Optional fields: `top_p` (float), `stop_sequences` (string array)

### 3.4 Response — Server-Sent Events (SSE)

The response is a stream of SSE events. Parse line-by-line:

```
event: <event_type>
data: <json_payload>
```

**Event handling:**

| Event Type | JSON Path | Action |
|------------|-----------|--------|
| `content_block_delta` | `delta.text` | Append text to current assistant message |
| `message_delta` | `delta.stop_reason` | Mark stream complete |
| `message_stop` | — | Mark stream complete, stop reason: `end_turn` |
| `error` | `error.message` | Display error, mark stream complete |

### 3.5 Error Handling

| HTTP Status | Error | User-Facing Behavior |
|-------------|-------|---------------------|
| 401 | Authentication failed | "Invalid API key" — prompt to re-enter |
| 429 | Rate limited | Show retry message, honor `retry-after` header |
| 400 | Bad request | Display error details |
| 404 | Model not found | Display error, suggest model change |
| 529 | API overloaded | "Service temporarily unavailable" |

### 3.6 Timeouts

| Timeout | Value |
|---------|-------|
| Request timeout | 120 seconds |
| Resource timeout | 300 seconds |

---

## 4. State Machines

### 4.1 Text Chat Flow

```
User types text
  → Validate non-empty (trim whitespace)
  → Clear input field
  → Append ChatMessage(role: user, content: text)
  → Append ChatMessage(role: assistant, content: "", isStreaming: true)
  → Set isGenerating = true
  → Build LLM messages (system prompt + last 20 messages)
  → Call streamCompletion(model, maxTokens: 4096, temperature: 0.7)
  → For each token:
      → Append token.content to assistant message
  → On done/error:
      → Set isStreaming = false
      → Set isGenerating = false
```

### 4.2 Voice Session Flow

```
                              ┌──────────────────────────────┐
                              │                              │
idle ──[mic tap]──► listening ──[STT final]──► generating ──► speaking
                     ▲    │                                    │
                     │    │──[2s silence]──► generating ───────┘
                     │                                         │
                     └──────────[response complete]────────────┘
                     │
                     └──────────[barge-in: VAD ≥ 0.7]──────────┘
                              │
idle ◄──[mic tap]─────────────┘
```

**Voice start sequence:**
1. Configure audio engine (sample rate, voice processing, VAD)
2. Start audio capture
3. Subscribe to audio stream for VAD results + audio level
4. Start STT streaming
5. Forward audio buffers to STT service
6. Set voiceState = `listening`

**Voice stop sequence:**
1. Cancel all async tasks (STT, audio forwarding, silence timer)
2. Stop STT streaming
3. Stop audio playback
4. Flush TTS queue
5. Stop audio engine
6. Set voiceState = `idle`

### 4.3 STT → LLM → TTS Pipeline

1. STT emits partial transcripts → display as `partialTranscript` in UI
2. On final transcript (or 2-second silence timeout on partial):
   - Clear partialTranscript
   - Set voiceState = `generating`
   - Send transcript as user message to LLM
3. LLM tokens accumulated into **sentences** (boundary = `.` `!` `?` with buffer > 10 chars)
4. Each complete sentence sent to TTS immediately
5. TTS audio chunks played through audio engine
6. When LLM stream completes and remaining text spoken:
   - Set voiceState = `listening`
   - Restart STT stream

### 4.4 Barge-In Detection

During `speaking` state:
- VAD continues monitoring microphone input
- If `VADResult.isSpeech == true` AND `confidence >= 0.7`:
  - Stop audio playback immediately
  - Flush TTS queue
  - Set voiceState = `listening`

### 4.5 Silence Timer

When STT emits a non-final, non-empty partial transcript:
- Start/reset a **2-second** timer
- If timer fires and partialTranscript is still non-empty:
  - Treat current partialTranscript as final
  - Proceed to LLM generation

---

## 5. Screen Specifications

### 5.1 Chat Screen (Main)

**Navigation Bar:**
- Title: `"Cyrano"`, inline display mode
- Left button: new conversation (SF Symbol: `plus.message`), disabled when messages empty
- Right button: settings (SF Symbol: `gear`)

**Message List:**
- Scrollable, auto-scrolls to bottom on new message or content update
- Scroll animation: ease-out, 200ms on new message, 100ms on content update
- Empty state: centered icon + text (see 5.1.1)
- Messages rendered in vertical stack, 12px spacing between bubbles
- Horizontal padding on list: platform default

**Empty State (centered vertically):**
- Icon: `bubble.left.and.bubble.right`, 48pt, secondary color
- Title: "Start a conversation", title3 font, secondary color
- Subtitle: "Type a message or tap the microphone to talk", subheadline, tertiary color

**Voice Indicator (visible when voiceState != idle):**
- Positioned between message list and input bar
- Background: system bar color
- See section 5.4 for details

**Input Bar:**
- See section 5.3

**Error Alert:**
- Standard modal alert
- Title: "Error"
- Body: error message text
- Single "OK" button to dismiss

**First Launch:**
- If no API key is stored, show Settings as a modal sheet immediately

### 5.2 Message Bubbles

**User Messages:**
- Alignment: right
- Background: blue (system blue)
- Text color: white
- Left spacer: minimum 48px (max width ~75% of screen)

**Assistant Messages:**
- Alignment: left
- Background: secondary fill (light gray in light mode, dark gray in dark mode)
- Text color: primary (black/white depending on mode)
- Right spacer: minimum 48px

**Shared Bubble Properties:**
- Corner radius: 18px
- Horizontal padding: 14px
- Vertical padding: 10px
- Text is selectable
- Font: body (system default)

**Timestamp:**
- Displayed below each bubble
- Font: caption2
- Color: tertiary
- Format: time only (e.g., "2:34 PM")
- Alignment: matches bubble alignment
- Horizontal padding: 4px
- Spacing from bubble: 4px

**Streaming Indicator (empty assistant message with isStreaming=true):**
- Three dots animation
- Dot size: 6x6px circles
- Dot color: secondary, 60% opacity
- Animation: ease-in-out, 600ms cycle, repeats forever
- Stagger: 200ms delay between each dot (0ms, 200ms, 400ms)
- Padding matches bubble padding (14px horizontal, 10px vertical)

### 5.3 Input Bar

**Layout:** horizontal stack, bottom of screen

| Element | Details |
|---------|---------|
| **Mic button** | 36x36px, icon 20pt. Blue when idle, red when voice active. SF Symbols: `mic.fill` (idle), `waveform` (listening), `ellipsis.circle.fill` (processing/generating), `speaker.wave.2.fill` (speaking). Disabled during text generation if voice idle. |
| **Text field** | Multi-line (1-6 lines), placeholder "Message", rounded rect background (radius 20px, tertiary fill), 12px horizontal padding, 8px vertical padding. Disabled during voice mode. Submit via keyboard sends message. |
| **Send button** | `arrow.up.circle.fill`, 30pt. Blue when enabled, gray at 40% opacity when disabled. |

**Send button enabled when:**
- Text is non-empty (after whitespace trimming)
- Not currently generating (isGenerating == false)
- Voice is idle (voiceState == idle)

**Spacing:** 10px between elements
**Container:** 12px horizontal padding, 8px vertical padding, system bar background
**Top border:** 1px divider line

### 5.4 Voice Indicator

**Layout:** vertical stack, 8px spacing

**Status Row (always visible):**
- Pulsing dot: 8px diameter, color varies by state (see below)
  - Animation: scale 1.0 → 1.3, ease-in-out, 800ms, repeats with autoreversal
- Status text: caption font, medium weight, secondary color

| VoiceState | Dot Color | Status Text |
|------------|-----------|-------------|
| `idle` | gray | (empty) |
| `listening` | green | "Listening..." |
| `processing` | orange | "Processing..." |
| `generating` | orange | "Thinking..." |
| `speaking` | blue | "Speaking..." |

**Partial Transcript (visible when non-empty):**
- Font: subheadline
- Color: primary
- Max lines: 2
- Alignment: leading
- Horizontal padding

**Audio Level Bars (visible only during `listening`):**
- 5 vertical bars
- Bar width: 4px, corner radius: 2px, fill: blue
- Bar spacing: 3px
- Container height: 24px
- Bar height formula: `base + (maxHeight - base) * normalized * variation`
  - base = 4px, maxHeight = 24px
  - normalized = clamp(audioLevel, 0, 1)
  - variation = sin(index * 1.2 + normalized * 5) * 0.3 + 0.7

**Container:** system bar background, 8px vertical padding, horizontal padding

### 5.5 Settings Screen

**Presented as:** modal sheet with navigation bar
**Navigation:** title "Settings" (inline), "Done" button (trailing)

**Sections:**

#### Section 1: "Anthropic API Key"
- **Input field:** toggleable secure/plain text
  - Placeholder: `"sk-ant-..."`
  - Monospaced font when visible
  - No autocorrection, no autocapitalization
- **Visibility toggle:** eye/eye.slash icon, secondary color, plain button style
- **Save button:** label "Save API Key" + green checkmark icon when saved
  - Disabled if input empty/whitespace
  - On save: stores to secure storage, masks input with 20 asterisks, hides text
- **Footer:** "Your API key is stored securely in the iOS Keychain."

#### Section 2: "Model"
- **Picker:** bound to selectedModel
- **Options:** 3 models (see section 2.4)

#### Section 3: "System Prompt"
- **Text editor:** multi-line, minimum height 80px
- **Font:** subheadline
- **No validation** — accepts any input including empty

#### Section 4: "Voice Pipeline"
- **Row 1:** mic.fill icon (blue) + "Voice Input" + "Apple Speech" (secondary, trailing)
- **Row 2:** speaker.wave.2.fill icon (blue) + "Voice Output" + "Apple TTS" (secondary, trailing)
- **Footer:** "STT: Apple Speech (on-device). TTS: Apple TTS (v1). GLM-ASR and Pocket TTS coming soon."
- **Read-only** — informational only

#### Section 5: "About"
- **Version:** "1.0.0" (secondary, trailing)
- **Remove API Key:** destructive button, only visible if key exists
  - Clears secure storage, resets input state

**First Launch Behavior:**
- On appear: check if API key exists
- If key exists: mask input with 20 asterisks
- Save validation: reject all-asterisks input (masked key)

---

## 6. Colors & Theming

The app uses **only system semantic colors** — no custom colors. This ensures automatic light/dark mode support and accessibility compliance.

| Usage | Color Token |
|-------|------------|
| User message background | blue |
| User message text | white |
| Assistant message background | fill.secondary |
| Assistant message text | primary |
| Primary actions (send, mic idle) | blue |
| Active voice indicator | red |
| Listening dot | green |
| Processing/generating dot | orange |
| Speaking dot | blue |
| Saved checkmark | green |
| Secondary text | secondary |
| Tertiary text | tertiary |
| Input field background | fill.tertiary |
| Bar backgrounds | bar (system) |
| Disabled send button | gray at 40% opacity |
| Destructive actions | system red (destructive role) |
| Streaming dots | secondary at 60% opacity |

---

## 7. Typography

| Element | Spec |
|---------|------|
| Nav title | System, inline |
| Message body | Body (system default) |
| Timestamp | Caption 2 |
| Empty state title | Title 3 |
| Empty state subtitle | Subheadline |
| Voice status text | Caption, medium weight |
| Partial transcript | Subheadline |
| API key input (visible) | Body, monospaced |
| System prompt editor | Subheadline |
| Settings labels | Form defaults |

---

## 8. Spacing & Layout Constants

| Constant | Value | Usage |
|----------|-------|-------|
| Message spacing | 12px | Between bubbles in list |
| Bubble padding H | 14px | Inside bubble horizontal |
| Bubble padding V | 10px | Inside bubble vertical |
| Bubble corner radius | 18px | Message roundness |
| Min opposite spacer | 48px | Max bubble width constraint |
| Input field corner radius | 20px | Text field background |
| Input field padding H | 12px | Inside text field |
| Input field padding V | 8px | Inside text field |
| Input bar spacing | 10px | Between mic, field, send |
| Input bar padding H | 12px | Container horizontal |
| Input bar padding V | 8px | Container vertical |
| Mic button frame | 36x36px | Touch target |
| Mic icon size | 20pt | SF Symbol |
| Send icon size | 30pt | SF Symbol |
| Voice indicator spacing | 8px | Between rows |
| Status dot diameter | 8px | Pulsing circle |
| Audio bar width | 4px | Each bar |
| Audio bar spacing | 3px | Between bars |
| Audio bar max height | 24px | Tallest bar |
| Streaming dot size | 6x6px | Each circle |
| Streaming dot spacing | 4px | Between dots |
| Timestamp padding H | 4px | Below bubble |
| Timestamp spacing | 4px | Gap from bubble |
| System prompt min height | 80px | Text editor |
| Text field line limit | 1–6 | Lines before scroll |
| Empty state icon | 48pt | SF Symbol |
| Scroll animation (count) | 200ms ease-out | New message |
| Scroll animation (content) | 100ms ease-out | Streaming |

---

## 9. Accessibility

| Control | Accessibility Label |
|---------|-------------------|
| Mic button (idle) | "Start voice" |
| Mic button (active) | "Stop voice" |
| Send button | "Send message" |
| Message text | Selectable by user |

---

## 10. Secure Storage

### API Key

| Property | Value |
|----------|-------|
| Storage mechanism | iOS Keychain / Web Crypto API / platform equivalent |
| Service/namespace | `"com.cyrano.chat"` |
| Key name | `"anthropic-api-key"` |
| Accessibility | When device unlocked only |
| Sharing | Not shared across apps/devices |

### Operations

- **Save:** Delete existing → add new with encryption
- **Load:** Query by service + key name → decode UTF-8
- **Delete:** Remove by service + key name (silent on not-found)

---

## 11. Voice Pipeline Architecture

### Provider Protocols

All voice services conform to protocol interfaces. Implementations are swappable.

**STTService:**
- `startStreaming(audioFormat)` → async stream of STTResult
- `sendAudio(buffer)` → feed audio data
- `stopStreaming()` → finalize and close
- `cancelStreaming()` → abort without finalizing

**TTSService:**
- `synthesize(text)` → async stream of audio chunks
- `configure(voiceConfig)` → set voice parameters
- `flush()` → stop and clear queue

**VADService:**
- `processBuffer(audioBuffer)` → VADResult (isSpeech, confidence)
- `prepare()` → load models
- `reset()` → clear state
- `shutdown()` → release resources

### v1 Implementations

| Service | Provider | Notes |
|---------|----------|-------|
| STT | Apple Speech (on-device) | Free, no network. GLM-ASR planned. |
| TTS | Apple AVSpeechSynthesizer | Free, on-device. Pocket TTS planned. |
| VAD | Silero (CoreML) with RMS fallback | Falls back to energy-based detection if model unavailable |
| LLM | Claude API (cloud) | On-device LLM (Ministral 3B) planned |

### Audio Engine

- Sample rate: 48kHz default (configurable: 16/24/48 kHz)
- Channels: 1 (mono)
- Format: Float32 PCM
- Voice processing: hardware AEC (echo cancellation), AGC, noise suppression
- Barge-in threshold: VAD confidence >= 0.7
- Buffer size: 1024 frames
- Audio level monitoring: 100ms update interval

### Sentence Boundary Detection

LLM tokens are accumulated and sent to TTS at sentence boundaries:
- Boundary characters: `.` `!` `?`
- Minimum buffer length before flush: 10 characters
- Remaining buffer flushed when LLM stream completes

---

## 12. Web Client Implementation Notes

### API Key Storage
- Use `localStorage` with encryption via Web Crypto API, or a server-side proxy
- Never expose API key in client-side JavaScript source

### Voice (Web Speech API)
- **STT:** `SpeechRecognition` / `webkitSpeechRecognition`
  - Set `continuous = true`, `interimResults = true`
  - Map `onresult` events to STTResult model
- **TTS:** `SpeechSynthesis` API
  - `speechSynthesis.speak(new SpeechSynthesisUtterance(text))`
  - Map `getVoices()` to voice picker
- **VAD:** Use `AudioContext` + `AnalyserNode` for RMS-based detection
  - Calculate RMS from `getFloatTimeDomainData()`
  - Map to 0–1 confidence using dB normalization (same formula as iOS fallback)

### SSE Streaming
- Use `fetch()` with `response.body.getReader()` and `TextDecoder`
- Parse SSE lines manually (same event/data format)
- Or use `EventSource` if CORS headers allow (Anthropic API does not support EventSource directly — use fetch)

### Responsive Layout
- Mobile-first design matching iOS layout
- Message list fills available height
- Input bar pinned to bottom (use `position: sticky` or flexbox)
- Respect safe areas on mobile browsers

### Keyboard Handling
- Enter key sends message (unless Shift+Enter for newline)
- Focus text field after sending
- Auto-resize textarea up to 6 lines

---

## 13. Cross-Platform Parity Checklist

| Feature | Required | Notes |
|---------|----------|-------|
| Text chat with streaming | Yes | Core feature |
| Message bubbles (user right, assistant left) | Yes | Exact styling per spec |
| Streaming dots animation | Yes | 3 dots, staggered |
| Auto-scroll on new content | Yes | Smooth animation |
| API key secure storage | Yes | Platform-appropriate |
| Model selection | Yes | 3 models |
| System prompt editing | Yes | Free text |
| Voice input (STT) | Yes | Platform speech API |
| Voice output (TTS) | Yes | Platform speech API |
| Voice indicator with state | Yes | Dot + text + bars |
| Barge-in detection | Yes | Interrupt playback on speech |
| Silence timer (2s) | Yes | Auto-finalize partial transcript |
| Sentence-level TTS streaming | Yes | Don't wait for full response |
| Dark mode support | Yes | System semantic colors only |
| Error alerts | Yes | Network, auth, rate limit |
| Settings modal | Yes | All sections per spec |
| New conversation | Yes | Clear all messages |
| Text selection on messages | Yes | Long-press / select |
| Timestamp per message | Yes | Time only, caption2 |
| Empty state | Yes | Icon + text |
| Multi-line input (1-6 lines) | Yes | Auto-grow textarea |
| Keyboard submit | Yes | Enter/Return sends |

---

## Appendix A: SF Symbol → Icon Mapping (Web)

| SF Symbol | Usage | Suggested Web Icon |
|-----------|-------|--------------------|
| `plus.message` | New conversation | Plus + chat bubble SVG |
| `gear` | Settings | Gear/cog SVG |
| `mic.fill` | Voice idle | Microphone SVG |
| `waveform` | Voice listening | Audio waveform SVG |
| `ellipsis.circle.fill` | Voice processing | Loading circle SVG |
| `speaker.wave.2.fill` | Voice speaking | Speaker SVG |
| `arrow.up.circle.fill` | Send message | Up arrow in circle SVG |
| `bubble.left.and.bubble.right` | Empty state | Chat bubbles SVG |
| `eye` / `eye.slash` | Show/hide password | Eye open/closed SVG |
| `checkmark.circle.fill` | Saved confirmation | Checkmark circle SVG |

---

## Appendix B: Animation Specifications

| Animation | Type | Duration | Easing | Repeat |
|-----------|------|----------|--------|--------|
| Scroll to bottom (new msg) | Position | 200ms | ease-out | once |
| Scroll to bottom (content) | Position | 100ms | ease-out | once |
| Streaming dots | Opacity/scale | 600ms | ease-in-out | forever, staggered 200ms |
| Status dot pulse | Scale 1.0→1.3 | 800ms | ease-in-out | forever, autoreverses |

---

*This spec is the source of truth for all Cyrano Chat client implementations.*
