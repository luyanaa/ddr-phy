#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the ngspice device-extraction report and generated spec block.

Guard rails: no fabricated/mock values, every measured datum traceable to a
hashed ngspice deck, BLOCKED backends carry a real simulator error, and the
10 pdk_rules in constraints.yaml stay TBD (a device probe cannot determine
DRC/ESD/EM rules).
"""
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
REPORT = ROOT / "reports" / "device_extraction.json"
CONSTRAINTS = ROOT / "specs" / "pads" / "constraints.yaml"
BACKENDS = ROOT / "specs" / "pads" / "device_backends.yaml"


def main():
    e = []
    if not REPORT.exists():
        print("ERROR missing reports/device_extraction.json", file=sys.stderr)
        return 1
    d = json.load(open(REPORT))
    if d.get("status") != "no_signoff_claim":
        e.append("report status is not no_signoff_claim")
    # Look for an actual mock/fabricated DATA field, not the word "mock" in
    # the method description (which says "no mock fallback").
    def walk(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k.lower() in ("simulator_mode", "source", "status", "value_source") and \
                   isinstance(v, str) and v.lower() in ("mock", "mock_calibrated", "lut", "calibrated_lut"):
                    e.append("report contains a mock/fabricated source: " + v)
                walk(v)
        elif isinstance(obj, list):
            for v in obj:
                walk(v)
    walk(d)

    cfg = yaml.safe_load(open(BACKENDS))["backends"]
    cons = yaml.safe_load(open(CONSTRAINTS))
    for name, r in d["backends"].items():
        if name not in cfg:
            e.append("unknown backend in report: " + name)
            continue
        st = r["status"]
        if st not in ("MEASURED", "BLOCKED", "PROBE_ONLY"):
            e.append("%s: bad status %s" % (name, st))
        # All three configured PDKs are now measurable locally. A regression
        # back to BLOCKED (wrong PDK version, broken include, missing models)
        # must fail the check rather than be silently accepted.
        if st != "MEASURED":
            e.append("%s: expected MEASURED, got %s (sky130 regression)" % (name, st))
        if st == "BLOCKED":
            errs = [x.get("error", "") for grp in ("triode_tt", "triode_ss", "triode_ff")
                    for x in r.get(grp, {}).values()]
            if not any("error" in q.lower() or "could not" in q.lower() or
                       "no such" in q.lower() for q in errs):
                e.append("%s: BLOCKED without a real ngspice error" % name)
        if st == "MEASURED":
            for tag in ("tt", "ss", "ff"):
                grp = r.get("triode_" + tag, {})
                for dev in ("NMOS", "PMOS"):
                    x = grp.get(dev, {})
                    if x.get("status") != "measured":
                        e.append("%s/%s/%s: not measured" % (name, tag, dev))
                    if x.get("source") != "ngspice" or not x.get("deck_sha256"):
                        e.append("%s/%s/%s: missing source/deck hash" % (name, tag, dev))
                    if x.get("Id_mA", 0) <= 0:
                        e.append("%s/%s/%s: non-positive Id" % (name, tag, dev))
            # corner ordering sanity: SS <= TT <= FF for the same device
            for dev in ("NMOS", "PMOS"):
                a = r["triode_ss"][dev]["Id_mA"]
                b = r["triode_tt"][dev]["Id_mA"]
                c = r["triode_ff"][dev]["Id_mA"]
                if not (a <= b <= c):
                    e.append("%s/%s: SS/TT/FF Id ordering violated (%s/%s/%s)" %
                             (name, dev, a, b, c))
            for dev in ("NMOS", "PMOS"):
                for key in ("sat_dc", "ac_caps"):
                    x = r[key][dev]
                    if x.get("status") != "measured" or x.get("source") != "ngspice":
                        e.append("%s/%s/%s: not a traced measurement" % (name, key, dev))
                cal = r["tx_calibration"][dev]
                if cal.get("status") == "measured":
                    if cal["Id_verified_mA"] < cal["target_mA"]:
                        e.append("%s/%s: calibration below target" % (name, dev))
                    for step in cal["calibration_log"]:
                        if not step.get("deck_sha256"):
                            e.append("%s/%s: calibration step lacks deck hash" % (name, dev))
            ic = r["rx_icmr"]
            if ic.get("status") != "measured" or "proxy" not in ic.get("note", ""):
                e.append("%s: ICMR must be labelled a headroom proxy" % name)

    rules = cons.get("pdk_rules", [])
    ev_path = ROOT / "specs" / "pads" / "pdk_rule_evidence.yaml"
    ev = {r["id"]: r for r in yaml.safe_load(open(ev_path))["rules"]} if ev_path.exists() else {}
    if len(rules) != 10:
        e.append("pdk_rules must have 10 entries")
    for x in rules:
        v = ev.get(x["id"], {})
        if v.get("verdict") == "verified":
            if x["status"] != "verified" or x["value"] is None or not x.get("verified_from"):
                e.append("verified pdk_rule %s lacks provenance" % x["id"])
        elif x["status"] != "TBD" or x["value"] is not None:
            e.append("pdk_rule %s must stay TBD/null" % x["id"])
    dm = cons.get("device_measurements", {})
    if dm.get("status") != "no_signoff_claim":
        e.append("constraints device_measurements missing no_signoff_claim")
    if set(dm.get("backends", {})) != set(d["backends"]):
        e.append("constraints device_measurements backend set mismatch")

    if e:
        for x in e:
            print("ERROR " + x, file=sys.stderr)
        return 1
    meas = [k for k, v in d["backends"].items() if v["status"] == "MEASURED"]
    nfill = sum(1 for x in cons["pdk_rules"] if x["status"] == "verified")
    print("device extraction checks PASS: %d measured, 0 blocked, %d pdk_rules verified/%d TBD, 0 mock values" %
          (len(meas), nfill, len(cons["pdk_rules"]) - nfill))
    return 0


if __name__ == "__main__":
    sys.exit(main())
