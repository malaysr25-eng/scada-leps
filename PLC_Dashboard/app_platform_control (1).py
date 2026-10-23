from flask import Flask, render_template_string, request, jsonify
import snap7
from snap7.util import get_bool, set_bool, get_int, set_int, get_real, set_real
import pandas as pd
import re
import threading
import time
import json

# ============================================================
# CONFIGURATION
# ============================================================

PLC_IP = "172.21.30.157"
RACK = 0
SLOT = 1

EXCEL_FILE = "Tag_list (1).xlsx"

# One PLC poll every 250 ms.
# Increase to 500 ms if the PLC/network is heavily loaded.
POLL_INTERVAL = 0.25

# The tag list may contain tags from more than one DB (for example DB1
# contains the Axis_1/platform command tags).  The poller below builds
# the required DB ranges from the loaded tags instead of assuming DB59.

app = Flask(__name__)

# ============================================================
# PLC STATE
# ============================================================

plc = snap7.client.Client()

# ONLY the PLC worker uses the PLC connection.
# Flask requests never call plc.db_read() directly.
plc_lock = threading.RLock()

plc_connected = False
last_error = ""
last_update = 0.0

# Latest values shown by the dashboard
values_cache = {}

# Stop flag for background worker
stop_event = threading.Event()

# ============================================================
# LOAD TAGS
# ============================================================

def load_tags():
    all_tags = []
    excel = pd.ExcelFile(EXCEL_FILE)

    for sheet in excel.sheet_names:
        df = pd.read_excel(EXCEL_FILE, sheet_name=sheet)

        for _, row in df.iterrows():
            tag_name = row.get("Tag Name")
            data_type = row.get("Data type")
            db_address = row.get("DB Address")
            description = row.get("Description")

            if pd.isna(tag_name) or pd.isna(data_type) or pd.isna(db_address):
                continue

            tag_name = str(tag_name).strip()
            data_type = str(data_type).strip()
            db_address = str(db_address).strip()

            m = re.search(r"DB(\d+)\.(DBX|DBW|DBD)(\d+)(?:\.(\d+))?", db_address)
            if not m:
                continue

            tag = {
                "name": tag_name,
                "type": data_type,
                "address": db_address,
                "db": int(m.group(1)),
                "area": m.group(2),
                "byte": int(m.group(3)),
                "bit": int(m.group(4) or 0),
                "description": "" if pd.isna(description) else str(description),
                "sheet": sheet,
            }

            all_tags.append(tag)

    return all_tags


TAGS = load_tags()


def db_byte_size(tag):
    if tag["type"] == "Bool":
        return tag["byte"] + 1
    if tag["type"] == "Int":
        return tag["byte"] + 2
    if tag["type"] == "Real":
        return tag["byte"] + 4
    return tag["byte"] + 1


# One contiguous read per DB used by the tag list.
DB_RANGES = {}
for _tag in TAGS:
    _db = _tag["db"]
    DB_RANGES[_db] = max(DB_RANGES.get(_db, 0), db_byte_size(_tag))

print("Loaded", len(TAGS), "tags across DBs:", DB_RANGES)


def find_tag_index(name):
    name_l = name.lower()
    for i, tag in enumerate(TAGS):
        if tag["name"].lower() == name_l:
            return i
    return None

# ============================================================
# CONNECTION
# ============================================================

def ensure_connection():
    global plc_connected, last_error

    with plc_lock:
        try:
            if not plc.get_connected():
                print("Connecting to PLC:", PLC_IP)
                plc.connect(PLC_IP, RACK, SLOT)

            plc_connected = plc.get_connected()

            if plc_connected:
                last_error = ""

            return plc_connected

        except Exception as e:
            plc_connected = False
            last_error = str(e)
            print("PLC connection error:", e)

            try:
                if plc.get_connected():
                    plc.disconnect()
            except Exception:
                pass

            return False


def close_connection():
    global plc_connected

    with plc_lock:
        try:
            if plc.get_connected():
                plc.disconnect()
        except Exception:
            pass

        plc_connected = False


# ============================================================
# DECODE ONE TAG FROM THE CACHED DB BYTES
# ============================================================

def decode_tag(tag, db_bytes):
    try:
        offset = tag["byte"]

        if tag["type"] == "Bool":
            return get_bool(db_bytes, offset, tag["bit"])

        if tag["type"] == "Int":
            return get_int(db_bytes, offset)

        if tag["type"] == "Real":
            return round(get_real(db_bytes, offset), 3)

        return None

    except Exception as e:
        print("Decode error:", tag["name"], tag["address"], e)
        return None


# ============================================================
# BACKGROUND PLC POLLER
# ============================================================

def plc_worker():
    global values_cache, plc_connected, last_error, last_update

    print("PLC background worker started")

    while not stop_event.is_set():

        start = time.monotonic()

        try:
            if not ensure_connection():
                time.sleep(1.0)
                continue

            # Read each DB used by the tag list once per poll.
            # This is what allows DB1 Axis_1 tags to coexist with DB59 tags.
            with plc_lock:
                if not plc.get_connected():
                    plc_connected = False
                    continue

                db_cache = {}
                for db_number, db_size in DB_RANGES.items():
                    db_cache[db_number] = plc.db_read(db_number, 0, db_size)

            # Decode locally. No PLC communication here.
            new_values = {}

            for index, tag in enumerate(TAGS):
                new_values[index] = decode_tag(
                    tag,
                    db_cache.get(tag["db"], bytearray())
                )

            values_cache = new_values
            plc_connected = True
            last_error = ""
            last_update = time.time()

        except Exception as e:
            plc_connected = False
            last_error = str(e)

            print("PLC read error:", e)

            with plc_lock:
                try:
                    if plc.get_connected():
                        plc.disconnect()
                except Exception:
                    pass

        # Keep polling at the selected interval without piling up requests.
        elapsed = time.monotonic() - start
        wait_time = max(0.01, POLL_INTERVAL - elapsed)
        stop_event.wait(wait_time)

    close_connection()
    print("PLC background worker stopped")


# ============================================================
# WRITE TO PLC
# ============================================================

def write_tag(index, value):
    global plc_connected, last_error, values_cache

    if index < 0 or index >= len(TAGS):
        return False, "Invalid tag"

    tag = TAGS[index]

    if not ensure_connection():
        return False, "PLC disconnected: " + last_error

    try:
        with plc_lock:

            if not plc.get_connected():
                plc_connected = False
                return False, "PLC disconnected"

            offset = tag["byte"]

            # BOOL:
            # Read one byte, modify only the requested bit, write it back.
            if tag["type"] == "Bool":

                data = plc.db_read(
                    tag["db"],
                    offset,
                    1
                )

                new_value = bool(value)

                set_bool(
                    data,
                    0,
                    tag["bit"],
                    new_value
                )

                plc.db_write(
                    tag["db"],
                    offset,
                    data
                )

                # Update dashboard immediately.
                values_cache[index] = new_value

            # INT
            elif tag["type"] == "Int":

                data = bytearray(2)

                set_int(
                    data,
                    0,
                    int(value)
                )

                plc.db_write(
                    tag["db"],
                    offset,
                    data
                )

                values_cache[index] = int(value)

            # REAL
            elif tag["type"] == "Real":

                data = bytearray(4)

                set_real(
                    data,
                    0,
                    float(value)
                )

                plc.db_write(
                    tag["db"],
                    offset,
                    data
                )

                values_cache[index] = round(float(value), 3)

            else:
                return False, "Unsupported data type"

        plc_connected = True
        last_error = ""

        return True, ""

    except Exception as e:
        plc_connected = False
        last_error = str(e)

        print(
            "PLC write error:",
            tag["name"],
            tag["address"],
            e
        )

        try:
            with plc_lock:
                if plc.get_connected():
                    plc.disconnect()
        except Exception:
            pass

        return False, str(e)


# ============================================================
# DASHBOARD HTML
# ============================================================

HTML = r"""
<!DOCTYPE html>
<html>
<head>
<title>S7-1200 PLC Dashboard</title>

<meta name="viewport" content="width=device-width, initial-scale=1">

<style>
body {
    font-family: Arial, sans-serif;
    background: #111827;
    color: white;
    margin: 0;
}

header {
    background: #1f2937;
    padding: 18px 20px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    position: sticky;
    top: 0;
    z-index: 10;
}

h1 {
    margin: 0;
    font-size: 22px;
}

.status {
    padding: 9px 15px;
    border-radius: 20px;
    font-weight: bold;
}

.connected {
    background: #166534;
}

.disconnected {
    background: #991b1b;
}

.controls {
    padding: 15px 20px;
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
}

input, select {
    padding: 9px;
    border-radius: 6px;
    border: none;
}

#search {
    width: 300px;
}

table {
    width: 100%;
    border-collapse: collapse;
    background: #1f2937;
}

th {
    background: #374151;
    padding: 11px;
    text-align: left;
    position: sticky;
    top: 62px;
}

td {
    padding: 9px;
    border-bottom: 1px solid #374151;
}

tr:hover {
    background: #374151;
}

.tag-name {
    font-family: monospace;
    color: #93c5fd;
}

.address {
    font-family: monospace;
    color: #9ca3af;
}

.value {
    font-size: 17px;
    font-weight: bold;
}

.on {
    color: #4ade80;
}

.off {
    color: #f87171;
}

.error {
    color: #fbbf24;
}

button {
    padding: 7px 12px;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-weight: bold;
}

button:disabled {
    opacity: 0.5;
    cursor: wait;
}

.toggle {
    background: #2563eb;
    color: white;
}

.write {
    background: #059669;
    color: white;
}

.value-input {
    width: 85px;
}

.badge {
    padding: 4px 8px;
    border-radius: 5px;
    background: #4b5563;
}

#info {
    color: #9ca3af;
    font-size: 13px;
    padding: 0 20px 10px;
}

.platform-panel {
    margin: 0 20px 18px;
    padding: 16px;
    border: 1px solid #374151;
    border-radius: 10px;
    background: #1f2937;
}
.platform-title {
    font-size: 18px;
    font-weight: bold;
}
.platform-subtitle {
    color: #9ca3af;
    font-size: 13px;
    margin: 5px 0 12px;
}
.platform-buttons {
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
}
.platform-buttons button {
    min-width: 190px;
    min-height: 48px;
    font-size: 15px;
    user-select: none;
    touch-action: none;
}
.platform-up { background: #2563eb; color: white; }
.platform-down { background: #7c3aed; color: white; }
.platform-status {
    margin-top: 10px;
    color: #9ca3af;
    font-size: 13px;
}
</style>
</head>

<body>

<header>
    <h1>⚙ S7-1200 PLC Dashboard</h1>
    <div id="connection" class="status disconnected">
        PLC DISCONNECTED
    </div>
</header>

<div class="controls">

    <input
        type="text"
        id="search"
        placeholder="Search tag..."
        onkeyup="filterTags()">

    <select id="sheetFilter" onchange="filterTags()">
        <option value="all">All Groups</option>

        {% for sheet in sheets %}
        <option value="{{ sheet }}">{{ sheet }}</option>
        {% endfor %}
    </select>

</div>

<div id="info">
    Polling PLC in background. Dashboard requests never read the PLC directly.
    <span id="lastUpdate"></span>
</div>

<div class="platform-panel">
    <div class="platform-title">Axis_1 — Workpiece Platform</div>
    <div class="platform-subtitle">Momentary jog control. Hold a button to move; release to stop.</div>
    <div class="platform-buttons">
        <button class="platform-up"
                onmousedown="platformJog('up', true)"
                onmouseup="platformJog('up', false)"
                onmouseleave="platformJog('up', false)"
                ontouchstart="platformJog('up', true); event.preventDefault()"
                ontouchend="platformJog('up', false); event.preventDefault()">
            ▲ RAISE PLATFORM
        </button>
        <button class="platform-down"
                onmousedown="platformJog('down', true)"
                onmouseup="platformJog('down', false)"
                onmouseleave="platformJog('down', false)"
                ontouchstart="platformJog('down', true); event.preventDefault()"
                ontouchend="platformJog('down', false); event.preventDefault()">
            ▼ LOWER PLATFORM
        </button>
    </div>
    <div id="platformStatus" class="platform-status">Platform control ready</div>
</div>

<table>
<thead>
<tr>
    <th>Tag</th>
    <th>Type</th>
    <th>DB Address</th>
    <th>Description</th>
    <th>Live Value</th>
    <th>Control</th>
</tr>
</thead>

<tbody id="tagTable">

{% for i, tag in enumerate(tags) %}
<tr
    data-name="{{ tag.name|lower }}"
    data-sheet="{{ tag.sheet }}">

    <td class="tag-name">{{ tag.name }}</td>

    <td><span class="badge">{{ tag.type }}</span></td>

    <td class="address">{{ tag.address }}</td>

    <td>{{ tag.description }}</td>

    <td>
        <span id="value-{{ i }}" class="value">---</span>
    </td>

    <td>

    {% if tag.type == "Bool" %}

        <button
            id="button-{{ i }}"
            class="toggle"
            onclick="toggleTag({{ i }})">
            Toggle
        </button>

    {% elif tag.type == "Int" or tag.type == "Real" %}

        <input
            class="value-input"
            id="input-{{ i }}"
            type="number"
            step="any">

        <button
            id="button-{{ i }}"
            class="write"
            onclick="writeTag({{ i }})">
            Write
        </button>

    {% endif %}

    </td>
</tr>
{% endfor %}

</tbody>
</table>


<script>

const tags = {{ tags_json|safe }};

let writeInProgress = false;


// ========================================================
// GET CACHED VALUES
// ========================================================

async function updateValues() {

    try {

        const response = await fetch(
            "/api/read",
            {
                cache: "no-store"
            }
        );

        const data = await response.json();

        const status =
            document.getElementById("connection");

        if (data.connected) {

            status.innerText = "PLC CONNECTED";
            status.className = "status connected";

        } else {

            status.innerText = "PLC DISCONNECTED";
            status.className = "status disconnected";
        }


        if (data.last_update) {

            const d = new Date(
                data.last_update * 1000
            );

            document.getElementById(
                "lastUpdate"
            ).innerText =
                "  Last PLC update: " +
                d.toLocaleTimeString();

        }


        data.values.forEach((item, index) => {

            const element =
                document.getElementById(
                    "value-" + index
                );

            if (!element)
                return;


            if (item.value === null) {

                element.innerText = "---";
                element.className = "value error";

                return;
            }


            if (item.type === "Bool") {

                element.innerText =
                    item.value ? "ON" : "OFF";

                element.className =
                    item.value
                    ? "value on"
                    : "value off";

            } else {

                element.innerText =
                    item.value;

                element.className =
                    "value";
            }

        });

    } catch (error) {

        console.log("Dashboard error:", error);
    }
}


// ========================================================
// TOGGLE BOOL
// ========================================================

async function toggleTag(index) {

    if (writeInProgress)
        return;

    writeInProgress = true;

    const button =
        document.getElementById(
            "button-" + index
        );

    button.disabled = true;
    button.innerText = "Writing...";


    try {

        // Read the cached/current PLC value.
        const response =
            await fetch(
                "/api/read/" + index,
                { cache: "no-store" }
            );

        const data =
            await response.json();


        if (data.value === null) {

            alert(
                "PLC value unavailable."
            );

            return;
        }


        const newValue =
            !data.value;


        const writeResponse =
            await fetch(
                "/api/write/" + index,
                {
                    method: "POST",
                    headers: {
                        "Content-Type":
                            "application/json"
                    },
                    body: JSON.stringify({
                        value: newValue
                    })
                }
            );


        const result =
            await writeResponse.json();


        if (!result.success) {

            alert(
                "PLC write failed:\n" +
                result.error
            );

        }


    } catch (error) {

        alert(
            "Communication error:\n" +
            error
        );

    } finally {

        button.disabled = false;
        button.innerText = "Toggle";

        writeInProgress = false;

        updateValues();
    }
}


// ========================================================
// WRITE INT / REAL
// ========================================================

async function writeTag(index) {

    if (writeInProgress)
        return;

    const input =
        document.getElementById(
            "input-" + index
        );

    const value =
        input.value;


    if (value === "") {

        alert("Enter a value.");
        return;
    }


    writeInProgress = true;

    const button =
        document.getElementById(
            "button-" + index
        );

    button.disabled = true;
    button.innerText = "Writing...";


    try {

        const response =
            await fetch(
                "/api/write/" + index,
                {
                    method: "POST",
                    headers: {
                        "Content-Type":
                            "application/json"
                    },
                    body: JSON.stringify({
                        value: value
                    })
                }
            );


        const result =
            await response.json();


        if (!result.success) {

            alert(
                "PLC write failed:\n" +
                result.error
            );
        }


    } catch (error) {

        alert(
            "Communication error:\n" +
            error
        );

    } finally {

        button.disabled = false;
        button.innerText = "Write";

        writeInProgress = false;

        updateValues();
    }
}


// ========================================================
// AXIS_1 PLATFORM JOG
// ========================================================

let platformRequestInProgress = false;

async function platformJog(direction, active) {
    if (platformRequestInProgress && active) return;
    platformRequestInProgress = true;

    const status = document.getElementById("platformStatus");
    status.innerText = active
        ? (direction === "up" ? "Raising platform..." : "Lowering platform...")
        : "Platform stopped";

    try {
        const response = await fetch("/api/platform/jog", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ direction: direction, active: active })
        });
        const result = await response.json();
        if (!result.success) {
            status.innerText = "Platform control: " + result.error;
        }
    } catch (error) {
        status.innerText = "Platform communication error: " + error;
    } finally {
        platformRequestInProgress = false;
    }
}


// ========================================================
// SEARCH
// ========================================================

function filterTags() {

    const search =
        document.getElementById(
            "search"
        ).value.toLowerCase();


    const sheet =
        document.getElementById(
            "sheetFilter"
        ).value;


    document
        .querySelectorAll("#tagTable tr")
        .forEach(row => {

            const name =
                row.dataset.name;

            const rowSheet =
                row.dataset.sheet;


            const matchesSearch =
                name.includes(search);

            const matchesSheet =
                sheet === "all" ||
                rowSheet === sheet;


            row.style.display =
                matchesSearch &&
                matchesSheet
                ? ""
                : "none";
        });
}


// ========================================================
// DASHBOARD REFRESH
// ========================================================

// This only reads Python's memory cache.
// It DOES NOT communicate with the PLC.
updateValues();

setInterval(
    updateValues,
    500
);

</script>

</body>
</html>
"""


# ============================================================
# FLASK ROUTES
# ============================================================

@app.route("/")
def dashboard():

    sheets = sorted(
        list(
            set(
                tag["sheet"]
                for tag in TAGS
            )
        )
    )

    return render_template_string(
        HTML,
        tags=TAGS,
        sheets=sheets,
        tags_json=json.dumps(TAGS),
        enumerate=enumerate
    )


# ============================================================
# READ ALL
# ============================================================

@app.route("/api/read")
def read_all():

    output = []

    for index, tag in enumerate(TAGS):

        output.append({
            "name": tag["name"],
            "type": tag["type"],
            "value": values_cache.get(index)
        })

    return jsonify({
        "connected": plc_connected,
        "values": output,
        "last_update": last_update,
        "error": last_error
    })


# ============================================================
# READ SINGLE
# ============================================================

@app.route("/api/read/<int:index>")
def read_single(index):

    if index < 0 or index >= len(TAGS):

        return jsonify({
            "value": None,
            "error": "Invalid tag"
        }), 400

    return jsonify({
        "value": values_cache.get(index),
        "connected": plc_connected,
        "error": last_error
    })


# ============================================================
# WRITE
# ============================================================

@app.route("/api/write/<int:index>", methods=["POST"])
def write_single(index):

    if index < 0 or index >= len(TAGS):

        return jsonify({
            "success": False,
            "error": "Invalid tag"
        }), 400


    data = request.get_json(silent=True)

    if not data or "value" not in data:

        return jsonify({
            "success": False,
            "error": "No value supplied"
        }), 400


    tag = TAGS[index]
    value = data["value"]


    if tag["type"] == "Bool":

        if not isinstance(value, bool):

            value = str(value).lower() in [
                "true",
                "1",
                "on"
            ]


    try:

        success, error = write_tag(
            index,
            value
        )

        return jsonify({
            "success": success,
            "error": error
        })

    except Exception as e:

        return jsonify({
            "success": False,
            "error": str(e)
        }), 500


# ============================================================
# AXIS_1 / WORKPIECE PLATFORM MANUAL CONTROL
# ============================================================

# These are the symbolic DB1 tags used by the existing PLC program for
# Axis_1.  The buttons below are momentary jog controls, not latched toggles:
# holding UP/DOWN keeps the corresponding jog bit on; releasing it turns it off.
PLATFORM_TAGS = {
    "power": "en_mc_power",
    "up": "exe_jogforward",
    "down": "exe_jogbackward",
    "velocity": "exe_jogvelocity",
    "upper_limit": "pgm_upper_limit_switch",
    "lower_limit": "pgm_lower_limit_switch",
    "power_status": "mc_power_status",
    "power_error": "mc_power_error",
}


def platform_index(key):
    return find_tag_index(PLATFORM_TAGS[key])


def platform_write_bool(name, value):
    idx = find_tag_index(name)
    if idx is None:
        return False, f"Tag '{name}' was not found in the configured Excel tag list."
    tag = TAGS[idx]
    if tag["type"] != "Bool":
        return False, f"Tag '{name}' is not a Bool."
    return write_tag(idx, bool(value))


@app.route("/api/platform/jog", methods=["POST"])
def platform_jog():
    data = request.get_json(silent=True) or {}
    direction = str(data.get("direction", "")).lower()
    active = bool(data.get("active", False))

    if direction not in ("up", "down"):
        return jsonify({"success": False, "error": "Invalid platform direction."}), 400

    # Read the limit state from the dashboard cache before allowing a jog.
    limit_key = "upper_limit" if direction == "up" else "lower_limit"
    limit_idx = platform_index(limit_key)
    if limit_idx is None:
        return jsonify({"success": False, "error": f"Missing platform limit tag: {PLATFORM_TAGS[limit_key]}"}), 500

    limit_value = values_cache.get(limit_idx)
    if active and limit_value is True:
        # Never jog farther into an active physical limit.
        return jsonify({"success": False, "error": f"{limit_key.replace('_', ' ').title()} limit is active."}), 409

    # Axis power is required by MC_MoveJog. We do not force it off on release;
    # the existing PLC logic remains responsible for the axis power state.
    if active:
        ok, err = platform_write_bool(PLATFORM_TAGS["power"], True)
        if not ok:
            return jsonify({"success": False, "error": err}), 500

    # Momentary command: UP=JogForward, DOWN=JogBackward.
    selected = PLATFORM_TAGS[direction]
    other = PLATFORM_TAGS["down" if direction == "up" else "up"]

    # Ensure the opposite command is never left active.
    ok, err = platform_write_bool(other, False)
    if not ok:
        return jsonify({"success": False, "error": err}), 500

    ok, err = platform_write_bool(selected, active)
    if not ok:
        return jsonify({"success": False, "error": err}), 500

    return jsonify({"success": True, "active": active, "direction": direction})


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    print("----------------------------------")
    print("S7-1200 PLC Flask Dashboard")
    print("----------------------------------")
    print("PLC:", PLC_IP)
    print("DB ranges:", DB_RANGES)
    print("Tags:", len(TAGS))
    print("Poll interval:", POLL_INTERVAL, "seconds")
    print("Dashboard: http://127.0.0.1:5000")
    print("----------------------------------")

    # Start ONE background PLC communication thread.
    worker = threading.Thread(
        target=plc_worker,
        daemon=True
    )

    worker.start()

    try:

        # IMPORTANT:
        # threaded=True lets multiple browsers access Flask,
        # while PLC communication remains serialized in plc_worker.
        app.run(
            host="0.0.0.0",
            port=5000,
            debug=False,
            threaded=True
        )

    finally:

        stop_event.set()
        worker.join(timeout=3)
        close_connection()
