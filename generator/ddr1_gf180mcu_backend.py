#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""gf180mcu adapter for the process-neutral DDR1 discrete-search runner.
Contract version 1. EXPERIMENTAL + PHYSICAL NO-GO: GF180's 2.3-2.7 V
SSTL-2 operating point with nfet_03v3/pfet_03v3 is not foundry-characterized.
This adapter supports witness-point characterization only, not signoff.
"""

from pathlib import Path
import math
import sys

CONTRACT_VERSION = 1

# gf180 ppolyf_u uses r_length/r_width in metres.
DEVICE_MAPPINGS = {
    "xrdriver_w_um": {
        "prefix": "XRDRIVER DRIVER PAD VSSIO ppolyf_u r_length=0.6u r_width=",
        "suffix": "",
        "default_token": "8u",
        "default_value": 8,
    },
    "xrbias_l_um": {
        "prefix": "XRBIAS VDDIO BIAS VSSIO ppolyf_u r_length=",
        "suffix": " r_width=1.2u",
        "default_token": "13u",
        "default_value": 13,
    },
}


def validate_config(config, repo_root):
    if config.get("schema_version") != CONTRACT_VERSION:
        raise ValueError("unsupported DDR1 backend schema_version")
    if config.get("adapter") != "generator/ddr1_gf180mcu_backend.py":
        raise ValueError("gf180 backend adapter path must match this adapter")
    search = config.get("search", {})
    knobs = search.get("knobs", [])
    by_id = {k.get("id"): k for k in knobs}
    if len(by_id) != len(knobs) or set(by_id) != set(DEVICE_MAPPINGS):
        raise ValueError("gf180 search knobs must map exactly to XRDRIVER and XRBIAS")
    for kid, mp in DEVICE_MAPPINGS.items():
        if by_id[kid].get("default") != mp["default_value"]:
            raise ValueError(f"{kid}: default does not match source identity")
    char = config.get("characterization", {})
    for key in ("script", "source_netlist"):
        v = char.get(key)
        if not isinstance(v, str) or not v:
            raise ValueError(f"characterization.{key} is required")
        if not (repo_root / v).resolve().is_file():
            raise ValueError(f"characterization.{key} not found")
    return None


def source_path(config, repo_root):
    return (repo_root / config["characterization"]["source_netlist"]).resolve()

def characterizer_path(config, repo_root):
    return (repo_root / config["characterization"]["script"]).resolve()


def _um(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"geometry must be numeric, got {value!r}")
    if not math.isfinite(float(value)) or value <= 0:
        raise ValueError(f"geometry must be finite positive, got {value!r}")
    # gf180 uses metres with explicit 'u' suffix.
    return ("%du" % int(value)) if float(value).is_integer() else (format(value, "g") + "u")


def _replace(source_text, knob_id, value):
    mp = DEVICE_MAPPINGS[knob_id]
    expected = mp["prefix"] + mp["default_token"] + mp["suffix"]
    replacement = mp["prefix"] + _um(value) + mp["suffix"]
    lines = source_text.splitlines(keepends=True)
    matches = [i for i, l in enumerate(lines) if l.rstrip("\r\n") == expected]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one identity line for {knob_id}; found {len(matches)}")
    i = matches[0]
    ending = "\r\n" if lines[i].endswith("\r\n") else "\n" if lines[i].endswith("\n") else ""
    lines[i] = replacement + ending
    return "".join(lines)


def render_netlist(config, repo_root, source_text, knobs):
    validate_config(config, repo_root)
    if set(knobs) != set(DEVICE_MAPPINGS):
        raise ValueError("gf180 knob set mismatch")
    rendered = source_text
    for kid in DEVICE_MAPPINGS:
        spec = next(k for k in config["search"]["knobs"] if k["id"] == kid)
        if knobs[kid] not in spec.get("values", []):
            raise ValueError(f"{kid} value outside discrete set")
        rendered = _replace(rendered, kid, knobs[kid])
    return rendered


def characterization_command(config, repo_root, netlist, case, vtt_offset_mv, output, pdk_root):
    script = (repo_root / config["characterization"]["script"]).resolve()
    cmd = [sys.executable, str(script),
           "--cell-netlist", str(netlist.resolve()),
           "--case", str(case),
           "--vtt-offset-mv", str(int(vtt_offset_mv)),
           "--output", str(output.resolve())]
    if pdk_root is not None:
        cmd.extend(("--pdk-root", str(Path(pdk_root).expanduser().resolve())))
    return cmd
