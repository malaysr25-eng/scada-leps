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

PLC_IP = "172.21.30.157"   # change 172.21.30.157
RACK = 0
SLOT = 1

EXCEL_FILE = "Tag_list (1).xlsx"

# One PLC poll every 250 ms.
# Increase to 500 ms if the PLC/network is heavily loaded.
POLL_INTERVAL = 0.25

# Your Excel tags are all in DB59. We read the whole used DB range
# once per poll instead of doing 121 individual PLC reads.
DB_NUMBER = 59
DB_START = 0
DB_SIZE = 266

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

print("Loaded", len(TAGS), "tags")

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

            # ONE PLC READ FOR ALL 121 TAGS
            with plc_lock:
                if not plc.get_connected():
                    plc_connected = False
                    continue

                db_bytes = plc.db_read(
                    DB_NUMBER,
                    DB_START,
                    DB_SIZE
                )

            # Decode locally. No PLC communication here.
            new_values = {}

            for index, tag in enumerate(TAGS):
                new_values[index] = decode_tag(tag, db_bytes)

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
                    DB_NUMBER,
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
                    DB_NUMBER,
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
                    DB_NUMBER,
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
                    DB_NUMBER,
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
# MAIN
# ============================================================

if __name__ == "__main__":

    print("----------------------------------")
    print("S7-1200 PLC Flask Dashboard")
    print("----------------------------------")
    print("PLC:", PLC_IP)
    print("DB:", DB_NUMBER)
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
