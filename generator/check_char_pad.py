#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate pad sizing fixtures and first-pass characterization reports.

Guards:
  - every fixture is explicitly labelled design_assumption
  - every topology parameter appears exactly once, with a known unit
  - the char metadata is present and positive
  - reports still carry the no-signoff marker and all required measures
"""
import glob
import json
import re
import sys
from pathlib import Path

import yaml

import emit_pads as ep
import emit_char_pad as ecp

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs" / "pads"
REPORTS = ROOT / "reports"
UNITS = {"um", "m", "m2", "A", "V", "count"}


def main():
    errors = []
    topo, maps = ep.load()
    ids = [p["id"] for p in topo["params"]]

    for f in sorted((SPECS / "sizing").glob("*.first_pass.yaml")):
        d = yaml.safe_load(open(f))
        meta = d.get("meta", {})
        if meta.get("status") != "design_assumption":
            errors.append("%s: status must be design_assumption" % f.name)
        backend = meta.get("backend")
        if backend not in maps:
            errors.append("%s: unknown backend %r" % (f.name, backend))
            continue
        if not ep.bound(maps[backend], topo):
            errors.append("%s: backend map is not bound" % f.name)
        seen = {}
        for p in d.get("params", []):
            pid = p.get("id")
            if pid in seen:
                errors.append("%s: duplicate param %s" % (f.name, pid))
            seen[pid] = p
            if p.get("unit") not in UNITS:
                errors.append("%s: %s has unknown unit %r" % (f.name, pid, p.get("unit")))
            try:
                float(p.get("value"))
            except (TypeError, ValueError):
                errors.append("%s: %s has non-numeric value %r" % (f.name, pid, p.get("value")))
        if set(seen) != set(ids):
            errors.append("%s: missing=%s extra=%s" % (
                f.name, sorted(set(ids) - set(seen)), sorted(set(seen) - set(ids))))
        ch = meta.get("char", {})
        for k in ("series_r_ohm", "vdd_v", "vddio_v"):
            try:
                if float(ch.get(k)) <= 0:
                    errors.append("%s: meta.char.%s must be positive" % (f.name, k))
            except (TypeError, ValueError):
                errors.append("%s: meta.char.%s missing/non-numeric" % (f.name, k))

    for f in sorted(glob.glob(str(REPORTS / "pad_char_*.json"))):
        d = json.load(open(f))
        dom = d.get("control_domains", {})
        for k, want in (("OUT", "core"), ("OE_N", "io"), ("PU_OK", "io"), ("PAD", "io")):
            if dom.get(k) != want:
                errors.append("%s: control_domains.%s must be %s" % (f, k, want))
        # If the generated deck exists, verify the actual source levels.
        backend = d.get("backend")
        stem = Path(f).stem
        prefix = "pad_char_" + str(backend)
        tag = stem[len(prefix):] if stem.startswith(prefix) else ""
        deck = ROOT / "sim" / "char" / str(backend) / ("char_tran%s.spice" % tag)
        if deck.exists():
            vdd = float(d.get("vdd_v", 0))
            vddio = float(d.get("vddio_v", 0))
            txt = deck.read_text()
            def first_pwl(src):
                m = re.search(r"^%s\s+\S+\s+0\s+PWL\(([^)]*)\)" % src, txt, re.M)
                if not m:
                    return None
                def num(x):
                    mult = 1.0
                    if x.endswith("n"):
                        x, mult = x[:-1], 1e-9
                    elif x.endswith("u"):
                        x, mult = x[:-1], 1e-6
                    return float(x) * mult
                nums = [num(x) for x in m.group(1).split()]
                return max(nums) if nums else None
            for src, want in (("VOE", vddio), ("VPU", vddio), ("VOUT", vdd)):
                got = first_pwl(src)
                if got is None:
                    errors.append("%s: cannot read %s PWL level" % (deck, src))
                elif abs(got - want) > 1e-9:
                    errors.append("%s: %s high level %g != %g" % (deck, src, got, want))
        status = str(d.get("status", ""))
        if "design_assumption" not in status or "no signoff" not in status.lower():
            errors.append("%s: report lost the design_assumption/no-signoff status" % f)
        ms = d.get("measures", {})
        missing = [m for m in ecp.MEASURES if m not in ms]
        if missing:
            errors.append("%s: missing measures %s" % (f, missing))
        for m in ecp.MEASURES:
            if m in ms and not isinstance(ms[m], (int, float)):
                errors.append("%s: measure %s is not numeric" % (f, m))

    for f in sorted(glob.glob(str(REPORTS / "pad_char_*.md"))):
        s = open(f).read()
        low = s.lower()
        if "not signoff" not in low or "design_assumption" not in low:
            errors.append("%s: markdown lost the no-signoff marker" % f)

    if errors:
        for e in errors:
            print("ERROR " + e, file=sys.stderr)
        return 1
    print("char-pad checks PASS: %d fixtures, %d reports, no signoff claims" %
          (len(list((SPECS / "sizing").glob("*.first_pass.yaml"))),
           len(glob.glob(str(REPORTS / "pad_char_*.json")))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
