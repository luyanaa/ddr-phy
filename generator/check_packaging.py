#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate packaging profiles, fixtures and the packaged-closure artifacts.

Generic: iterates every *.yaml profile in specs/pads/packaging_profiles/,
so adding a package or a PDK needs no code change. Guard rails:
  - no invented numbers: every override must trace to a cited source
  - generic pdk_rules PAD_PITCH/PAD_OPENING must STAY TBD (profile = overlay)
  - synthetic fixtures must declare their status
  - closure artifacts, if present, must not claim drc_clean/signoff.
"""
import json
import sys
from pathlib import Path

import yaml

import solve_layout as sl
import solve_packaged as sp

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs" / "pads"
OUT = ROOT / "sch" / "pads"


def main():
    e = []
    topo, cons = sl.load()
    rules = {r["id"]: r for r in cons["pdk_rules"]}

    # The generic model must NOT be frozen to one package.
    for k in ("PAD_PITCH", "PAD_OPENING"):
        if rules[k]["status"] != "TBD" or rules[k]["value"] is not None:
            e.append("generic pdk_rules %s must stay TBD (profile is an overlay)" % k)

    profiles = [p for p in sp.all_profiles() if not p.stem.endswith(".fixture")]
    if not profiles:
        e.append("no packaging profiles found")
    for p in profiles:
        d = yaml.safe_load(p.read_text())
        sp.validate_profile(d, cons["pdk_rules"], e)
        meta = d["meta"]
        # every override must have a source section
        if d.get("overrides") and not d.get("sources"):
            e.append("%s: overrides without sources" % p.name)
        # evidence class assembly_measured should cite a golden mask with sha256
        if meta.get("evidence_class") == "assembly_measured":
            gm = d.get("sources", {}).get("golden_mask", {})
            if not (isinstance(gm, dict) and gm.get("sha256")):
                e.append("%s: assembly_measured needs golden_mask sha256" % p.name)
        # fixtures
        fx = p.with_name(p.stem + ".fixture.yaml")
        if fx.exists():
            f = yaml.safe_load(fx.read_text())
            if f.get("meta", {}).get("status") != "synthetic_fixture":
                e.append("%s: fixture not labelled synthetic" % fx.name)
            bad = [k for k in f.get("values", {}) if k not in rules and
                   k not in {t["id"] for t in topo["params"]}]
            if bad:
                e.append("%s: unknown fixture keys %s" % (fx.name, bad))
        # closure artifacts must stay honest
        pid = meta.get("profile_id")
        backend = (meta.get("applies_to_backend") or ["?"])[0]
        art = OUT / backend / "layout" / "profiles" / str(pid) / "closure_constraints.json"
        if art.exists():
            c = json.load(open(art))
            if c.get("drc_clean") is not False or c.get("signoff") is not False:
                e.append("%s: closure artifact claims drc_clean/signoff" % pid)
            if c.get("note") != "profile overrides are in-memory only; generic pdk_rules unchanged":
                e.append("%s: closure artifact missing overlay note" % pid)

    if e:
        for x in e:
            print("ERROR " + x, file=sys.stderr)
        return 1
    print("packaging checks PASS: %d profiles, %d fixtures, generic PAD_* still TBD" %
          (len(profiles), sum(1 for p in profiles if p.with_name(p.stem + ".fixture.yaml").exists())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
