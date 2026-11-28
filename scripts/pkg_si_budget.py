#!/usr/bin/env python3
"""First-order package + board SI timing budget for DDR1.

Reads the QFN48 coupon RLC and adds an explicit FR4 board estimate.  This is a
planning budget, not IBIS/3D-EM/SSN signoff.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QFN = ROOT / "reports/ddr1/qfn48_pkg_rlc.json"
OUT = ROOT / "reports/ddr1/pkg_si_budget.json"

# Board assumptions, to be replaced by the real stack-up / length table.
BOARD = {
    "stackup": "4-layer FR4, 50 ohm microstrip",
    "trace_len_mm": 25.0,
    "eps_eff": 3.4,
    "tpd_ps_per_mm": 6.2,
    "length_mismatch_mm_max": 5.0,
    "connector_ssn_ps": 20.0,
}


def main() -> None:
    pkg = json.loads(QFN.read_text())
    pins = pkg["pins"]
    flights = [p["t_l_over_50_ps"] for p in pins]
    # sqrt(LC) is the LC-only propagation estimate; L/50 is the matched-50ohm
    # first-order flight used by the existing SDC placeholder.
    lc = [((p["l_total_nh"] * 1e-9) * (p["c_total_pf"] * 1e-12)) ** 0.5 * 1e12 for p in pins]
    board_flight = BOARD["trace_len_mm"] * BOARD["tpd_ps_per_mm"]
    board_skew = BOARD["length_mismatch_mm_max"] * BOARD["tpd_ps_per_mm"]
    pkg_skew = max(flights) - min(flights)
    total_skew = pkg_skew + board_skew + BOARD["connector_ssn_ps"]
    data = {
        "meta": {
            "source": str(QFN.relative_to(ROOT)),
            "model": "first-order package RLC + estimated FR4 board; not IBIS/3D EM",
            "signoff": False,
        },
        "package": {
            "l_nh": [min(p["l_total_nh"] for p in pins), max(p["l_total_nh"] for p in pins)],
            "r_ohm": [min(p["r_total_ohm"] for p in pins), max(p["r_total_ohm"] for p in pins)],
            "c_pf": max(p["c_total_pf"] for p in pins),
            "flight_l_over_50_ps": [min(flights), max(flights)],
            "flight_sqrt_lc_ps": [min(lc), max(lc)],
            "pin_to_pin_flight_skew_ps": pkg_skew,
        },
        "board": BOARD | {
            "flight_ps": board_flight,
            "length_mismatch_skew_ps": board_skew,
        },
        "channel_budget": {
            "absolute_flight_ps": max(flights) + board_flight,
            "matched_flight_cancels": True,
            "skew_terms_ps": {
                "package_pin_to_pin": pkg_skew,
                "board_length_mismatch": board_skew,
                "connector_ssn": BOARD["connector_ssn_ps"],
            },
            "total_skew_ps": total_skew,
            "fraction_ui_133mhz": total_skew / 7500.0,
            "fraction_ui_166mhz": total_skew / 6000.0,
        },
        "sdc_recommendation": {
            "pkg_flight_ns": round(max(flights) / 1000.0, 3),
            "channel_skew_ns": round(total_skew / 1000.0, 3),
            "note": "add channel_skew to read/write uncertainty unless DQS training removes it",
        },
    }
    OUT.write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
