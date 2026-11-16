#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Model-agnostic ngspice terminal-characterization for the pad flow.

No .model parsing, no fabricated fallback. Every number comes from an
ngspice .op / .dc / .ac run whose exact deck is hashed into the report.
A backend that cannot load is reported BLOCKED with the real simulator
error - never a mock value.

Inputs : specs/pads/device_backends.yaml (wiring only)
Outputs: reports/device_extraction.json
         reports/device_extraction.md
         specs/pads/constraints.yaml (device_measurements section only)

Usage : python3 generator/extract_devices.py [--backend NAME]
"""
import argparse
import glob
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
BACKENDS = ROOT / "specs" / "pads" / "device_backends.yaml"
CONSTRAINTS = ROOT / "specs" / "pads" / "constraints.yaml"
REPORTS = ROOT / "reports"
MARK_BEGIN = "# === BEGIN GENERATED device_measurements ==="
MARK_END = "# === END GENERATED device_measurements ==="


def discover(cfg):
    """Pick a PDK root. Some PDKs have several ciel versions; the lexicographic
    newest is not necessarily the complete one. If root_must_contain is set,
    choose the first version that actually has that file (root_select)."""
    hits = sorted(glob.glob(os.path.expanduser(cfg["root_glob"])))
    if not hits:
        return None
    must = cfg.get("root_must_contain")
    if must:
        valid = [h for h in hits if (Path(h) / must).exists()]
        if not valid:
            return None
        return Path(valid[0] if cfg.get("root_select") == "first_valid" else valid[-1])
    return Path(hits[-1])


class Backend:
    def __init__(self, name, cfg):
        self.name = name
        self.c = cfg
        self.root = discover(cfg)
        self.s = cfg["meta_sstl2"]

    def headers(self, corner):
        out = []
        for h in self.c["headers"]:
            out.append(h.replace("@root@", str(self.root))
                        .replace("@parent@", str(self.root.parent))
                        .replace("@corner@", corner))
        return "\n".join(out) + "\n"

    def cwd(self, td):
        # Some libraries (sky130) use relative .include chains that only
        # resolve from inside the PDK's ngspice directory.
        rel = self.c.get("cwd_rel")
        return str(self.root / rel) if rel else str(td)

    def spiceinit(self):
        return self.c["spiceinit"].replace("@root@", str(self.root))

    def env(self):
        e = {"PDK_ROOT": str(self.root)}
        for k, v in self.c.get("env", {}).items():
            e[k] = v.replace("@root@", str(self.root)).replace("@parent@", str(self.root.parent))
        return e

    def inst(self, name, is_pmos, wf_um, l_um, fingers):
        # width_mode is verified per PDK (see device_backends.yaml notes):
        #  per_finger_fixed : w is PER-FINGER, finger_param multiplies it (gf180 m=N)
        #  total_scaled     : w is TOTAL, finger_param only splits it (ihp ng, sky130 nf)
        c = self.c
        cell = c["pmos_cell"] if is_pmos else c["nmos_cell"]
        sfx = c["size_suffix"]
        fp = c["finger_param"]
        if c["width_mode"] == "per_finger_fixed":
            w = wf_um
        else:
            w = wf_um * fingers
        line = "X%s d g 0 0 %s w=%g%s l=%g%s %s=%d" % (
            name, cell, w, sfx, l_um, sfx, fp, fingers)
        if c.get("extra_inst"):
            line += " " + c["extra_inst"]
        return line

    def l_drv(self, is_pmos):
        return self.c["l_drv_p_um"] if is_pmos else self.c["l_drv_n_um"]


def run_ngspice(be, corner, temp_c, body, marker):
    if shutil.which("ngspice") is None:
        return {"ok": False, "error": "ngspice binary not found"}
    with tempfile.TemporaryDirectory(prefix="dev_ext_") as td:
        td = Path(td)
        cwd = be.cwd(td)
        # A PDK-owned cwd must not be polluted with a local .spiceinit; those
        # backends pass -n instead (ngspice_flags).
        if cwd == str(td):
            (td / ".spiceinit").write_text(be.spiceinit())
        deck = be.headers(corner) + ".temp %g\n" % temp_c + body
        (td / "tb.spice").write_text(deck)
        env = os.environ.copy()
        env.update(be.env())
        flags = be.c.get("ngspice_flags", [])
        cmd = ["ngspice"] + flags + ["-b", str(td / "tb.spice")]
        try:
            r = subprocess.run(cmd, cwd=cwd,
                               env=env, capture_output=True, text=True, timeout=150)
            out = r.stdout + r.stderr
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": "ngspice timeout (150s)"}
        ok = (marker in out) and ("fatal error" not in out.lower())
        return {"ok": ok, "stdout": out,
                "deck_sha256": hashlib.sha256(deck.encode()).hexdigest(),
                "error": "" if ok else _first_error(out)}


def _first_error(out):
    for line in out.splitlines():
        low = line.lower()
        if any(k in low for k in ("error", "fatal", "could not find", "no such",
                                  "not found", "couldn't be loaded")):
            return line.strip()
    return "marker not found in ngspice output"


def _floats(line):
    m = re.search(r"=\s*(.+)$", line)
    if not m:
        return []
    vals = []
    for tok in m.group(1).split():
        try:
            vals.append(float(tok))
        except ValueError:
            pass
    return vals


def _grab(out, key):
    for line in out.splitlines():
        if line.strip().startswith(key + "="):
            return _floats(line)
    return []


def probe_triode(be, corner, temp_c, is_pmos, fingers):
    s = be.s
    pol = -1.0 if is_pmos else 1.0
    body = """Vg g 0 DC %g
Vd d 0 DC %g
%s
.control
 op
 let idma = abs(i(Vd)) * 1e3
 echo "RESULT_ID_MA=" $&idma
 quit
.endc
.end
""" % (pol * s["vddq_min_v"], pol * s["vds_triode_v"],
       be.inst("DUT", is_pmos, s["wf_ref_um"], be.l_drv(is_pmos), fingers))
    r = run_ngspice(be, corner, temp_c, body, "RESULT_ID_MA=")
    if not r["ok"]:
        return {"status": "ERROR", "error": r["error"], "deck_sha256": r["deck_sha256"]}
    v = _grab(r["stdout"], "RESULT_ID_MA")
    if not v:
        return {"status": "ERROR", "error": "RESULT_ID_MA parse failed",
                "deck_sha256": r["deck_sha256"]}
    id_ma = abs(v[0])
    w_tot = s["wf_ref_um"] * fingers
    r_on = (s["vds_triode_v"] / (id_ma * 1e-3)) if id_ma > 0 else None
    return {"status": "measured", "Id_mA": round(id_ma, 5),
            "R_on_ohm": round(r_on, 3) if r_on else None,
            "R_on_unit_ohm_um": round(r_on * w_tot, 2) if r_on else None,
            "W_total_um": w_tot, "fingers": fingers,
            "Vgs_V": s["vddq_min_v"], "Vds_V": s["vds_triode_v"],
            "corner": corner, "temp_c": temp_c, "source": "ngspice",
            "deck_sha256": r["deck_sha256"]}


def probe_sat_dc(be, corner, temp_c, is_pmos):
    s = be.s
    pol = -1.0 if is_pmos else 1.0
    w = be.c["trial_p_w_um"] if is_pmos else be.c["trial_n_w_um"]
    l = be.c["l_ana_um"]
    body = """Vg g 0 DC 0
Vd d 0 DC %g
%s
.control
 dc Vg 0 %g %g
 let idv = abs(i(Vd))
 let vgv = abs(v(g))
 echo "IDVEC=" $&idv
 echo "VGVEC=" $&vgv
 quit
.endc
.end
""" % (pol * s["vds_sat_v"], be.inst("DUT", is_pmos, w, l, 1),
       pol * s["vgs_sat_v"], pol * 0.02)
    r = run_ngspice(be, corner, temp_c, body, "IDVEC=")
    if not r["ok"]:
        return {"status": "ERROR", "error": r["error"], "deck_sha256": r["deck_sha256"]}
    ids = _grab(r["stdout"], "IDVEC")
    vgs = _grab(r["stdout"], "VGVEC")
    if len(ids) < 5 or len(vgs) < 5:
        return {"status": "ERROR", "error": "DC sweep vector parse failed",
                "deck_sha256": r["deck_sha256"]}
    n = min(len(ids), len(vgs))
    ids, vgs = ids[:n], vgs[:n]
    icrit = s["vth_crit_a_per_wl"] * (w / l)
    vth = next((vgs[i] for i in range(n) if ids[i] >= icrit), vgs[-1])
    gm_id = []
    for i in range(1, n - 1):
        did = (ids[i + 1] - ids[i - 1]) / (vgs[i + 1] - vgs[i - 1] + 1e-30)
        gm_id.append(abs(did) / ids[i] if ids[i] > 0 else 0.0)
    itgt = s["i_branch_ua"] * 1e-6
    j = min(range(n), key=lambda k: abs(ids[k] - itgt))
    jp, jm = min(j + 1, n - 1), max(j - 1, 0)
    gm_op = abs((ids[jp] - ids[jm]) / (vgs[jp] - vgs[jm] + 1e-30))
    return {"status": "measured", "Vth_V": round(vth, 4),
            "Vgs_at_Ibranch_V": round(vgs[j], 4), "Id_at_op_A": ids[j],
            "gm_at_op_S": round(gm_op, 9),
            "gm_Id_at_op_Vinv": round(gm_op / itgt, 2) if itgt else None,
            "gm_Id_peak_Vinv": round(max(gm_id), 2) if gm_id else None,
            "Id_sat_at_Vgs_max_A": ids[-1],
            "sweep_points": n, "trial_W_um": w, "trial_L_um": l,
            "corner": corner, "temp_c": temp_c, "source": "ngspice",
            "deck_sha256": r["deck_sha256"]}


def probe_ac_caps(be, corner, temp_c, is_pmos):
    s = be.s
    pol = -1.0 if is_pmos else 1.0
    w = be.c["trial_p_w_um"] if is_pmos else be.c["trial_n_w_um"]
    l = be.c["l_ana_um"]
    body = """Vg g 0 DC %g AC 1
Vd d 0 DC %g
%s
.control
 ac lin 1 100meg 100meg
 let cgg = abs(imag(i(Vg))) / (2 * 3.141592653589793 * 100e6) * 1e15
 let cgd = abs(imag(i(Vd))) / (2 * 3.141592653589793 * 100e6) * 1e15
 echo "RESULT_CGG_FF=" $&cgg
 echo "RESULT_CGD_FF=" $&cgd
 quit
.endc
.end
""" % (pol * s["vref_v"], pol * s["vref_v"], be.inst("DUT", is_pmos, w, l, 1))
    r = run_ngspice(be, corner, temp_c, body, "RESULT_CGG_FF=")
    if not r["ok"]:
        return {"status": "ERROR", "error": r["error"], "deck_sha256": r["deck_sha256"]}
    cgg = _grab(r["stdout"], "RESULT_CGG_FF")
    cgd = _grab(r["stdout"], "RESULT_CGD_FF")
    if not cgg or not cgd:
        return {"status": "ERROR", "error": "AC cap parse failed",
                "deck_sha256": r["deck_sha256"]}
    return {"status": "measured", "Cgg_fF": round(cgg[0], 4),
            "Cgd_fF": round(cgd[0], 4),
            "Cgg_per_um_fF": round(cgg[0] / w, 4),
            "Cgd_per_um_fF": round(cgd[0] / w, 4),
            "freq_hz": s["ac_freq_hz"], "trial_W_um": w, "trial_L_um": l,
            "corner": corner, "temp_c": temp_c, "source": "ngspice",
            "deck_sha256": r["deck_sha256"]}


def calibrate(be, corner, temp_c, is_pmos):
    s = be.s
    target = s["class_I_target_ma"]
    ref = probe_triode(be, corner, temp_c, is_pmos, 2)
    if ref["status"] != "measured":
        return {"status": "ERROR", "error": "reference probe failed: " + ref["error"]}
    per_finger = ref["Id_mA"] / 2.0
    m = max(2, int(math.ceil(target / max(per_finger, 1e-6))))
    if m % 2:
        m += 1
    m = min(m, 512)   # guard: never emit an absurd finger count
    log = []
    prev_id = 0.0
    for it in range(1, 6):
        meas = probe_triode(be, corner, temp_c, is_pmos, m)
        if meas["status"] != "measured":
            return {"status": "ERROR", "error": "iter %d failed: %s" % (it, meas["error"]),
                    "calibration_log": log}
        log.append({"iter": it, "fingers": m, "Id_mA": meas["Id_mA"],
                    "W_total_um": meas["W_total_um"],
                    "deck_sha256": meas["deck_sha256"]})
        if meas["Id_mA"] >= target:
            return {"status": "measured", "target_mA": target,
                    "M_class_I": m, "M_class_II": m * 2,
                    "W_class_I_um": round(m * s["wf_ref_um"], 2),
                    "W_class_II_um": round(2 * m * s["wf_ref_um"], 2),
                    "Id_verified_mA": meas["Id_mA"],
                    "R_on_wc_ohm": meas["R_on_ohm"],
                    "corner": corner, "temp_c": temp_c, "source": "ngspice",
                    "calibration_log": log}
        # If current did not grow with the width, the model is not scaling:
        # stop instead of exponentiating the finger count.
        if meas["Id_mA"] <= prev_id * 1.02:
            return {"status": "NOT_CONVERGED", "target_mA": target,
                    "reason": "Id did not grow with finger count; width scaling invalid",
                    "calibration_log": log, "source": "ngspice"}
        prev_id = meas["Id_mA"]
        m = min(512, max(m + 2, 2 * int(math.ceil(m * target / max(meas["Id_mA"], 0.1) / 2))))
    return {"status": "NOT_CONVERGED", "target_mA": target,
            "reason": "iteration limit reached",
            "calibration_log": log, "source": "ngspice"}


def characterize(be, only_probe=False):
    out = {"backend": be.name, "root": str(be.root) if be.root else None,
           "model_kind": be.c["model_kind"], "license": be.c.get("license"),
           "corners": be.c["corners"], "temps_c": be.c["temps_c"]}
    if be.root is None:
        out["status"] = "BLOCKED"
        out["reason"] = "PDK root not found for glob " + be.c["root_glob"]
        return out
    corners, temps = be.c["corners"], be.c["temps_c"]
    for tag in ("tt", "ss", "ff"):
        out["triode_" + tag] = {}
        for dev, pmos in (("NMOS", False), ("PMOS", True)):
            out["triode_" + tag][dev] = probe_triode(
                be, corners[tag], temps[tag], pmos, 2)
    ok = all(out["triode_tt"][d]["status"] == "measured" for d in ("NMOS", "PMOS"))
    if not ok or only_probe:
        out["status"] = "BLOCKED" if not ok else "PROBE_ONLY"
        out["reason"] = "triode probe failed; see triode_tt errors" if not ok else "probe-only backend"
        return out
    out["tx_calibration"] = {}
    for dev, pmos in (("NMOS", False), ("PMOS", True)):
        out["tx_calibration"][dev] = calibrate(be, corners["ss"], temps["ss"], pmos)
    out["sat_dc"] = {}
    out["ac_caps"] = {}
    for dev, pmos in (("NMOS", False), ("PMOS", True)):
        out["sat_dc"][dev] = probe_sat_dc(be, corners["tt"], temps["tt"], pmos)
        out["ac_caps"][dev] = probe_ac_caps(be, corners["tt"], temps["tt"], pmos)
    s = be.s
    n, p = out["sat_dc"]["NMOS"], out["sat_dc"]["PMOS"]
    if n["status"] == "measured" and p["status"] == "measured":
        v_ds_n = round(s["vref_v"] - n["Vgs_at_Ibranch_V"], 4)
        v_sd_p = round(s["vddq_min_v"] - (s["vref_v"] + p["Vgs_at_Ibranch_V"]), 4)
        hmin = s["headroom_min_v"]
        viable = v_ds_n >= hmin and v_sd_p >= hmin
        out["rx_icmr"] = {"status": "measured",
                          "V_DS_tail_NMOS_V": v_ds_n, "V_SD_tail_PMOS_V": v_sd_p,
                          "headroom_min_V": hmin, "PMOS_pair_active": viable,
                          "topology": "COMPLEMENTARY_RAIL_TO_RAIL" if viable
                                      else "NMOS_ONLY_DIFF_PAIR",
                          "note": "headroom proxy from measured Vgs at I_branch; "
                                  "not a full stacked tail-current-source simulation"}
    else:
        out["rx_icmr"] = {"status": "ERROR", "error": "sat_dc missing"}
    out["status"] = "MEASURED"
    return out


def patch_constraints(results):
    text = CONSTRAINTS.read_text()
    block = [MARK_BEGIN,
             "# Generated by generator/extract_devices.py -- DO NOT EDIT BY HAND.",
             "# Device characteristics measured by ngspice terminal probes.",
             "# pdk_rules below (DRC/ESD/EM/pitch) are layout-rule inputs and",
             "# deliberately remain TBD: a single-device DC/AC probe cannot",
             "# determine DRC spacing, ESD target, metal Jmax or pad pitch.",
             "device_measurements:",
             "  generated_by: generator/extract_devices.py",
             "  simulator: \"ngspice-44.2\"",
             "  status: no_signoff_claim",
             "  backends:"]
    for name, r in results.items():
        block.append("    %s:" % name)
        block.append("      status: %s" % r["status"])
        block.append("      model_kind: \"%s\"" % r["model_kind"])
        if r["status"] != "MEASURED":
            block.append("      reason: \"%s\"" % r.get("reason", "").replace('"', "'"))
        if r["status"] == "MEASURED":
            for dev in ("NMOS", "PMOS"):
                t = r["triode_tt"][dev]
                block.append("      %s:" % dev)
                block.append("        Vth_V: %s" % r["sat_dc"][dev]["Vth_V"])
                block.append("        R_on_unit_ohm_um: %s" % t["R_on_unit_ohm_um"])
                block.append("        Cgg_per_um_fF: %s" % r["ac_caps"][dev]["Cgg_per_um_fF"])
                block.append("        Cgd_per_um_fF: %s" % r["ac_caps"][dev]["Cgd_per_um_fF"])
                cal = r["tx_calibration"][dev]
                if cal.get("status") == "measured":
                    block.append("        M_class_I: %s" % cal["M_class_I"])
                    block.append("        Id_verified_mA: %s" % cal["Id_verified_mA"])
                else:
                    block.append("        tx_calibration: %s" % cal.get("status"))
                block.append("        source: ngspice")
    block += ["  rule_fill_map:",
              "    IO_CURRENT: derivable_from_triode_Id (target is a design spec, keep TBD)",
              "    DQ_BIT_SKEW_MAX: needs timing budget, NOT a device probe",
              "    RAIL_WIDTH: needs metal EM rules, NOT a device probe",
              "    ESD_AREA_MIN / GUARD_RING_RULE_MIN: need ESD/latch-up deck",
              "    PAD_PITCH / PAD_OPENING / DRC_MIN_*: need DRC deck and package",
              "    METAL_JMAX: need PDK metal EM rules",
              MARK_END, ""]
    new = "\n".join(block)
    if MARK_BEGIN in text:
        a = text.index(MARK_BEGIN)
        b = text.index(MARK_END, a) + len(MARK_END)
        text = text[:a] + new.rstrip("\n") + text[b:]
    else:
        text = text.rstrip("\n") + "\n\n" + new
    CONSTRAINTS.write_text(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", help="only characterize this backend")
    ap.add_argument("--no-constraints", action="store_true")
    args = ap.parse_args()
    doc = yaml.safe_load(BACKENDS.read_text())
    s = doc["meta"]["sstl2_target"]
    results = {}
    for name, cfg in doc["backends"].items():
        if args.backend and name != args.backend:
            continue
        cfg = dict(cfg)
        cfg["meta_sstl2"] = s
        be = Backend(name, cfg)
        print("== %s ==" % name, flush=True)
        r = characterize(be, only_probe=(cfg.get("expectation") == "probe_only"))
        results[name] = r
        print("   status: %s" % r["status"], flush=True)
    REPORTS.mkdir(exist_ok=True)
    payload = {"generated_by": "generator/extract_devices.py",
               "simulator": "ngspice-44.2", "status": "no_signoff_claim",
               "method": "terminal .op/.dc/.ac measurement; no .model parsing; no mock fallback",
               "backends": results}
    (REPORTS / "device_extraction.json").write_text(json.dumps(payload, indent=2) + "\n")
    if not args.no_constraints:
        patch_constraints(results)
    md = ["# ngspice device extraction", "",
          "Generated by generator/extract_devices.py. No .model parsing, no fabricated values.", "",
          "| backend | model | status | NMOS Vth | PMOS Vth | M(Class I) N/P | RX topology |",
          "|---|---|---|---|---|---|---|"]
    for name, r in results.items():
        if r["status"] == "MEASURED":
            nv = r["sat_dc"]["NMOS"]["Vth_V"]
            pv = r["sat_dc"]["PMOS"]["Vth_V"]
            cn = r["tx_calibration"]["NMOS"]
            cp = r["tx_calibration"]["PMOS"]
            mn = cn.get("M_class_I", cn.get("status"))
            mp = cp.get("M_class_I", cp.get("status"))
            topo = r["rx_icmr"]["topology"]
            md.append("| %s | %s | %s | %s | %s | %s / %s | %s |" %
                      (name, r["model_kind"], r["status"], nv, pv, mn, mp, topo))
        else:
            md.append("| %s | %s | %s | - | - | - | - |" %
                      (name, r["model_kind"], r["status"]))
    blocking = [k for k, v in results.items() if v["status"] != "MEASURED"]
    note = ("BLOCKED backends carry the real ngspice error in device_extraction.json."
            if blocking else "All configured backends measured with real ngspice decks; no mock values.")
    md += ["", note, "",
           "Not a signoff result: no PVT min/max STA, no PEX, no IBIS, no DRC/LVS.", ""]
    (REPORTS / "device_extraction.md").write_text("\n".join(md))
    print("report: reports/device_extraction.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
