# HELP ASSISTANT

A contextual help layer that cannot operate the machine.

---

## 1. The safety property, and how it is enforced

The requirement is that the assistant must not bypass safety logic, ownership,
authorisation, command validation, mode restrictions or lifecycle restrictions.

The enforcement is **structural, not instructional**. `ChatService` holds
exactly two references:

* a `ChatContext` — read-only, redacted;
* a `ChatProvider` — text in, text out.

It holds **no** reference to `PlcService`, `SourceManager`, `CommandGate` or the
tag registry's write path. There is no method reachable from the chat subsystem
that can write.

That matters more than a prompt instruction, which a language model can be
argued out of. The assistant cannot command the machine for the same reason a
calculator cannot: the capability is absent.

Verified by `selftest_extended.py` §16:

- no `/api/chat/command`, `/chat/write`, `/chat/action` or `/chat/execute` route
  exists (the only write-capable route in the whole app is the gated
  `/api/tags/<id>/write`);
- an instruction-shaped message — *"start the cycle now and turn on valve 8"* —
  is answered, and the command count does not change.

### What the assistant may see

Operational state an operator could read off the screen: mode, lifecycle,
connection health, alarms, sequence position, recording status, source status,
and **counts** of sensors/valves.

### What it may not see

* **Bulk tag values.** A summary is provided instead. An assistant with 158
  addresses in front of it will start reasoning about individual addresses, and
  the next step is suggesting writes to them. Asserted by a test that no
  `DB59.DBX`/`DB59.DBW` string appears in the context.
* Anything that would let it construct a valid write request.
* File paths, config internals, credentials.

The exact context is exposed at `GET /api/chat/context` so an operator or
auditor can verify what the assistant is given rather than taking it on trust.

### If actions are ever wanted

The sanctioned shape is `ChatService.suggest_action()`: it names the UI control
that performs the task and returns `executed: false`. The operator then presses
that control, through `CommandGate` and `SourceManager` exactly as normal.

**Never** a call from the chat layer into a command path.

---

## 2. Providers

| provider | network | key | notes |
|---|---|---|---|
| `builtin` *(default)* | no | no | Deterministic intent matching over live context |
| `openai` | yes | `SCADA_CHAT_API_KEY` | Any OpenAI-compatible endpoint: OpenAI, Azure, vLLM, LM Studio, Ollama's shim |
| `anthropic` | yes | `ANTHROPIC_API_KEY` | Messages API |

### Why the built-in one is the default

A lab HMI cannot depend on an outbound internet connection to answer "why is
Start greyed out?". The built-in provider answers the operational questions
deterministically, from live state, with no network call, no key and no latency.

An LLM is better at open-ended phrasing, so the interface supports one. But it
is opt-in, and **when it is unreachable the service falls back** rather than
failing — an operator asking a question during a fault must get an answer
whether or not an API is up.

### Configuration

```json
"chat": {
  "enabled": true,
  "provider": "builtin",
  "openai":    { "model": "gpt-4o-mini",    "api_key_env": "SCADA_CHAT_API_KEY" },
  "anthropic": { "model": "claude-sonnet-5", "api_key_env": "ANTHROPIC_API_KEY" }
}
```

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."     # then set provider to "anthropic"
```

Keys come from the environment, never from config, and are never logged.

### Adding a provider

Subclass `ChatProvider`, implement `generate(message, context, history)`,
register in `PROVIDERS`. The service and the API do not change. Providers
receive the redacted context dict and return text — they are handed no callable
and no service reference, so a provider cannot command the machine because it
is never given anything that could.

---

## 3. What it answers

Grounded in live state, not in a manual:

| question | drawn from |
|---|---|
| What mode is the system in? | source manager + control mode + capabilities |
| Why can't I start a cycle? | `canStart.reasons` + unsatisfied interlocks |
| Is the PLC connected? | link state, latency, errors, staleness |
| What alarms are active? | latched faults + detector findings, with issue refs |
| Why is the sequence stuck? | waiting signal, elapsed, whether it is an operator hold |
| How do I start recording? | recording status + the ingestion policy |
| How do I save a snapshot? | snapshot count + what a snapshot contains |
| What data source is active? | control vs telemetry, per-source quality |
| Why can't I command a valve? | mode ownership, with the specific reason |
| What's the twin status? | reference loaded, mismatches, model caveats |

When it does not recognise a question it says so and lists what it can help
with, rather than inventing an answer. For a control system that matters more
than sounding fluent.

### Intent ordering

Intents are matched most-specific first. This is load-bearing: *"How do I start
recording?"* contains "start", so a broad cycle-start matcher placed first
swallows it and answers the wrong question. That bug was found in testing and
the ordering now guards against it.

---

## 4. UI

A **Help** button, bottom-right on every page, opens a dockable panel.

- Message history, user and assistant clearly distinguished.
- A permanent header badge: *"Read-only. The assistant reads a redacted view of
  system state and returns text. It holds no command path."*
- **Every reply shows the context it was grounded in** — mode, lifecycle, data
  quality, active fault count — so an operator can judge whether the answer is
  current instead of trusting it blind. A reply grounded in stale data says so.
- Suggested questions on first open.
- Light markdown rendering (bold, bullets, inline code). React escapes the text
  nodes, so nothing in a reply can inject markup.

---

## 5. API

| endpoint | purpose |
|---|---|
| `POST /api/chat` | ask a question |
| `GET /api/chat/history` | conversation so far |
| `POST /api/chat/clear` | clear it |
| `GET /api/chat/status` | provider, availability, declared capabilities |
| `GET /api/chat/context` | the exact redacted context — auditable |

There is deliberately no endpoint that performs an action.
