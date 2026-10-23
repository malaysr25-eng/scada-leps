"""
Minimal, dependency-free .xlsx reader.

WHY THIS EXISTS
---------------
The original PLC_Dashboard loaded `Tag_list (1).xlsx` with pandas + openpyxl.
That pulled ~60 MB of transitive dependencies into a lab PC whose only job is
to run an HMI, and pandas is not present in the Final/ venv at all -- so the
two halves of the system could not even share one interpreter.

An .xlsx file is a ZIP of XML. Reading the handful of string/number cells in a
tag list needs the standard library and nothing else. This keeps the whole
backend installable with `pip install flask python-snap7` on a machine with no
internet connection.

Scope: reads cell values as text. No formulas, styles, dates or types --
the tag list has none of those and the registry parses everything itself.
"""

from __future__ import annotations

import re
import zipfile
import xml.etree.ElementTree as ET
from typing import Dict, List

_MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
_DOCREL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"

_COL_RE = re.compile(r"([A-Z]+)")


def _column_index(cell_ref: str) -> int:
    """'BC12' -> 54 (zero-based column index)."""
    match = _COL_RE.match(cell_ref)
    if not match:
        return 0
    n = 0
    for ch in match.group(1):
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def _shared_strings(zf: zipfile.ZipFile) -> List[str]:
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
    out = []
    for si in root.findall(_MAIN + "si"):
        # <si> may hold one <t>, or several <r><t> runs for rich text.
        out.append("".join(t.text or "" for t in si.iter(_MAIN + "t")))
    return out


def _sheet_targets(zf: zipfile.ZipFile) -> List[tuple]:
    workbook = ET.fromstring(zf.read("xl/workbook.xml"))
    rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    rel_map = {r.get("Id"): r.get("Target") for r in rels}

    sheets = []
    for sheet in workbook.find(_MAIN + "sheets"):
        target = rel_map.get(sheet.get(_DOCREL + "id"), "")
        if not target.startswith("xl/"):
            target = "xl/" + target.lstrip("/")
        sheets.append((sheet.get("name"), target))
    return sheets


def read_workbook(path: str) -> Dict[str, List[List[str]]]:
    """
    Return {sheet_name: [[cell, cell, ...], ...]}.

    Rows are ragged: each row is only as wide as its last populated cell.
    Callers must index defensively.
    """
    with zipfile.ZipFile(path) as zf:
        strings = _shared_strings(zf)
        names = zf.namelist()
        book: Dict[str, List[List[str]]] = {}

        for sheet_name, target in _sheet_targets(zf):
            if target not in names:
                book[sheet_name] = []
                continue

            root = ET.fromstring(zf.read(target))
            sheet_data = root.find(_MAIN + "sheetData")
            if sheet_data is None:
                book[sheet_name] = []
                continue

            rows: List[List[str]] = []
            for row in sheet_data.findall(_MAIN + "row"):
                cells: Dict[int, str] = {}
                for c in row.findall(_MAIN + "c"):
                    ref = c.get("r") or ""
                    idx = _column_index(ref) if ref else len(cells)
                    ctype = c.get("t")
                    v = c.find(_MAIN + "v")
                    inline = c.find(_MAIN + "is")

                    if ctype == "s" and v is not None:
                        try:
                            value = strings[int(v.text)]
                        except (ValueError, IndexError):
                            value = ""
                    elif ctype == "inlineStr" and inline is not None:
                        value = "".join(t.text or "" for t in inline.iter(_MAIN + "t"))
                    elif v is not None:
                        value = v.text or ""
                    else:
                        value = ""

                    cells[idx] = value.strip()

                if cells:
                    width = max(cells) + 1
                    rows.append([cells.get(i, "") for i in range(width)])
                else:
                    rows.append([])

            book[sheet_name] = rows

    return book
