#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Emit reports/timing_margin.json from the timing contract.

This implements the report artifact of signoff gate S2 and the operating
point classification of S3. It does NOT close them: B is still a TBD
placeholder, so every result is marked open.
"""
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "specs" / "timing_contract.yaml"
REPORTS = ROOT / "reports"


def main():
    con = yaml.safe_load(open(CONTRACT))
    tbds = [p["id"] for cls, body in con["parameter_classes"].items()
            for p in body["params"] if p["status"] == "TBD"]

    points = []
    for p in con["operating_points"]:
        # From docs/TIMING_SWEEP.md section 4, with uncertainty U = 0:
        #   safe_phase = [max(0, B + tAC - tCK), B + tOH]
        #   fixed phase (delta = 0) works while B <= tCK - tAC
        b_limit = round(p["tCK_ns"] - p["tAC_max_ns"], 3)
        points.append({
            "id": p["id"],
            "device": p["device"],
            "tCK_ns": p["tCK_ns"],
            "CL": p["CL"],
            "tAC_max_ns": p["tAC_max_ns"],
            "tOH_min_ns": p["tOH_min_ns"],
            "ideal_setup_ceiling_ns": p["ideal_setup_ceiling_ns"],
            "ideal_hold_ceiling_ns": p["ideal_hold_ceiling_ns"],
            "max_B_for_fixed_phase_ns": b_limit,
            "safe_phase_expr": "max(0, B + tAC - tCK) .. B + tOH   (U=0, skew=0)",
            "fixed_phase_at_B_zero": "feasible",
            "fixed_phase_at_B_above_limit": "infeasible_without_delta",
            "required_delta_expr": "delta ~= B - (tCK - tAC)",
            "classification": "open - B is TBD, not a characterized board delay",
        })

    payload = {
        "status": "open - no signoff claim",
        "generated_by": "generator/check_timing.py",
        "blocking_terms": tbds,
        "blocking_term_count": len(tbds),
        "signoff_gates": {g["id"]: g["status"] for g in con["signoff_gates"]},
        "capability_overall": "NO_GO (reports/capability_report.md)",
        "operating_points": points,
        "evidence": [
            "docs/TIMING_BUDGET.md section 4 (first-order read budget)",
            "docs/TIMING_SWEEP.md section 4 (numerical phase sweep)",
            "specs/devices/*.yaml (datasheet AC tables)",
        ],
        "not_performed": [
            "multi-corner min/max STA closure",
            "SDF annotation and post-layout timing",
            "PEX / SPICE on clock, write DQ, read DQ, OE paths",
            "IBIS / package / PCB signal and power integrity",
            "pad-ring DRC/LVS, ESD, latch-up, EM/IR",
        ],
    }
    REPORTS.mkdir(exist_ok=True)
    (REPORTS / "timing_margin.json").write_text(json.dumps(payload, indent=2) + "\n")
    print(f"wrote {REPORTS / 'timing_margin.json'}")
    print(f"blocking terms: {len(tbds)}")
    for p in points:
        print(f"  {p['id']:20s} fixed-phase B <= {p['max_B_for_fixed_phase_ns']:.1f} ns")
    print("status: open - no signoff claim")
    return 0


if __name__ == "__main__":
    sys.exit(main())
