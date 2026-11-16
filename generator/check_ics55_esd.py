#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Guard the ics55 3.3 V ESD prototype: STUDY_ONLY, no sizes, no signoff."""
import json
import re
import sys
from pathlib import Path

import yaml

import emit_pads as ep

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs" / "pads"
OUT = ROOT / "sch" / "pads" / "ics55"
REPORTS = ROOT / "reports"


def main():
    errors = []
    spec = yaml.safe_load(open(SPECS / "ics55_esd_3v3.yaml"))
    maps = {d["backend"]: d for d in
            (yaml.safe_load(open(p)) for p in (SPECS / "devices").glob("*.yaml"))}
    topo, maps2 = ep.load()
    ics = maps["ics55"]

    if spec["meta"]["status"] != "STUDY_ONLY":
        errors.append("ics55 ESD spec status must stay STUDY_ONLY")
    if ics.get("custom_esd", {}).get("status") != "STUDY_ONLY":
        errors.append("ics55 map custom_esd must stay STUDY_ONLY")
    if ep.bound(ics, topo):
        errors.append("ics55 pad map must stay unbound")
    for p in spec["params"]:
        if p["value"] is not None or p["status"] != "TBD":
            errors.append("ics55 ESD param %s must stay null/TBD" % p["id"])
    if spec["devices"].get("nmos") != ics["slots"]["NMOS_IO"]["device"]:
        errors.append("ics55 ESD NMOS does not match the map")
    if spec["devices"].get("pmos") != ics["slots"]["PMOS_IO"]["device"]:
        errors.append("ics55 ESD PMOS does not match the map")

    f = OUT / "esd_ggnmos_3v3.spice"
    if not f.exists():
        errors.append("missing generated esd_ggnmos_3v3.spice")
    else:
        s = f.read_text()
        for marker in ("STUDY_ONLY", "NOT SIMULATABLE", "NOT A QUALIFIED ESD CELL"):
            if marker not in s:
                errors.append("generated ESD netlist missing %r" % marker)
        if "@@" in s:
            errors.append("generated ESD netlist has unresolved tokens")
        if re.search(r"\bw\s*=\s*[0-9]", s) or re.search(r"\bl\s*=\s*[0-9]", s):
            errors.append("generated ESD netlist has a numeric W/L")
        if "dio_2p5" in s or "dio_3p3" in s:
            errors.append("generated ESD netlist uses a diode model")
    mf = OUT / "esd_ggnmos_3v3_manifest.json"
    if mf.exists():
        m = json.load(open(mf))
        if m.get("signoff") or m.get("simulatable") or m.get("status") != "STUDY_ONLY":
            errors.append("ESD manifest claims signoff/simulatable or wrong status")
    else:
        errors.append("missing ESD manifest")
    if not (REPORTS / "ics55_esd_3v3.md").exists():
        errors.append("missing ics55 ESD report")

    if errors:
        for e in errors:
            print("ERROR " + e, file=sys.stderr)
        return 1
    print("ics55 ESD checks PASS: STUDY_ONLY, %d params null, no signoff" %
          len(spec["params"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
