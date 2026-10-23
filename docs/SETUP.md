# SETUP

Exact steps to run the platform. Windows lab PC assumed; the commands are the
same on Linux with `./.venv/bin/python` instead of `.\.venv\Scripts\python.exe`.

---

## 0. Before you start

**Stop the legacy programs.** They hold their own Snap7 connections and will
compete with this one for the PLC:

- `Final/app.py`
- `Final/json_write_for_web_tag.py` ← the important one; it polls continuously
- `Final/camera_yolo.py`
- `PLC_Dashboard/app.py`, `app_fixed.py`, `app_platform_control (1).py`

Nothing in those folders has been modified. To roll back, stop this platform and
start them again.

---

## 1. Backend

```bash
cd "E:\PS2 1st sem\WILP SMCC\Final\scada_platform"
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

The entire dependency list is two packages:

```
flask>=3.0
python-snap7>=2.0
```

No pandas, no openpyxl, no numpy. The tag list is parsed with a stdlib
`.xlsx` reader (`backend/util/xlsx.py`), so this installs on an offline machine.

### Configure

Edit `config/config.json`. The only value that must be right is the PLC address:

```json
"plc": {
  "plc_ip": "172.21.30.157",
  "rack": 0,
  "slot": 1,
  "poll_interval": 0.25
}
```

`tag_list_path` defaults to the supplied workbook at
`../../PLC_Dashboard/PLC_Dashboard/Tag_list (1).xlsx`. Point it wherever yours
lives — it is read, never written.

### Run

```bash
.\.venv\Scripts\python.exe run.py
```

```
  Unified SCADA / Digital Twin Platform
  ----------------------------------------------
  PLC            : 172.21.30.157  rack 0 slot 1
  Poll interval  : 250 ms
  Tags           : 158 (121 documented, 37 undocumented/raw)
  DB read plan   : [(59, 280)]
  HMI            : http://127.0.0.1:5000
  API health     : http://127.0.0.1:5000/api/health
  ----------------------------------------------
```

Useful flags:

| Flag | Effect |
|------|--------|
| `--simulate` | Run with no PLC. Writes round-trip through an in-memory image, so the whole UI including write confirmation works. |
| `--sim-fault NAME` | With `--simulate`, inject a scripted fault. Repeatable. `emergency`, `air_pressure`, `conveyor2_stall`, `valve8_chatter`, `plate_stuck_top`. |
| `--port 8080` | Different port. The legacy apps also used 5000. |
| `--plc-ip 192.168.0.251` | Override the configured address. |
| `--log-level DEBUG` | Verbose, including every write. |

> **Never add `--reload` or set `debug=True`.** The Werkzeug reloader forks a
> second process, and a second process means a second Snap7 client competing for
> the PLC. That is precisely what the legacy `Final/app.py` did.

---

## 2. Frontend

The repository ships a built frontend in `frontend/dist`, so the backend serves
the HMI immediately with no Node step. Rebuild only if you change the UI.

```bash
cd frontend
npm install
npm run build
```

Then reload the browser — `run.py` serves `frontend/dist` directly.

### Developing the UI

```bash
# terminal 1
.\.venv\Scripts\python.exe run.py --simulate

# terminal 2
cd frontend
npm run dev          # http://localhost:5173, proxies /api to :5000
```

Vite's proxy is configured to pass the SSE stream through unbuffered; without
that the realtime channel silently stalls in dev only.

```bash
npm run typecheck    # tsc, no emit
```

---

## 3. Camera service

Runs as its own process. Nothing about it can stall the PLC poll loop.

```bash
.\.venv\Scripts\python.exe tools\camera_bridge.py
```

| Flag | Effect |
|------|--------|
| `--simulate` | Synthetic detections. No camera or model needed — useful for demos and for exercising the magazine-mismatch logic. |
| `--show` | Preview window. Off by default: `cv2.imshow` needs a desktop session, which a service account may not have. |
| `--source 1` | Different camera index. |
| `--confidence 0.25` | Detection threshold. The legacy script used 0.05 — see `DEBUGGING_REPORT.md` E-01. |
| `--model PATH` | Weights. Defaults to `../Final/runs/detect/train3/weights/best.pt`. |

Real detection needs the detector dependencies, which are **not** in
`requirements.txt` because the control system must not depend on them:

```bash
.\.venv\Scripts\python.exe -m pip install ultralytics opencv-python
```

The bridge publishes `data/camera_detections.json` and `data/camera_counts.json`
atomically, each with an `epoch` heartbeat. The backend marks the feed STALE past
`camera.stale_after` (default 5 s) and **withholds counts** rather than showing
an old number as current.

---

## 4. Digital twin integration

The twin is exported from MATLAB once, then replayed by the backend against the
live cycle clock. There is no live MATLAB link — see `DIGITAL_TWIN.md` for why.

```matlab
>> cd Factory_Simulation
>> addpath('E:\PS2 1st sem\WILP SMCC\Final\scada_platform\tools')
>> export_twin_reference
```

Or non-interactively:

```bash
matlab -batch "cd('Factory_Simulation'); addpath('../Final/scada_platform/tools'); export_twin_reference"
```

This writes `scada_platform/data/twin_reference.json`. It **only reads** the
model's output — not one file of `Factory_Simulation/` is modified.

Then in the HMI: **Digital Twin → Reload**, or `POST /api/digital-twin/reload`.

### Without MATLAB

```bash
.\.venv\Scripts\python.exe tools\make_sample_twin_reference.py
```

Generates a **synthetic** reference so the twin page and its detectors can be
exercised. The state names are transcribed from `factory_states.m` and are
accurate; **every timing is fabricated**. The payload says so in `meta.source`
and in the first caveat, which the HMI renders in amber at the top of the page.
Do not draw engineering conclusions from it.

---

## 5. Verify

```bash
.\.venv\Scripts\python.exe run.py --simulate --port 5055              # terminal 1

.\.venv\Scripts\python.exe tools\selftest.py --port 5055              # 47
.\.venv\Scripts\python.exe tools\selftest_extended.py --port 5055     # 101
.\.venv\Scripts\python.exe tools\check_twin_layout.py                 # 55
```

**203 checks** in total:

| suite | covers |
|---|---|
| `selftest.py` | connectivity, the zero-quantity rule, protected tags, auto/manual ownership, a full cycle, recovery, SSE, JSON safety |
| `selftest_extended.py` | snapshot backwards-compatibility, source ownership, the MATLAB adapter, SQL persistence, manual capture, ingestion limits, the chatbot capability boundary, history queries |
| `check_twin_layout.py` | 3-D geometry: nothing outside the table, conveyor 2 perpendicular, honesty markers present |

Every check exercises a **backend** rule, because a frontend can be bypassed
with curl. Full manual procedure in `TEST_CHECKLIST.md`.

---

## 5a. Data sources and modes

The PLC takes control automatically at startup. To change it:

```bash
curl -X POST http://127.0.0.1:5000/api/sources/control \
     -H "Content-Type: application/json" -d '{"sourceId":"plc"}'
```

Or use **Sources…** in the mode banner.

A simulation source is telemetry-only and **cannot** take control — that is
what stops simulated values reaching the PLC. See `DATA_SOURCES.md`.

To point the dashboards at simulation telemetry while the PLC keeps control,
use *Display* rather than *Take control*.

### MATLAB live telemetry

Set `sources.matlab.transport` in `config/config.json`:

- `mock` — synthetic, no MATLAB needed (default)
- `file` — MATLAB writes JSON atomically to `data/matlab_live.json`
- `tcp` — MATLAB streams newline-delimited JSON to port 5560

**The `tcp` path and both real-MATLAB paths are untested** — no MATLAB licence
was available. See `DATA_SOURCES.md` §5.

---

## 5b. Data capture

On the **Data** page:

| button | effect |
|---|---|
| Save Snapshot | one row holding the complete current state |
| Start / Stop Recording | opens a sampled, deadbanded recording session |
| Save Cycle | cycle summary + aggregates + a pinned snapshot |

Outside a recording, per-tag values are **not** stored — see
`DATA_PERSISTENCE.md`. The **History** page queries everything back, and
recordings export as CSV.

---

## 5c. Help assistant

The **Help** button, bottom-right. Works offline with the built-in provider.

For an LLM instead, set `chat.provider` to `openai` or `anthropic` and export
the corresponding key:

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
```

The assistant is read-only and holds no command path. See `CHATBOT.md`.

---

## 6. First run against real hardware

Do this in order.

1. **Read-only first.** Start in AUTO mode and do not start a cycle. The platform
   is read-only in that state. Confirm on `/api/health` and the top bar:
   - `PLC CONNECTED`, latency stable, `staleSeconds` small;
   - 121 documented tags loaded, no registry warnings.
2. **Check the tag decode.** Open Tag Explorer and spot-check against the PLC in
   TIA Portal — pressure, a proximity sensor you can trigger by hand, the
   conveyor position feedbacks.
3. **Settle E-18 while you are there.** Filter provenance = *Undocumented* and
   watch `raw.db59.x268_4` against `io_status.digital_outputs.solenoid_valve5`
   during a run. If they track, the legacy mapping error is confirmed.
4. **Then test a write.** Switch to MANUAL, energise one valve you can observe,
   and confirm the command reaches `CONFIRMED` — meaning an independent PLC read
   saw the value.
5. **Then run a cycle.**

---

## 7. Running as a service

Two processes, in this order:

```
1.  run.py                 the control platform     (required)
2.  tools/camera_bridge.py the detector             (optional)
```

The camera bridge is optional by design: the HMI reports the camera OFFLINE and
carries on. The control system does not depend on it.

Nothing else should run. In particular `json_write_for_web_tag.py` must stay
stopped — it opens a competing Snap7 client.

### Ports

| Port | Service |
|------|---------|
| 5000 | Platform HTTP + SSE (configurable) |
| 102 | S7 comms to the PLC (outbound) |
| 5173 | Vite dev server (development only) |

For access from other machines on the lab network, `host` is already `0.0.0.0`.
There is no authentication — the command model is authorisation-*ready* (every
command carries an operator field and an access class) but no identity provider
is wired in. **Do not expose this beyond a trusted lab network.**

---

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Frontend build not found` | `frontend/dist` missing | `cd frontend && npm install && npm run build` |
| Registry warning: tag list not found | `tag_list_path` wrong | Fix the path in `config/config.json`; it is relative to `scada_platform/` |
| `PLC DISCONNECTED`, backoff climbing | Wrong IP, PLC off, or another client holding the connection | Check the IP; confirm no legacy app is running; S7-1200 connection slots are limited |
| Values freeze but the UI stays responsive | Working as designed — the link dropped and values are marked stale | Check the top bar's `staleSeconds` and last error |
| Writes rejected `wrong_mode` | You are in AUTO | Switch to MANUAL (or MAINTENANCE for setpoints) in the top bar |
| Writes rejected `auto_owns` | A cycle is running | Let it finish or reset it. Two writers on one coil is the failure being prevented |
| Command settles `MISMATCH` | The write went out but the PLC does not hold the value | Normally means the PLC program drives that address. This is a finding, not a bug |
| Camera shows STALE | Bridge not running, or crashed | Restart `tools/camera_bridge.py`; check its console |
| Twin shows "No reference" | Not exported yet | Run `export_twin_reference.m`, or the sample generator |
| Port 5000 in use | A legacy app is running | Stop it, or use `--port` |
