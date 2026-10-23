# DATA SOURCES, OPERATING MODES AND MATLAB INTEGRATION

How the platform talks to the PLC, to MATLAB/Simulink, and to anything added
later — and how it guarantees the two can never fight over the machine.

---

## 1. The adapter contract

Everything that produces machine data implements one interface
(`backend/sources/base.py`):

```python
class DataSourceAdapter(ABC):
    source_id: str
    kind: str                 # PLC | SIMULATION | MOCK
    supports_control: bool    # may this source ever command the machine?

    def connect(self) -> bool
    def disconnect(self) -> None
    def start(self) -> bool
    def stop(self) -> None
    def get_status(self) -> SourceStatus
    def read_latest(self) -> Dict[str, Sample]
    def send_command(self, tag_id, value, **kw) -> tuple   # refuses by default
```

The application core consumes **normalised samples** and never asks which
driver produced them. Adding a source is a new file plus a config entry; no
core change.

### Why every sample carries provenance

```python
Sample(value=..., source='plc', timestamp=..., quality='GOOD', sequence=412)
```

A bare number is how stale data gets displayed as live. `quality` is the
load-bearing field:

| quality | meaning |
|---|---|
| `GOOD` | fresh, from a healthy link |
| `STALE` | last known good, past the freshness budget |
| `UNCERTAIN` | link degraded; the value may lag |
| `BAD` | decode failed, or no value has ever arrived |

`sequence` increments per successful poll, so a consumer can detect a **wedged
feed** whose timestamp still looks plausible.

---

## 2. Control vs telemetry — two different questions

These are tracked separately, on purpose:

* **Control source** — who may write to hardware. Exactly one, and it must
  declare `supports_control`.
* **Telemetry source** — whose data feeds the dashboards. Any healthy source.

Keeping them apart is what lets an engineer watch simulation telemetry while
the PLC remains the thing under control, without either becoming ambiguous. A
single "mode" flag is how simulated values end up silently labelled as plant
data.

### The guarantee

`MatlabSourceAdapter.supports_control = False`. Consequently:

1. `SourceManager.set_control_source('matlab')` **refuses**, with a reason.
2. `MatlabSourceAdapter.send_command()` **refuses**, independently.
3. `SourceManager.write()` routes only to the *active* control source.

Three barriers, none of which relies on anyone remembering a convention.
Verified by `tools/selftest_extended.py` §11.

```bash
$ curl -X POST /api/sources/control -d '{"sourceId":"matlab"}'
409  {"code":"control_refused",
      "message":"MATLAB / Simulink is a telemetry-only source and can never
                 take control of the machine. This prevents simulated values
                 from reaching the PLC."}
```

---

## 3. Operating modes

Derived from the sources every poll rather than stored, so the displayed mode
can never disagree with reality:

| mode | when |
|---|---|
| `PLC_CONNECTED` | a healthy control-capable PLC source holds control |
| `PLC_CONNECTING` | the PLC source is coming up |
| `SIMULATION_RUNNING` | telemetry is a running simulation |
| `SIMULATION_STOPPED` | simulation selected but not producing |
| `DISCONNECTED` | no source is producing usable data |
| `ERROR` | the active source reports an error |

This sits **alongside** the existing `AUTO / MANUAL / MAINTENANCE` control mode
and the existing machine lifecycle. It does not replace either — the brief
explicitly warned against a second conflicting lifecycle, and there isn't one.

The UI states it full width at the top of every page, with hazard striping in
simulation mode so it is distinguishable across a room and without colour.

---

## 4. The PLC adapter

Deliberately thin. `PlcService` already owns the single Snap7 client, the poll
thread, the write queue and read-back confirmation; none of that is
reimplemented.

`PlcSourceAdapter.connect()` **does not** call `plc.start()`. The poll thread
must be started exactly once, by the owner — an adapter starting it would
recreate the "four competing Snap7 clients" defect this project exists to
remove.

`disconnect()` is a deliberate no-op: tearing down the shared connection
because one adapter was deselected would break every other consumer, and the
PLC link should stay up for monitoring even when control moves elsewhere.

---

## 5. MATLAB / Simulink

### Why three transports

The existing MATLAB integration is a **batch export**:
`run_factory_simulation` solves a whole 31 s cycle and returns a LOG struct.
That path is unchanged (see `DIGITAL_TWIN.md`). What is new is *live*
telemetry, which the batch model cannot produce.

Rejected:

* **MATLAB Engine API** — needs a licence on the control PC, puts a heavyweight
  process in the control path, and still cannot step a batch solver.
* **MQTT** — a broker to install and administer for one point-to-point link.
* **Simulink Coder / real-time** — forks the execution paths the simulation
  project works hard to keep bit-identical.

Implemented, all behind the same adapter:

| transport | how MATLAB sends | when to use |
|---|---|---|
| `file` *(default)* | `jsonencode` → temp file → `movefile` | offline PC, no networking; mirrors the camera bridge already proven here |
| `tcp` | `tcpclient` writing newline-delimited JSON | live streaming from a running model |
| `mock` | nothing — generated locally | development and CI with no MATLAB |

`file` is the default because it needs no ports, survives either side
restarting, and uses the atomic-rename pattern already working in
`tools/camera_bridge.py`.

### Wire format

Either shape is accepted, because MATLAB users will reasonably produce either:

```json
{"timestamp": 1788160000.0, "values": {"sim.belt1_speed": 0.15, ...}}
{"sim.belt1_speed": 0.15, "sim.receiver_pressure": 5.4}
```

### MATLAB side (file transport)

```matlab
payload = struct('timestamp', posixtime(datetime('now','TimeZone','UTC')), ...
                 'values', struct('sim_belt1_speed', v1, ...));
tmp = [target '.tmp'];
fid = fopen(tmp,'w'); fwrite(fid, jsonencode(payload)); fclose(fid);
movefile(tmp, target);          % atomic — do not skip this
```

The rename matters. Without it a reader lands mid-write and gets a truncated
file, which is exactly the defect that made the legacy SCADA blank every tag
for a frame.

### What has and has not been tested

| | status |
|---|---|
| `mock` transport | **Tested.** Covered by `selftest_extended.py` §12. |
| `file` transport | **Tested** against a fixture written by the same atomic-rename pattern. |
| `tcp` transport | **NOT tested against real MATLAB.** |
| Real Simulink model streaming | **NOT tested.** |

No MATLAB licence is available in this environment. The `tcp` wire format is
deliberately trivial — one JSON object per line — but it is unverified against
an actual `tcpclient`. **Do not treat it as proven.**

### Configuration

```json
"sources": {
  "matlab": {
    "enabled": true,
    "transport": "mock",          // mock | file | tcp
    "data_path": "data/matlab_live.json",
    "host": "127.0.0.1",
    "port": 5560,
    "poll_interval": 0.5,
    "stale_after": 5.0
  }
}
```

---

## 6. Adding a source

1. Subclass `DataSourceAdapter` in `backend/sources/`.
2. Set `supports_control` — **False unless it genuinely must command hardware.**
3. Implement `get_status()` and `read_latest()`; both must be non-blocking,
   because they are called from the composition path.
4. Register it in `Core.__init__`.

Nothing in the core, the API or the frontend changes. A source that does not
override `send_command` refuses writes by default, so a new adapter is
read-only until someone deliberately makes it otherwise.

---

## 7. API

| endpoint | purpose |
|---|---|
| `GET /api/sources` | all sources, modes, allowed transitions |
| `GET /api/sources/<id>` | one source in detail |
| `POST /api/sources/control` | hand over machine control (refusable) |
| `POST /api/sources/telemetry` | change the displayed source (grants no control) |
| `POST /api/sources/<id>/start` · `/stop` | adapter lifecycle |
| `GET /api/mode` | everything the mode banner needs, in one call |

`GET /api/state` also carries `dataSources` in every snapshot, so the UI needs
no extra request.
