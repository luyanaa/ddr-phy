#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the composite-constraint layout solver and its artifacts.

Guard rails: no invented sizes or PDK rules, no leftover template tokens,
no DRC-clean claim, symbolic mode by default, and the gf180mcu DDR1
long-term deferral must stay in place.
"""
import json
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs" / "pads"
LAY = ROOT / "sch" / "pads" / "gf180mcuD" / "layout"

ALLOWED = {"satisfied", "violated", "unresolved", "structural"}


def main():
    e = []
    topo = yaml.safe_load(open(SPECS / "topology.yaml"))
    cons = yaml.safe_load(open(SPECS / "constraints.yaml"))
    dev = yaml.safe_load(open(SPECS / "devices" / "gf180mcuD.yaml"))

    for p in topo["params"]:
        if p["value"] is not None:
            e.append("design param %s invented value" % p["id"])
    for p in cons["pdk_rules"]:
        if p["value"] is not None or p["status"] != "TBD":
            e.append("PDK rule %s invented or not TBD" % p["id"])
    if dev["ddr1"]["status"] != "DEFERRED_LONG_TERM":
        e.append("gf180mcuD DDR1 is not DEFERRED_LONG_TERM")

    lc = json.load(open(LAY / "layout_constraints.json"))
    if lc["drc_clean"] is not False:
        e.append("layout_constraints claims drc_clean")
    if lc["mode"] != "symbolic":
        e.append("default mode must be symbolic")
    if lc["unresolved_param_count"] != len(topo["params"]) + len(cons["pdk_rules"]):
        e.append("unresolved count mismatch")
    for c in lc["constraints"]:
        if c["status"] not in ALLOWED:
            e.append("bad constraint status %s" % c["status"])
        if c["status"] == "violated" and "unresolved_operands" in c:
            e.append("violated with unresolved operands")
        if c["check"] != "structural" and not c.get("upstream"):
            e.append("constraint %s has no composite upstream" % c["id"])
    if not {"geometry", "esd", "latch_up", "power_em", "matching", "pad_ring", "drc"}.issubset(
            {c["class"] for c in lc["constraints"]}):
        e.append("composite classes incomplete")

    pl = json.load(open(LAY / "placement.json"))
    if pl["drc_clean"] is not False or "NOT DRC CLEAN" not in pl["labels"]:
        e.append("placement lacks NOT DRC CLEAN marker")
    if any(x["bbox_um"] is not None for x in pl["instances"]):
        e.append("symbolic placement has dimensional boxes")

    for f in LAY.glob("*.py"):
        if "@@" in f.read_text():
            e.append("leftover token in " + str(f))
    gds = LAY / "sdr_bidir_pad_topology.gds"
    if not gds.exists() or gds.stat().st_size < 100:
        e.append("symbolic GDS missing or empty")

    rep = (ROOT / "reports" / "layout_solver_report.md").read_text()
    if "NOT DRC CLEAN" not in rep:
        e.append("report lacks NOT DRC CLEAN")

    if e:
        for x in e:
            print("ERROR " + x, file=sys.stderr)
        return 1
    print("layout checks PASS: %d params unresolved, %d composite constraints, %d classes, 0 DRC claims" %
          (lc["unresolved_param_count"], len(lc["constraints"]),
           len({c["class"] for c in lc["constraints"]})))
    return 0


if __name__ == "__main__":
    sys.exit(main())
