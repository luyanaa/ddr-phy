#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the pad topology/device maps and all generated artifacts.

Guard rails: no invented sizes, no leftover template tokens, no signoff
claim, no unverified device name in emitted SPICE, and the gf180mcu
DDR1 exclusion must stay explicit.
"""
import glob
import json
import re
import sys
from pathlib import Path

import yaml

import emit_pads as ep

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs" / "pads"
OUT = ROOT / "sch" / "pads"

SPICE_KEYS = ("mos_format", "res_format", "diode_format",
              "finger_param", "mult_param")


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

        is_bound = ep.bound(d, topo)
        if is_bound:
            for k in SPICE_KEYS:
                if not d.get("spice", {}).get(k):
                    errors.append("%s is bound but spice.%s missing" % (d["backend"], k))
            for s in topo["slots"]:
                sid = s["id"]
                if sid in ep.COMPOSITE_SLOTS:
                    continue
                if sid in ep.CONDITIONAL_SLOTS and not ep.conditions_for(d)["LEVEL_SHIFTER"]:
                    continue
                slot = d["slots"].get(sid, {})
                if not slot.get("device"):
                    errors.append("%s bound but slot %s has no device" % (d["backend"], sid))
                elif not slot.get("verified"):
                    errors.append("%s bound but slot %s is not verified" % (d["backend"], sid))
            # The emitted SPICE must use the map's declared syntax, not
            # another backend's. This catches a template regression even
            # before an ngspice run.
            gen = OUT / d["backend"] / "sdr_bidir_pad.spice"
            if not gen.exists():
                errors.append("%s is bound but sdr_bidir_pad.spice is missing" % d["backend"])
            else:
                body = gen.read_text()
                sp = d["spice"]
                for key in ("finger_param", "mult_param"):
                    if ("%s=" % sp[key]) not in body:
                        errors.append("%s SPICE does not use %s=%s" %
                                      (d["backend"], key, sp[key]))
                prefix = sp["diode_format"].lstrip()[:1]
                if ("%s_ESD_UP" % prefix) not in body:
                    errors.append("%s SPICE diode prefix != %s" % (d["backend"], prefix))
        else:
            if not d.get("blocker"):
                errors.append("%s is unbound but has no blocker note" % d["backend"])

    g = maps.get("gf180mcuD")
    if not g or g["ddr1"]["status"] != "DEFERRED_LONG_TERM":
        errors.append("gf180mcuD DDR1 must stay DEFERRED_LONG_TERM (long-term plan)")
    if g and g["ddr1"]["status"] == "SUPPORTED":
        errors.append("gf180mcuD DDR1 must not be claimed SUPPORTED")
    if g and ("nfet_06v0" not in str(g.get("forbidden", ""))):
        errors.append("gf180mcuD must forbid 6 V devices")

    # ics55 must stay unbound until a 3.3 V ESD diode card exists.
    i = maps.get("ics55")
    if i:
        if ep.bound(i, topo):
            errors.append("ics55 must stay unbound (3.3 V ESD diode card missing)")
        if not i.get("blocker") or "3.3 V" not in i["blocker"]:
            errors.append("ics55 must record the 3.3 V ESD diode blocker")
        if i.get("custom_esd", {}).get("status") != "STUDY_ONLY":
            errors.append("ics55 custom_esd must stay STUDY_ONLY")

    for f in sorted(glob.glob(str(OUT / "**" / "*.spice"), recursive=True)):
        s = open(f).read()
        if "@@" in s:
            errors.append("leftover template token in " + f)
        if "UNBOUND_" in s:
            errors.append("unbound device placeholder in " + f)
        if re.search(r"\bw\s*=\s*\d", s) or re.search(r"\bl\s*=\s*\d", s):
            errors.append("hard-coded W/L numeric in " + f)
        if "NOT SIMULATABLE" not in s and "NOT RUNNABLE" not in s:
            errors.append("missing NOT SIMULATABLE marker in " + f)
        if "D_CLAMP VDDIO VSSIO" in s:
            errors.append("clamp diode is forward-biased in " + f)
        if "D_CLAMP" in s and "D_CLAMP VSSIO VDDIO" not in s:
            errors.append("2-terminal clamp must be VSSIO->VDDIO in " + f)
        if "X_CLAMP" in s and "X_CLAMP VDDIO VSSIO VSSIO" not in s:
            errors.append("3-terminal clamp node order is wrong in " + f)
    for f in sorted(glob.glob(str(OUT / "**" / "*.sch"), recursive=True)):
        if "@@" in open(f).read():
            errors.append("leftover template token in " + f)
    for f in sorted(glob.glob(str(OUT / "**" / "manifest.json"), recursive=True)):
        m = json.load(open(f))
        if m["simulatable"] or m["signoff"]:
            errors.append("manifest claims simulatable/signoff: " + f)
        d = maps.get(m["backend"])
        if d is not None and bool(m.get("device_map_bound")) != ep.bound(d, topo):
            errors.append("manifest device_map_bound mismatch: " + f)

    if errors:
        for e in errors:
            print("ERROR " + e, file=sys.stderr)
        return 1
    bound = sum(1 for d in maps.values() if ep.bound(d, topo))
    print("pad checks PASS: %d params unresolved, %d backends (%d bound), 0 signoff claims" %
          (len(topo["params"]), len(maps), bound))
    return 0


if __name__ == "__main__":
    sys.exit(main())
