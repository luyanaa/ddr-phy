#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the pad topology/device maps and all generated artifacts.

Guard rails: no invented sizes, no leftover template tokens, no signoff
claim, and the gf180mcu DDR1 exclusion must stay explicit.
"""
import glob
import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs" / "pads"
OUT = ROOT / "sch" / "pads"


def main():
    errors = []
    topo = yaml.safe_load(open(SPECS / "topology.yaml"))
    for p in topo["params"]:
        if p["value"] is not None:
            errors.append("param %s has a concrete value %r" % (p["id"], p["value"]))
        if p["status"] != "TBD":
            errors.append("param %s status is %s" % (p["id"], p["status"]))

    maps = {}
    for p in sorted((SPECS / "devices").glob("*.yaml")):
        d = yaml.safe_load(open(p))
        maps[d["backend"]] = d
        if d["decision"] == "GO":
            errors.append("%s claims GO" % d["backend"])
        for s in topo["slots"]:
            if s["id"] not in d["slots"]:
                errors.append("%s missing slot %s" % (d["backend"], s["id"]))

    g = maps.get("gf180mcuD")
    if not g or g["ddr1"]["status"] != "DEFERRED_LONG_TERM":
        errors.append("gf180mcuD DDR1 must stay DEFERRED_LONG_TERM (long-term plan)")
    if g and g["ddr1"]["status"] == "SUPPORTED":
        errors.append("gf180mcuD DDR1 must not be claimed SUPPORTED")
    if g and ("nfet_06v0" not in str(g.get("forbidden", ""))):
        errors.append("gf180mcuD must forbid 6 V devices")

    for f in sorted(glob.glob(str(OUT / "**" / "*.spice"), recursive=True)):
        s = open(f).read()
        if "@@" in s:
            errors.append("leftover template token in " + f)
        if re.search(r"\bw\s*=\s*\d", s) or re.search(r"\bl\s*=\s*\d", s):
            errors.append("hard-coded W/L numeric in " + f)
        if "NOT SIMULATABLE" not in s and "NOT RUNNABLE" not in s:
            errors.append("missing NOT SIMULATABLE marker in " + f)
    for f in sorted(glob.glob(str(OUT / "**" / "*.sch"), recursive=True)):
        if "@@" in open(f).read():
            errors.append("leftover template token in " + f)
    for f in sorted(glob.glob(str(OUT / "**" / "manifest.json"), recursive=True)):
        m = json.load(open(f))
        if m["simulatable"] or m["signoff"]:
            errors.append("manifest claims simulatable/signoff: " + f)

    if errors:
        for e in errors:
            print("ERROR " + e, file=sys.stderr)
        return 1
    print("pad checks PASS: %d params unresolved, %d backends, 0 signoff claims" %
          (len(topo["params"]), len(maps)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
