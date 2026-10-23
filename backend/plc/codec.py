"""
Big-endian S7 encode/decode against a cached DB byte buffer.

Deliberately implemented with ``struct`` rather than ``snap7.util`` so the
decoder can be unit-tested and run in simulation mode without python-snap7
installed. The wire format is identical: S7 is big-endian, Int is a signed
16-bit word, Real is an IEEE-754 32-bit float, and Bool bit 0 is the LSB of
its byte.
"""

from __future__ import annotations

import struct
from typing import Any, Optional


class DecodeError(Exception):
    pass


def decode(buf: bytes, byte: int, bit: int, dtype: str) -> Any:
    """Read one value out of a cached DB buffer. Raises DecodeError on overrun."""
    try:
        if dtype == "Bool":
            return bool((buf[byte] >> bit) & 0x01)
        if dtype == "Int":
            return struct.unpack_from(">h", buf, byte)[0]
        if dtype == "Word":
            return struct.unpack_from(">H", buf, byte)[0]
        if dtype == "DInt":
            return struct.unpack_from(">i", buf, byte)[0]
        if dtype == "Real":
            value = struct.unpack_from(">f", buf, byte)[0]
            # A PLC Real that has never been written reads as NaN/Inf. Passing
            # that to json.dumps produces invalid JSON that silently breaks the
            # browser's JSON.parse, so it is normalised to None here instead.
            if value != value or value in (float("inf"), float("-inf")):
                return None
            return round(value, 4)
    except (IndexError, struct.error) as exc:
        raise DecodeError(
            "cannot read %s at byte %d (buffer is %d bytes)" % (dtype, byte, len(buf))
        ) from exc

    raise DecodeError("unsupported data type %r" % dtype)


def encode(value: Any, dtype: str) -> bytearray:
    """Encode a scalar into its S7 wire bytes. Bool is handled by the writer."""
    if dtype == "Int":
        v = int(value)
        if not -32768 <= v <= 32767:
            raise ValueError("Int out of S7 range (-32768..32767): %d" % v)
        return bytearray(struct.pack(">h", v))
    if dtype == "Word":
        v = int(value)
        if not 0 <= v <= 65535:
            raise ValueError("Word out of S7 range (0..65535): %d" % v)
        return bytearray(struct.pack(">H", v))
    if dtype == "DInt":
        v = int(value)
        if not -2147483648 <= v <= 2147483647:
            raise ValueError("DInt out of S7 range: %d" % v)
        return bytearray(struct.pack(">i", v))
    if dtype == "Real":
        v = float(value)
        if v != v or v in (float("inf"), float("-inf")):
            raise ValueError("Real must be finite")
        return bytearray(struct.pack(">f", v))

    raise ValueError("encode() does not handle %r (Bool uses set_bit)" % dtype)


def set_bit(byte_value: int, bit: int, value: bool) -> int:
    """Return ``byte_value`` with a single bit forced high or low."""
    mask = 1 << bit
    return (byte_value | mask) if value else (byte_value & ~mask & 0xFF)


def coerce(value: Any, dtype: str) -> Any:
    """
    Coerce a JSON-decoded value to the tag's Python type, rejecting anything
    ambiguous. HTTP bodies arrive as strings often enough that silently
    accepting ``"false"`` as truthy would be a genuine safety hazard.
    """
    if dtype == "Bool":
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)) and value in (0, 1):
            return bool(value)
        if isinstance(value, str):
            low = value.strip().lower()
            if low in ("true", "1", "on", "yes"):
                return True
            if low in ("false", "0", "off", "no"):
                return False
        raise ValueError("cannot interpret %r as a Bool" % (value,))

    if dtype in ("Int", "Word", "DInt"):
        if isinstance(value, bool):
            raise ValueError("refusing to write a Bool into an %s tag" % dtype)
        try:
            return int(value)
        except (TypeError, ValueError):
            raise ValueError("cannot interpret %r as an %s" % (value, dtype))

    if dtype == "Real":
        if isinstance(value, bool):
            raise ValueError("refusing to write a Bool into a Real tag")
        try:
            return float(value)
        except (TypeError, ValueError):
            raise ValueError("cannot interpret %r as a Real" % (value,))

    raise ValueError("unsupported data type %r" % dtype)


def value_equal(a: Any, b: Any, dtype: str) -> bool:
    """
    Compare a requested value against a PLC readback.

    Real needs a tolerance: the float that comes back out of the PLC is not
    guaranteed to be bit-identical to the one written, and comparing with ==
    would leave every Real write stuck in the 'pending' state forever.
    """
    if a is None or b is None:
        return a is b
    if dtype == "Real":
        return abs(float(a) - float(b)) <= 1e-3
    if dtype == "Bool":
        return bool(a) is bool(b)
    return int(a) == int(b)


def optional_round(value: Optional[float], digits: int = 3) -> Optional[float]:
    return None if value is None else round(value, digits)
