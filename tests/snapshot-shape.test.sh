#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/bolt-helper"

json="$("$HELPER" snapshot)"
python3 - "$json" <<'PY'
import json, sys

data = json.loads(sys.argv[1])
assert data.get("ok") is True, data
assert data.get("boltAvailable") is True, data
assert isinstance(data.get("devices"), list), data
assert isinstance(data.get("domains"), list), data
assert "manager" in data
assert "authMode" in data["manager"]
assert "securityLevel" in data

for device in data["devices"]:
    for key in ("uid", "label", "type", "status", "stored", "authorized", "connected"):
        assert key in device, (key, device)

print("snapshot-shape: ok (%d devices, domainPresent=%s)" % (
    len(data["devices"]), data.get("domainPresent")))
PY
