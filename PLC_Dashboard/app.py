from flask import Flask, render_template_string, request, jsonify
import snap7
from snap7.util import get_bool, set_bool, get_int, set_int, get_real, set_real
import pandas as pd
import re
import threading
import time

# ============================================================
# CONFIGURATION
# ============================================================

PLC_IP = "172.21.30.157"       # <-- CHANGE TO YOUR PLC IP
RACK = 0
SLOT = 1

EXCEL_FILE = "Tag_list (1).xlsx"

app = Flask(__name__)

# ============================================================
# PLC CONNECTION
# ============================================================

plc = snap7.client.Client()
plc_lock = threading.Lock()


def connect_plc():
    try:
        if not plc.get_connected():
            plc.connect(PLC_IP, RACK, SLOT)

        return plc.get_connected()

    except Exception as e:
        print("PLC connection error:", e)
        return False


def disconnect_plc():
    try:
        if plc.get_connected():
            plc.disconnect()
    except:
        pass


# ============================================================
# LOAD TAGS FROM EXCEL
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

            # Ignore section headings / empty rows
            if pd.isna(tag_name):
                continue

            if pd.isna(data_type):
                continue

            if pd.isna(db_address):
                continue

            tag_name = str(tag_name).strip()
            data_type = str(data_type).strip()
            db_address = str(db_address).strip()

            # Parse DB number
            db_match = re.search(r"DB(\d+)", db_address)

            if not db_match:
                continue

            db_number = int(db_match.group(1))

            tag = {
                "name": tag_name,
                "type": data_type,
                "address": db_address,
                "db": db_number,
                "description": "" if pd.isna(description) else str(description),
                "sheet": sheet
            }

            all_tags.append(tag)

    return all_tags


TAGS = load_tags()

print("Loaded", len(TAGS), "tags")


# ============================================================
# PARSE DB ADDRESS
# ============================================================

def parse_address(address):

    # Example:
    # DB59.DBX0.0
    # DB59.DBW108.0
    # DB59.DBD152.0

    match = re.search(
        r"DB(\d+)\.(DBX|DBW|DBD)(\d+)(?:\.(\d+))?",
        address
    )

    if not match:
        raise ValueError("Invalid DB address: " + address)

    db_number = int(match.group(1))
    area = match.group(2)
    byte_offset = int(match.group(3))

    bit = 0

    if match.group(4):
        bit = int(match.group(4))

    return db_number, area, byte_offset, bit


# ============================================================
# READ TAG
# ============================================================

def read_tag(tag):

    if not connect_plc():
        return None

    try:

        db_number, area, byte_offset, bit = parse_address(
            tag["address"]
        )

        data_type = tag["type"]

        with plc_lock:

            if data_type == "Bool":

                data = plc.db_read(
                    db_number,
                    byte_offset,
                    1
                )

                value = get_bool(
                    data,
                    0,
                    bit
                )

            elif data_type == "Int":

                data = plc.db_read(
                    db_number,
                    byte_offset,
                    2
                )

                value = get_int(
                    data,
                    0
                )

            elif data_type == "Real":

                data = plc.db_read(
                    db_number,
                    byte_offset,
                    4
                )

                value = round(
                    get_real(data, 0),
                    3
                )

            else:
                value = "Unsupported"

        return value

    except Exception as e:

        print(
            "Read error:",
            tag["name"],
            tag["address"],
            e
        )

        return None


# ============================================================
# WRITE TAG
# ============================================================

def write_tag(tag, value):

    if not connect_plc():
        return False

    try:

        db_number, area, byte_offset, bit = parse_address(
            tag["address"]
        )

        data_type = tag["type"]

        with plc_lock:

            if data_type == "Bool":

                # Read existing byte first
                data = plc.db_read(
                    db_number,
                    byte_offset,
                    1
                )

                value = bool(value)

                set_bool(
                    data,
                    0,
                    bit,
                    value
                )

                plc.db_write(
                    db_number,
                    byte_offset,
                    data
                )

            elif data_type == "Int":

                data = bytearray(2)

                set_int(
                    data,
                    0,
                    int(value)
                )

                plc.db_write(
                    db_number,
                    byte_offset,
                    data
                )

            elif data_type == "Real":

                data = bytearray(4)

                set_real(
                    data,
                    0,
                    float(value)
                )

                plc.db_write(
                    db_number,
                    byte_offset,
                    data
                )

            else:
                return False

        return True

    except Exception as e:

        print(
            "Write error:",
            tag["name"],
            tag["address"],
            e
        )

        return False


# ============================================================
# DASHBOARD
# ============================================================

HTML = """

<!DOCTYPE html>

<html>

<head>

<title>S7-1200 PLC Dashboard</title>

<meta name="viewport"
      content="width=device-width, initial-scale=1">

<style>

body {
    font-family: Arial, sans-serif;
    background: #111827;
    color: white;
    margin: 0;
}

header {
    background: #1f2937;
    padding: 20px;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

h1 {
    margin: 0;
}

.status {
    padding: 10px 16px;
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
    padding: 20px;
}

input {
    padding: 10px;
    border-radius: 6px;
    border: none;
    width: 300px;
}

select {
    padding: 10px;
    border-radius: 6px;
}

table {
    width: 100%;
    border-collapse: collapse;
    background: #1f2937;
}

th {
    background: #374151;
    padding: 12px;
    text-align: left;
}

td {
    padding: 10px;
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
    font-size: 18px;
    font-weight: bold;
}

.on {
    color: #4ade80;
}

.off {
    color: #f87171;
}

button {
    padding: 8px 14px;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-weight: bold;
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
    width: 100px;
    padding: 7px;
}

.badge {
    padding: 4px 8px;
    border-radius: 5px;
    background: #4b5563;
}

</style>

</head>


<body>


<header>

<h1>⚙ S7-1200 PLC Dashboard</h1>

<div id="connection"
     class="status disconnected">

PLC DISCONNECTED

</div>

</header>


<div class="controls">

<input
    type="text"
    id="search"
    placeholder="Search tag..."
    onkeyup="filterTags()">


<select id="sheetFilter"
        onchange="filterTags()">

<option value="all">
All Groups
</option>

{% for sheet in sheets %}

<option value="{{ sheet }}">
{{ sheet }}
</option>

{% endfor %}

</select>

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

<td class="tag-name">

{{ tag.name }}

</td>

<td>

<span class="badge">

{{ tag.type }}

</span>

</td>

<td class="address">

{{ tag.address }}

</td>

<td>

{{ tag.description }}

</td>

<td>

<span
    id="value-{{ i }}"
    class="value">

Loading...

</span>

</td>

<td>

{% if tag.type == "Bool" %}

<button
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


// ========================================================
// TAG DATA
// ========================================================

const tags = {{ tags_json|safe }};


// ========================================================
// READ ALL TAGS
// ========================================================

async function updateValues() {

    try {

        const response =
            await fetch("/api/read");

        const data =
            await response.json();


        // Connection status

        const status =
            document.getElementById("connection");


        if (data.connected) {

            status.innerText =
                "PLC CONNECTED";

            status.className =
                "status connected";

        } else {

            status.innerText =
                "PLC DISCONNECTED";

            status.className =
                "status disconnected";

        }


        // Update values

        data.values.forEach((item, index) => {

            const element =
                document.getElementById(
                    "value-" + index
                );

            if (!element)
                return;


            if (item.value === null) {

                element.innerText =
                    "ERROR";

                element.className =
                    "value";

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

        console.log(error);

    }

}


// ========================================================
// TOGGLE BOOL
// ========================================================

async function toggleTag(index) {

    const tag = tags[index];


    // First read current value

    const response =
        await fetch("/api/read/" + index);

    const data =
        await response.json();


    if (data.value === null) {

        alert("Cannot read PLC tag");

        return;

    }


    const newValue =
        !data.value;


    await fetch("/api/write/" + index, {

        method: "POST",

        headers: {
            "Content-Type":
                "application/json"
        },

        body: JSON.stringify({
            value: newValue
        })

    });


    updateValues();

}


// ========================================================
// WRITE INT / REAL
// ========================================================

async function writeTag(index) {

    const input =
        document.getElementById(
            "input-" + index
        );


    const value =
        input.value;


    if (value === "") {

        alert("Enter a value");

        return;

    }


    const response =
        await fetch("/api/write/" + index, {

            method: "POST",

            headers: {
                "Content-Type":
                    "application/json"
            },

            body: JSON.stringify({
                value: value
            })

        });


    const result =
        await response.json();


    if (!result.success) {

        alert("Write failed");

    }


    updateValues();

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


    const rows =
        document.querySelectorAll(
            "#tagTable tr"
        );


    rows.forEach(row => {

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
// LIVE UPDATE EVERY SECOND
// ========================================================

updateValues();

setInterval(
    updateValues,
    1000
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
        tags_json=TAGS,
        enumerate=enumerate
    )


# ============================================================
# READ ALL
# ============================================================

@app.route("/api/read")
def read_all():

    values = []

    connected = connect_plc()

    for tag in TAGS:

        value = read_tag(tag)

        values.append({
            "name": tag["name"],
            "type": tag["type"],
            "value": value
        })

    return jsonify({
        "connected": connected,
        "values": values
    })


# ============================================================
# READ SINGLE TAG
# ============================================================

@app.route("/api/read/<int:index>")
def read_single(index):

    if index < 0 or index >= len(TAGS):

        return jsonify({
            "value": None,
            "error": "Invalid tag"
        }), 400


    value = read_tag(
        TAGS[index]
    )


    return jsonify({
        "value": value
    })


# ============================================================
# WRITE
# ============================================================

@app.route(
    "/api/write/<int:index>",
    methods=["POST"]
)
def write_single(index):

    if index < 0 or index >= len(TAGS):

        return jsonify({
            "success": False,
            "error": "Invalid tag"
        }), 400


    data = request.get_json()

    if not data or "value" not in data:

        return jsonify({
            "success": False,
            "error": "No value supplied"
        }), 400


    tag = TAGS[index]

    value = data["value"]


    # Convert Boolean

    if tag["type"] == "Bool":

        if isinstance(value, bool):

            pass

        else:

            value = str(value).lower()

            value = value in [
                "true",
                "1",
                "on"
            ]


    try:

        success = write_tag(
            tag,
            value
        )

        return jsonify({
            "success": success
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

    print(
        "PLC:",
        PLC_IP
    )

    print(
        "Tags:",
        len(TAGS)
    )

    print(
        "Dashboard:",
        "http://127.0.0.1:5000"
    )

    connect_plc()

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=False
    )