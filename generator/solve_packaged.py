#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Profile-driven packaged-pad closure solver (PDK-agnostic).

A packaging profile is a PLUGGABLE overlay that supplies assembly-specific
geometry the generic pdk_rules deliberately leave TBD. This solver contains
NO hard-coded PDK or assembly house: the backend, the overrides, the
assumptions and the evidence class all come from the profile file under
specs/pads/packaging_profiles/. Adding a package (or sky130 / ihp130 /
ics55) means adding ONE yaml, zero code changes.

Crucially this does NOT write into constraints.yaml: the generic model keeps
PAD_PITCH/PAD_OPENING as TBD so that one MPW run's commitment is never
mistaken for a universal rule. The profile values are overlaid only in the
solver's in-memory namespace and are recorded, with provenance, in the
generated closure report.

Usage:
  python3 generator/solve_packaged.py --profile wafer_space_gf180_1x1
  python3 generator/solve_packaged.py --profile NAME --design-fixture FILE
  python3 generator/solve_packaged.py --check-profiles
"""
import argparse
import json
import tempfile
import sys
from pathlib import Path

import yaml

import solve_layout as sl

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "specs" / "pads"
PROFILES = SPECS / "packaging_profiles"
REPORTS = ROOT / "reports"
OUT = ROOT / "sch" / "pads"
VALID_EVIDENCE = {"assembly_measured", "foundry_doc", "datasheet", "design_assumption"}


def all_profiles():
    return sorted(PROFILES.glob("*.yaml"))


def load_profile(name):
    p = PROFILES / (name + ".yaml")
    if not p.exists():
        return None
    return yaml.safe_load(p.read_text())


def validate_profile(d, rules, errors):
    """Structure + internal consistency. Generic - no PDK-specific logic."""
    meta = d.get("meta", {})
    for k in ("profile_id", "applies_to_backend", "status", "evidence_class", "license"):
        if not meta.get(k):
            errors.append("meta.%s missing" % k)
    if meta.get("evidence_class") not in VALID_EVIDENCE:
        errors.append("meta.evidence_class invalid: %s" % meta.get("evidence_class"))
    if not isinstance(meta.get("applies_to_backend"), list) or not meta["applies_to_backend"]:
        errors.append("meta.applies_to_backend must be a non-empty list")

    rule_ids = {r["id"] for r in rules}
    g = d.get("geometry", {})
    ov = d.get("overrides", {})
    for k in ov:
        if k not in rule_ids:
            errors.append("override %s is not a pdk_rules id" % k)
    for a in d.get("assumptions", []):
        if a.get("id") not in rule_ids:
            errors.append("assumption %s is not a pdk_rules id" % a.get("id"))

    # Internal pitch consistency (generic arithmetic, not GF-specific).
    if all(x in g for x in ("pitch_ns_um", "pitch_ew_um", "pitch_min_um")):
        if g["pitch_min_um"] != min(g["pitch_ns_um"], g["pitch_ew_um"]):
            errors.append("pitch_min_um != min(ns, ew)")
    for key in ("pitch_ns_um", "pitch_ew_um", "pitch_min_um", "pad_opening_um"):
        if key in g and (not isinstance(g[key], (int, float)) or g[key] <= 0):
            errors.append("geometry.%s must be positive number" % key)
    if "PAD_OPENING" in ov and "pad_opening_um" in g and ov["PAD_OPENING"] != g["pad_opening_um"]:
        errors.append("override PAD_OPENING disagrees with geometry.pad_opening_um")
    if "PAD_PITCH" in ov and "pitch_min_um" in g and ov["PAD_PITCH"] != g["pitch_min_um"]:
        errors.append("override PAD_PITCH disagrees with geometry.pitch_min_um")
    if "sources" not in d or not d["sources"]:
        errors.append("profile must cite sources")

    # pad_count_internal consistency when present
    pc = [g.get(x) for x in ("pad_count_south", "pad_count_north", "pad_count_east", "pad_count_west")]
    if all(isinstance(x, int) for x in pc) and isinstance(g.get("pad_count_total"), int):
        if sum(pc) != g["pad_count_total"]:
            errors.append("pad_count_total != sum of four edges")


def build_namespace(topo, cons, profile, fixture):
    """Generic overlay: values_for + overrides + assumptions. Nothing writes
    back to constraints.yaml."""
    v = sl.values_for(topo, cons, fixture)
    asm_values = {}
    for key, val in profile.get("overrides", {}).items():
        if key not in v:
            raise KeyError("override key not in namespace: " + key)
        v[key] = val
    for a in profile.get("assumptions", []):
        if a["id"] not in v:
            raise KeyError("assumption key not in namespace: " + a["id"])
        v[a["id"]] = a["value"]
        asm_values[a["id"]] = a
    return v, asm_values


def source_map(cons, profile):
    """Where did each input value come from? Drives honest annotation."""
    m = {}
    for r in cons["pdk_rules"]:
        if r["status"] == "verified":
            m[r["id"]] = "verified:" + str(r.get("verified_from", ""))
        elif r["status"] == "foundry_doc":
            m[r["id"]] = "foundry_doc:" + str(r.get("foundry_from", ""))
        else:
            m[r["id"]] = "TBD"
    for k in profile.get("overrides", {}):
        m[k] = "profile_override(%s):%s" % (profile["meta"]["evidence_class"],
                                            profile["meta"]["profile_id"])
    for a in profile.get("assumptions", []):
        m[a["id"]] = "design_assumption:%s" % a["id"]
    return m


def annotate(results, cons, smap):
    for r in results:
        if r["check"] == "structural":
            r["operand_sources"] = {}
            continue
        r["operand_sources"] = {
            "lhs": smap.get(r["lhs"], "derived"),
            "rhs": smap.get(r["rhs"], "derived"),
        }
    return results


def closure_report(profile, v, derived, results, unresolved, unresolved_params, outdir, gds):
    meta = profile["meta"]
    counts = {}
    for r in results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    n_profile_inputs = len(profile.get("overrides", {})) + len(profile.get("assumptions", []))
    lines = [
        "# Packaged-pad closure report", "",
        "Generated by generator/solve_packaged.py.", "",
        "**Profile: %s** (%s, %s)." % (meta["profile_id"], meta["assembly_house"],
                                       meta["evidence_class"]),
        "Backend(s): %s. This solver is PDK-agnostic; backend and geometry come from the profile." %
        ", ".join(meta["applies_to_backend"]), "",
        "**Status: %s.** drc_clean: false. NOT A TAPEOUT LAYOUT." % meta["status"], "",
        "## What closed", "",
        "%d assembly inputs were overlaid (NOT written into the generic pdk_rules)." % n_profile_inputs,
        "",
        "| constraint | class | status | lhs | rhs | lhs source | rhs source |",
        "|---|---|---|---|---|---|---|",
    ]
    for r in results:
        o = r.get("operand_sources", {})
        lines.append("| %s | %s | %s | %s | %s | %s | %s |" % (
            r["id"], r["class"], r["status"],
            r.get("lhs_value", "-"), r.get("rhs_value", "-"),
            o.get("lhs", "-"), o.get("rhs", "-")))
    lines += ["", "Constraint status counts: %s." % json.dumps(counts),
              "Unresolved inputs: %d of %d." % (len(unresolved_params), len(v)), "",
              "## Provenance of overlaid values", ""]
    for k, val in sorted(profile.get("overrides", {}).items()):
        lines.append("- **%s = %s** from %s (measured from golden mask GDS)." %
                     (k, val, meta["evidence_class"]))
    for a in profile.get("assumptions", []):
        lines.append("- **%s = %s %s** is a DESIGN ASSUMPTION, not assembly data: %s" %
                     (a["id"], a["value"], a.get("unit", ""), a.get("note", "")))
    lines += ["", "## Deliberately still open", ""]
    for x in unresolved_params[:40]:
        lines.append("- %s" % x)
    if len(unresolved_params) > 40:
        lines.append("- ... and %d more" % (len(unresolved_params) - 40))
    lines += ["", "A packaging commitment supplies assembly GEOMETRY only. Device sizing",
              "(31 design params), ESD HBM target and rail/EM decisions are independent gates",
              "and are NOT closed by choosing a package.", "",
              "## Sources", ""]
    for name, s in profile.get("sources", {}).items():
        url = s.get("url", "") if isinstance(s, dict) else str(s)
        extra = ""
        if isinstance(s, dict) and s.get("sha256"):
            extra = " (sha256 %s)" % s["sha256"][:16]
        lines.append("- %s: %s%s" % (name, url, extra))
    lines += ["", "## Outputs", "", "- directory: %s" % outdir.relative_to(ROOT),
              "- GDS: %s" % (gds.name if gds else "not written"),
              "", "Not performed: PEX/SPICE, IBIS/SI-PI, DRC/LVS, ESD qualification, PVT.", ""]
    return "\n".join(lines), counts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", help="packaging profile name (file stem)")
    ap.add_argument("--design-fixture", help="JSON with sizing values (explicitly labelled)")
    ap.add_argument("--no-gds", action="store_true")
    ap.add_argument("--check-profiles", action="store_true", help="validate all profiles, no solve")
    args = ap.parse_args()

    topo, cons = sl.load()
    errors = []
    # *.fixture.yaml are companions, not profiles themselves
    profiles = {p.stem: yaml.safe_load(p.read_text())
                for p in all_profiles() if not p.stem.endswith(".fixture")}

    def resolve_fixture(path):
        """Accept either a plain JSON map or a *.fixture.yaml with {meta, values}."""
        if path.endswith(".yaml") or path.endswith(".yml"):
            d = yaml.safe_load(open(path))
            if d.get("meta", {}).get("status") != "synthetic_fixture":
                raise ValueError("fixture yaml must declare meta.status=synthetic_fixture")
            tmp = Path(tempfile.mkdtemp()) / "fixture.json"
            tmp.write_text(json.dumps(d["values"]))
            return str(tmp)
        return path

    if args.check_profiles:
        for name, d in profiles.items():
            validate_profile(d, cons["pdk_rules"], errors)
        if errors:
            for e in errors:
                print("ERROR %s: %s" % (name, e), file=sys.stderr)
            return 1
        print("packaging profile checks PASS: %d profiles, all internally consistent" % len(profiles))
        return 0

    if not args.profile:
        print("ERROR --profile required (or --check-profiles)", file=sys.stderr)
        return 1
    profile = profiles.get(args.profile)
    if profile is None:
        print("ERROR unknown profile %s (have: %s)" % (args.profile, ", ".join(profiles)), file=sys.stderr)
        return 1
    validate_profile(profile, cons["pdk_rules"], errors)
    if errors:
        for e in errors:
            print("ERROR %s" % e, file=sys.stderr)
        return 1

    # backend is read from the profile, never hard-coded
    backend = profile["meta"]["applies_to_backend"][0]
    synthetic = bool(args.design_fixture)
    fixture = resolve_fixture(args.design_fixture) if synthetic else None
    v, asm = build_namespace(topo, cons, profile, fixture)
    derived, unres_derived, ns = sl.evaluate(v, cons)
    results = [sl.check_constraint(c, ns, cons) for c in cons["constraints"]]
    smap = source_map(cons, profile)
    results = annotate(results, cons, smap)
    unresolved_params = sorted([k for k, x in v.items() if x is None])
    mode = "symbolic" if unresolved_params else "dimensional"

    pid = profile["meta"]["profile_id"]
    # Keep the honest partial closure as the DEFAULT artifact; put the
    # synthetic full-chain demo in its own subdir so it never overwrites it.
    outdir = OUT / backend / "layout" / "profiles" / pid
    if synthetic:
        outdir = outdir / "synthetic_fixture"
    outdir.mkdir(parents=True, exist_ok=True)
    netlist = OUT / backend / "sdr_bidir_pad.spice"

    lc = {
        "generated_by": "generator/solve_packaged.py",
        "profile": profile["meta"], "backend_from_profile": backend,
        "mode": mode, "drc_clean": False, "signoff": False,
        "note": "profile overrides are in-memory only; generic pdk_rules unchanged",
        "unresolved_param_count": len(unresolved_params),
        "unresolved_params": unresolved_params,
        "overrides": profile.get("overrides", {}),
        "assumptions": profile.get("assumptions", []),
        "derived": derived, "derived_unresolved": unres_derived,
        "constraints": results,
        "constraint_status_counts": {s: sum(1 for r in results if r["status"] == s)
                                     for s in {r["status"] for r in results}},
    }
    (outdir / "closure_constraints.json").write_text(json.dumps(lc, indent=2) + "\n")

    pl = None
    if netlist.exists():
        pl = sl.placement_for(backend, netlist, ns, mode)
        (outdir / "placement.json").write_text(json.dumps(pl, indent=2) + "\n")
        (outdir / "constraint_graph.dot").write_text(sl.dot_graph(cons, results))

    gds = None
    if pl is not None and not args.no_gds:
        target = outdir / "packaged_pad.gds"
        script = sl.klayout_script(outdir / "placement.json", target, mode)
        (outdir / "draw_layout.py").write_text(script)
        try:
            import subprocess
            subprocess.run(["klayout", "-b", "-r", str(outdir / "draw_layout.py")],
                           capture_output=True, text=True, timeout=90)
            if target.exists():
                gds = target
        except (FileNotFoundError, Exception):
            pass

    rep, counts = closure_report(profile, v, derived, results, unres_derived,
                                 unresolved_params, outdir, gds)
    suffix = "_synthetic" if synthetic else ""
    banner = ("**SYNTHETIC DESIGN FIXTURE - verification-only, not a design.**\n\n"
              if synthetic else "")
    rep = rep.replace("# Packaged-pad closure report\n\n",
                      "# Packaged-pad closure report\n\n" + banner, 1)
    (REPORTS / ("packaged_layout_%s%s.md" % (pid, suffix))).write_text(rep)
    (outdir / "closure_report.md").write_text(rep)

    print("backend=%s(from profile) profile=%s evidence=%s mode=%s fixture=%s unresolved=%d/%d %s" %
          (backend, pid, profile["meta"]["evidence_class"], mode,
           "synthetic" if synthetic else "none",
           len(unresolved_params), len(v), json.dumps(counts)))
    print("report: reports/packaged_layout_%s%s.md" % (pid, suffix))
    return 0


if __name__ == "__main__":
    sys.exit(main())
