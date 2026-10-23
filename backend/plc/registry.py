"""
Tag registry: the single authority on what every PLC address means.

SOURCES, IN PRECEDENCE ORDER
----------------------------
1. ``Tag_list (1).xlsx`` -- the vendor/commissioning tag list. This is the ONLY
   source treated as authoritative for address-to-meaning mapping.
2. ``config/tag_overlay.json`` -- engineering metadata layered on top:
   subsystem grouping, write-access class, semantic role, and physical
   placement for the factory schematic. The overlay never invents an address;
   it may only annotate an address the Excel already documents, or declare a
   block as explicitly UNDOCUMENTED/raw.

WHAT THIS FILE DELIBERATELY DOES NOT DO
---------------------------------------
It does not guess. Bytes 266-269 of DB59 are read by the legacy
``json_write_for_web_tag.py`` and surfaced by the legacy SCADA Hub as sensors
and solenoid valves, but they appear NOWHERE in the tag list, which ends at
DB59.DBX265.7. Those bits are therefore registered as ``raw.*`` diagnostic tags
with provenance UNDOCUMENTED and access READ_ONLY. They are visible in the Tag
Explorer so an engineer can verify them against the real PLC, and they are
never used to drive the HMI's sensor or valve indicators.

See docs/TAG_MAP.md and docs/DEBUGGING_REPORT.md (issue E-18).
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional

from backend.util.xlsx import read_workbook

# Matches DB59.DBX128.0 / DB59.DBW108.0 / DB59.DBD132.0
_ADDR_RE = re.compile(r"DB(\d+)\.(DBX|DBW|DBD)(\d+)(?:\.(\d+))?", re.IGNORECASE)

# Write-access classes. Enforced in backend/services/safety.py, not here.
ACCESS_READ_ONLY = "read_only"       # never writable from the HMI
ACCESS_SAFE_MANUAL = "safe_manual"   # writable in MANUAL mode, interlocked
ACCESS_ENGINEERING = "engineering"   # writable in MAINTENANCE mode, confirmed
ACCESS_PROTECTED = "protected"       # only via a dedicated validated endpoint

PROV_DOCUMENTED = "documented"
PROV_UNDOCUMENTED = "undocumented"

_SIZE_BY_TYPE = {"Bool": 1, "Int": 2, "Real": 4, "DInt": 4, "Word": 2}


@dataclass
class Tag:
    """One addressable PLC datum."""

    id: str
    name: str
    short: str
    dtype: str
    db: int
    byte: int
    bit: int
    address: str
    description: str
    group: str
    access: str
    provenance: str
    role: Optional[str] = None
    sheet: str = ""
    unit: str = ""
    notes: str = ""

    # Commissioned engineering range, from the overlay's "min"/"max". Both stay
    # None when nobody has commissioned a limit for the tag, and CommandGate
    # then range-checks nothing -- an absent limit must never read as 0.
    minimum: Optional[float] = None
    maximum: Optional[float] = None

    @property
    def byte_span(self) -> int:
        return _SIZE_BY_TYPE.get(self.dtype, 1)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["writable"] = self.access != ACCESS_READ_ONLY
        return d


@dataclass
class Registry:
    tags: List[Tag] = field(default_factory=list)
    by_id: Dict[str, Tag] = field(default_factory=dict)
    by_role: Dict[str, Tag] = field(default_factory=dict)
    by_address: Dict[str, Tag] = field(default_factory=dict)
    db_extents: Dict[int, int] = field(default_factory=dict)
    warnings: List[str] = field(default_factory=list)

    def get(self, tag_id: str) -> Optional[Tag]:
        return self.by_id.get(tag_id)

    def role(self, role_name: str) -> Optional[Tag]:
        return self.by_role.get(role_name)

    def groups(self) -> List[str]:
        seen: List[str] = []
        for t in self.tags:
            if t.group not in seen:
                seen.append(t.group)
        return seen


def _slugify(name: str) -> str:
    """``"DB_Global".IO Status.Digital_Inputs.Proximity_sensor1`` ->
    ``io_status.digital_inputs.proximity_sensor1``."""
    cleaned = name.replace('"', "").strip()
    if cleaned.startswith("DB_Global."):
        cleaned = cleaned[len("DB_Global."):]
    parts = [p for p in cleaned.split(".") if p]
    slug_parts = []
    for p in parts:
        p = re.sub(r"[^A-Za-z0-9]+", "_", p).strip("_").lower()
        if p:
            slug_parts.append(p)
    return ".".join(slug_parts) or "unnamed"


def _short_name(name: str) -> str:
    cleaned = name.replace('"', "").strip()
    return cleaned.split(".")[-1] if "." in cleaned else cleaned


def _opt_float(raw: Any) -> Optional[float]:
    """
    Overlay limits are optional. A key that is absent, null, or unparseable
    yields None (= "no commissioned limit"), never a silent 0.0 that would
    clamp every write to a bound nobody configured.
    """
    if raw is None or isinstance(raw, bool):
        return None
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return None
    return value if value == value and value not in (float("inf"), float("-inf")) else None


def _normalise_type(raw: str) -> Optional[str]:
    t = (raw or "").strip().lower()
    return {
        "bool": "Bool",
        "int": "Int",
        "real": "Real",
        "dint": "DInt",
        "word": "Word",
    }.get(t)


def load_registry(excel_path: str, overlay_path: str) -> Registry:
    """Build the registry from the tag list plus the engineering overlay."""
    reg = Registry()

    overlay: dict = {"tags": {}, "raw_blocks": [], "sheet_defaults": {}}
    if os.path.exists(overlay_path):
        with open(overlay_path, "r", encoding="utf-8") as fh:
            overlay.update(json.load(fh))
    else:
        reg.warnings.append(
            "Tag overlay not found at %s; every tag falls back to read-only."
            % overlay_path
        )

    if not os.path.exists(excel_path):
        reg.warnings.append(
            "Tag list not found at %s. The registry is EMPTY -- the HMI will "
            "start in a degraded, read-only state. Point config/config.json at "
            "the real Tag_list workbook." % excel_path
        )
        return reg

    book = read_workbook(excel_path)
    tag_rules = overlay.get("tags", {})
    sheet_defaults = overlay.get("sheet_defaults", {})

    for sheet_name, rows in book.items():
        if not rows:
            continue

        header = [c.strip().lower() for c in rows[0]]

        def col(*candidates: str) -> Optional[int]:
            for cand in candidates:
                if cand in header:
                    return header.index(cand)
            return None

        c_name = col("tag name")
        c_type = col("data type", "datatype")
        c_addr = col("db address", "address")
        c_desc = col("description")

        if c_name is None or c_addr is None:
            reg.warnings.append(
                "Sheet '%s' has no recognisable header row; skipped." % sheet_name
            )
            continue

        defaults = sheet_defaults.get(sheet_name, {})

        for row in rows[1:]:

            def cell(i: Optional[int]) -> str:
                if i is None or i >= len(row):
                    return ""
                return (row[i] or "").strip()

            name = cell(c_name)
            addr = cell(c_addr)
            dtype = _normalise_type(cell(c_type))

            # Section banner rows ("STRATUP TAGS", "Digital input status", ...)
            # carry a label but no address. Skip them silently.
            if not name or not addr or not dtype:
                continue

            m = _ADDR_RE.search(addr)
            if not m:
                reg.warnings.append(
                    "Unparseable address '%s' for tag '%s'; skipped." % (addr, name)
                )
                continue

            db = int(m.group(1))
            byte = int(m.group(3))
            bit = int(m.group(4) or 0)

            # DBW/DBD addresses in this workbook carry a trailing '.0' that is
            # a formatting artefact, not a bit index.
            if m.group(2).upper() != "DBX":
                bit = 0

            tag_id = _slugify(name)
            rule = tag_rules.get(tag_id, {})

            tag = Tag(
                id=tag_id,
                name=name.replace('"', "").strip(),
                short=rule.get("short") or _short_name(name),
                dtype=dtype,
                db=db,
                byte=byte,
                bit=bit,
                address=addr,
                description=cell(c_desc),
                group=rule.get("group") or defaults.get("group") or sheet_name,
                access=rule.get("access") or defaults.get("access") or ACCESS_READ_ONLY,
                provenance=PROV_DOCUMENTED,
                role=rule.get("role"),
                sheet=sheet_name,
                unit=rule.get("unit", ""),
                notes=rule.get("notes", ""),
                minimum=_opt_float(rule.get("min")),
                maximum=_opt_float(rule.get("max")),
            )

            if tag.id in reg.by_id:
                # Duplicate symbolic names would silently shadow each other.
                reg.warnings.append(
                    "Duplicate tag id '%s' (%s vs %s); keeping the first."
                    % (tag.id, tag.address, reg.by_id[tag.id].address)
                )
                continue

            _register(reg, tag)

    # ---- explicitly-declared raw / undocumented blocks -------------------
    for block in overlay.get("raw_blocks", []):
        _register_raw_block(reg, block)

    return reg


def _register(reg: Registry, tag: Tag) -> None:
    reg.tags.append(tag)
    reg.by_id[tag.id] = tag
    reg.by_address[tag.address.upper()] = tag

    if tag.role:
        if tag.role in reg.by_role:
            reg.warnings.append(
                "Role '%s' claimed by both %s and %s; keeping the first."
                % (tag.role, reg.by_role[tag.role].id, tag.id)
            )
        else:
            reg.by_role[tag.role] = tag

    end = tag.byte + tag.byte_span
    reg.db_extents[tag.db] = max(reg.db_extents.get(tag.db, 0), end)


def _register_raw_block(reg: Registry, block: dict) -> None:
    """
    Register a contiguous span of bits/words the tag list does NOT document.

    These exist so an engineer can observe the region on live hardware and
    decide what it actually is. They are always READ_ONLY and always flagged
    UNDOCUMENTED so nothing in the HMI can quietly start trusting them.
    """
    db = int(block["db"])
    start = int(block["start_byte"])
    end = int(block["end_byte"])
    dtype = block.get("dtype", "Bool")
    group = block.get("group", "Diagnostics / Raw")
    note = block.get("notes", "")
    desc = block.get("description", "Undocumented address -- meaning unconfirmed.")

    if dtype == "Bool":
        for byte in range(start, end + 1):
            for bit in range(8):
                tag = Tag(
                    id="raw.db%d.x%d_%d" % (db, byte, bit),
                    name="RAW DB%d.DBX%d.%d" % (db, byte, bit),
                    short="DBX%d.%d" % (byte, bit),
                    dtype="Bool",
                    db=db,
                    byte=byte,
                    bit=bit,
                    address="DB%d.DBX%d.%d" % (db, byte, bit),
                    description=desc,
                    group=group,
                    access=ACCESS_READ_ONLY,
                    provenance=PROV_UNDOCUMENTED,
                    sheet="(raw)",
                    notes=note,
                )
                if tag.id not in reg.by_id:
                    _register(reg, tag)
    else:
        step = _SIZE_BY_TYPE.get(dtype, 2)
        for byte in range(start, end + 1, step):
            tag = Tag(
                id="raw.db%d.w%d" % (db, byte),
                name="RAW DB%d.DBW%d" % (db, byte),
                short="DBW%d" % byte,
                dtype=dtype,
                db=db,
                byte=byte,
                bit=0,
                address="DB%d.DBW%d.0" % (db, byte),
                description=desc,
                group=group,
                access=ACCESS_READ_ONLY,
                provenance=PROV_UNDOCUMENTED,
                sheet="(raw)",
                notes=note,
            )
            if tag.id not in reg.by_id:
                _register(reg, tag)
