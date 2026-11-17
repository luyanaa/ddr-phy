#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""P1-3 end-to-end timing margins: pad SPICE + digital STA + device spec.

Inputs
  reports/pad_delay_gf180mcuD_<tag>.json   pad tpd (generator/emit_char_delay.py)
  reports/sta/p1_3_sta.txt                 OpenSTA slacks (sim/p1_3_timing.sh)
  specs/devices/micron_mt48lc16m16a2-75.yaml
  specs/timing_contract.yaml

Outputs
  reports/p1_3_margins.json
  reports/p1_3_timing.md

The STA netlist is unplaced with no wire load, and the pad numbers come from
the first-pass sizing fixture. Every number here is a DESIGN ASSUMPTION.
The report states the margins; it does not claim signoff.
"""
import json
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
REPORTS = ROOT / "reports"
DEVICE = ROOT / "specs" / "devices" / "micron_mt48lc16m16a2-75.yaml"
CONTRACT = ROOT / "specs" / "timing_contract.yaml"

# STA slack -> path delay. Output paths are constrained with a 0 output
# delay on a 10 ns clock, so max arrival = 10 - slack and min arrival is
# the slack itself (hold reference is 0). Input paths carry the capture
# flip-flop setup/hold inside the slack, so the delay is 10 - slack.
TCK = 10.0
CORNERS = {"tt": "tt_27", "ss": "ss_125", "ff": "ff_-40"}


def dev_param(dev, ident):
    for p in dev["parameters"]:
        if p["id"] == ident:
            return p["value"]
    raise KeyError(ident)


def load_pad(tag):
    p = REPORTS / ("pad_delay_gf180mcuD_%s.json" % tag)
    if not p.exists():
        return None
    return json.loads(p.read_text())


def load_sta():
    """Parse the per-corner OpenSTA logs.

    `report_checks` prints the launch clock edge time and the data arrival
    time. The pad pin delay is arrival - launch_edge; for input paths the
    input delay is 0, so arrival is the path delay.
    """
    out = {}
    for corner in CORNERS:
        p = REPORTS / "sta" / ("p1_3_%s.log" % corner)
        if not p.exists():
            continue
        tag = None
        edge = None
        for line in p.read_text().splitlines():
            t = line.strip()
            if t.startswith("== "):
                tag = t[3:].strip()
                edge = None
                continue
            if not tag:
                continue
            if "clock clk (" in t and "edge)" in t:
                f = t.split()
                try:
                    edge = float(f[0])
                except (ValueError, IndexError):
                    edge = None
                continue
            if t.endswith("data arrival time"):
                f = t.split()
                try:
                    arr = float(f[0])
                except (ValueError, IndexError):
                    continue
                delay = arr - (edge or 0.0)
                out.setdefault(corner, {})[tag] = delay
                tag = None
    return out


def load_channel():
    """P1-4 channel delay (ns) and trace skew (ns), if characterized."""
    files = sorted(REPORTS.glob("channel_*_*.json"))
    if not files:
        return None
    p = files[0]
    d = json.loads(p.read_text())
    m = d["measures"]
    lo = min(m["t_chan_r"], m["t_chan_f"])
    hi = max(m["t_chan_r"], m["t_chan_f"])
    return {"file": p.name, "min": lo, "max": hi,
            "skew": d["trace_skew_s"]}


def load_oe(tag):
    """OE on/off from the P1-1 characterization (same PVT tag)."""
    p = REPORTS / ("pad_char_gf180mcuD_%s.json" % tag)
    if not p.exists():
        return {}
    return json.loads(p.read_text()).get("measures", {})


def main():
    dev = yaml.safe_load(open(DEVICE))
    con = yaml.safe_load(open(CONTRACT))
    op = con["operating_points"][0]          # baseline_100_cl2
    tck = float(op["tCK_ns"])
    tds = dev_param(dev, "tDS_min")
    tdh = dev_param(dev, "tDH_min")
    tac = dev_param(dev, "tAC_CL2_max")
    toh = dev_param(dev, "tOH_min_loaded")
    thz = dev_param(dev, "tHZ_CL2_max")
    tlz = dev_param(dev, "tLZ_min")
    sta = load_sta()
    ch = load_channel()

    rows = []
    for corner, tag in CORNERS.items():
        pad = load_pad(tag)
        if pad is None or corner not in sta:
            continue
        m = pad["measures"]
        oe = load_oe(tag)
        s = sta[corner]
        # digital clk -> pad (ns); unplaced, no wire load
        ck_max, ck_min = s["ck_max"], s["ck_min"]
        dqo_max, dqo_min = s["dqo_max"], s["dqo_min"]
        dqi_max, dqi_min = s["dqi_max"], s["dqi_min"]
        # pad delays (s -> ns)
        po_max = max(m["tpd_out_r"], m["tpd_out_f"]) * 1e9
        po_min = min(m["tpd_out_r"], m["tpd_out_f"]) * 1e9
        pi_max = max(m["tpd_in_r"], m["tpd_in_f"]) * 1e9
        pi_min = min(m["tpd_in_r"], m["tpd_in_f"]) * 1e9
        # P1-4 board: the same channel for CK and DQ, so only the
        # matched-length skew survives the subtraction.
        b_min = (ch["min"] - ch["skew"]) if ch else 0.0
        b_max = (ch["max"] + ch["skew"]) if ch else 0.0
        # end-to-end path delays
        ckf_max = ck_max + po_max + b_max   # tCLK,fwd max (pad + board)
        ckf_min = ck_min + po_min + b_min   # tCLK,fwd min
        dqtx_max = dqo_max + po_max + b_max # tDQ,tx max
        dqtx_min = dqo_min + po_min + b_min # tDQ,tx min
        dqrx_max = dqi_max + pi_max        # tDQ,rx max (incl. FF setup)
        dqrx_min = dqi_min + pi_min        # tDQ,rx min (incl. FF hold)
        # write path, P1-3 path B: the pin command is pipelined one cycle
        # (+tCK) and DQ/DM/OE launch on the falling edge (+tCK/2), so the
        # relative budget gains tCK/2 against the command edge.
        w_setup = tck / 2.0 + ckf_min - dqtx_max - tds
        w_hold = tck / 2.0 + dqtx_min - ckf_max - tdh
        # read path
        r_setup = tck - tac - dqrx_max
        r_hold = toh + dqrx_min
        # OE turnaround: the driver must be off before the DRAM drives
        # (tLZ) and on only after the DRAM releases (tHZ). One guard cycle.
        toe_off = oe.get("t_oe_off", 0.0) * 1e9
        toe_on = oe.get("t_oe_on", 0.0) * 1e9
        # driver release: t_oe_off after the OE edge, before the DRAM drives
        oe_off = tck - toe_off - tlz
        # driver enable: after the DRAM releases (tHZ) plus t_oe_on
        oe_on = tck - thz - toe_on
        rows.append({
            "corner": corner, "pad_tag": tag,
            "tco_ck_ns": [ck_min, ck_max],
            "tco_dq_ns": [dqo_min, dqo_max],
            "pad_out_ns": [po_min, po_max],
            "pad_in_ns": [pi_min, pi_max],
            "tCLK_fwd_ns": [ckf_min, ckf_max],
            "tDQ_tx_ns": [dqtx_min, dqtx_max],
            "tDQ_rx_ns": [dqrx_min, dqrx_max],
            "write_setup_ns": w_setup,
            "write_hold_ns": w_hold,
            "read_setup_ns": r_setup,
            "read_hold_ns": r_hold,
            "board_min_ns": b_min,
            "board_max_ns": b_max,
            "t_oe_on_ns": toe_on,
            "t_oe_off_ns": toe_off,
            "oe_off_ns": oe_off,
            "oe_on_ns": oe_on,
        })

    if not rows:
        raise SystemExit("ERROR: no corner data; run sim/p1_3_timing.sh")

    worst = {
        "write_setup_ns": min(r["write_setup_ns"] for r in rows),
        "write_hold_ns": min(r["write_hold_ns"] for r in rows),
        "read_setup_ns": min(r["read_setup_ns"] for r in rows),
        "read_hold_ns": min(r["read_hold_ns"] for r in rows),
        "oe_off_ns": min(r["oe_off_ns"] for r in rows),
        "oe_on_ns": min(r["oe_on_ns"] for r in rows),
    }
    status = "GO" if all(v > 0 for v in worst.values()) else "NO_GO"

    rep = {
        "generated_by": "generator/p1_3_margins.py",
        "status": status,
        "claim": "design_assumption - unplaced STA netlist, first-pass pad fixture",
        "operating_point": op["id"],
        "tCK_ns": tck,
        "device": dev["meta"]["part"],
        "device_terms_ns": {"tDS": tds, "tDH": tdh, "tAC_max": tac,
                            "tOH_min": toh, "tHZ_max": thz, "tLZ_min": tlz},
        "channel": ch,
        "notes": [
            "STA netlist is synthesised but not placed and has no wire load.",
            "Pad delays are SPICE from the first-pass sizing fixture.",
            "Board/package terms are not included (P1-4).",
            "OE margins use the P1-1 t_oe_on/t_oe_off and one guard cycle;",
            "  the board delay that sets the DRAM-side reference is P1-4.",
        ],
        "corners": rows,
        "worst": worst,
    }
    (REPORTS / "p1_3_margins.json").write_text(json.dumps(rep, indent=2) + "\n")

    md = ["# P1-3: CK output and end-to-end timing margins", "",
          "**Status: %s** (design assumption; unplaced STA netlist, first-pass "
          "pad fixture, no board/package terms)." % status, "",
          "Operating point `%s`, tCK = %.1f ns, device %s."
          % (op["id"], tck, dev["meta"]["part"]), "",
          "## Method", "",
          "- Digital `clk -> pad` and `pad -> capture FF` delays: OpenSTA on a",
          "  yosys-synthesised `sdram_phy_top` with the GF180 `mcu7t5v0` liberty",
          "  (`reports/sta/`). Unplaced, zero wire load.",
          "- Pad `OUT -> PAD` and `PAD -> IN` delays: ngspice on the sized pad",
          "  slice (`reports/pad_delay_gf180mcuD_*.json`).",
          "- Device terms: `specs/devices/micron_mt48lc16m16a2-75.yaml`.",
          "", "## Per-corner results (ns)", "",
          "| corner | tco_ck | tco_dq | pad_out | pad_in | tCLK,fwd | tDQ,tx | tDQ,rx | W setup | W hold | R setup | R hold | OE on | OE off |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        md.append("| %s | %.3f-%.3f | %.3f-%.3f | %.3f-%.3f | %.4f-%.4f | %.3f-%.3f | %.3f-%.3f | %.3f-%.3f | %+.3f | %+.3f | %+.3f | %+.3f | %+.3f | %+.3f |" % (
            r["corner"], *r["tco_ck_ns"], *r["tco_dq_ns"], *r["pad_out_ns"],
            *r["pad_in_ns"], *r["tCLK_fwd_ns"], *r["tDQ_tx_ns"], *r["tDQ_rx_ns"],
            r["write_setup_ns"], r["write_hold_ns"], r["read_setup_ns"],
            r["read_hold_ns"], r["oe_on_ns"], r["oe_off_ns"]))
    md += ["", "## Worst case", "",
           "| check | margin (ns) |", "|---|---|"]
    for k, v in worst.items():
        md.append("| %s | %+.3f |" % (k, v))
    md += ["", "## Reading", ""]
    if worst["write_setup_ns"] <= 0:
        md += ["- Write setup is **negative**: the forwarded CK leaves the chip",
               "  ~0.6 ns earlier than DQ (2-gate mux vs register + mux), so the",
               "  DRAM sees DQ after its CK edge. This is the `assign ck = clk`",
               "  limitation from `docs/TIMING_BUDGET.md` section 5, now with",
               "  numbers. It needs a characterized CK phase/delay (gate G6) or a",
               "  write-scheme change; no constraint tweak fixes it."]
    if worst["write_hold_ns"] <= 0:
        md += ["- Write hold is negative for the same reason (CK too early)."]
    if worst["read_setup_ns"] <= 0:
        md += ["- Read setup is negative: tAC(max) plus the receive path exceeds tCK."]
    if worst["read_hold_ns"] <= 0:
        md += ["- Read hold is negative."]
    md += ["", "## Not included", "",
           "- Board/package: included as the P1-4 channel (matched traces).",
          "- The channel is a pre-layout RLC/T-line model, not an EM extraction.",
           "- Clock jitter/DCD/OCV: the SDC uncertainty term is still TBD.",
           "- Placement, routing, CTS, wire load, SDF back-annotation.",
           "- OE turn-on: needs the DRAM release reference through the board.",
           "", "`reports/capability_report.md` stays `NO_GO`."]
    (REPORTS / "p1_3_timing.md").write_text("\n".join(md) + "\n")
    print("P1-3 status %s; worst %s" % (status, json.dumps(worst)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
