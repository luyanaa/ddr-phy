#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""IHP SG13G2 adapter for the process-neutral DDR1 discrete-search runner.

Adapter contract version 1:
  * validate_config(config, repo_root)
  * source_path(config, repo_root)
  * characterizer_path(config, repo_root)
  * render_netlist(config, repo_root, source_text, knobs)
  * characterization_command(config, repo_root, netlist, case, vtt_offset_mv,
                             output, pdk_root)

All process-specific device mappings and exact source identities belong here;
the runner knows only this contract and the characterization report shape.
"""

from pathlib import Path
import math
import sys


CONTRACT_VERSION = 1

# These are the only geometry controls exposed by this bounded search.  Keep
# exact device identity and unsearched parameters here so source drift fails
# closed instead of silently tuning a different element.
DEVICE_MAPPINGS = {
    "xrdriver_w_um": {
        "prefix": "XRDRIVER DRIVER PAD VSSIO rppd w=",
        "suffix": " l=0.6u",
        "default_token": "8u",
        "default_value": 8,
    },
    "xrbias_l_um": {
        "prefix": "XRBIAS VDDIO BIAS VSSIO rhigh w=1.2u l=",
        "suffix": "",
        "default_token": "13u",
        "default_value": 13,
    },
}


def validate_config(config, repo_root):
    if config.get("schema_version") != CONTRACT_VERSION:
        raise ValueError("unsupported DDR1 backend schema_version")
    if config.get("adapter") != "generator/ddr1_ihp130_backend.py":
        raise ValueError("IHP backend adapter path must match this adapter")

    search = config.get("search", {})
    knobs = search.get("knobs", [])
    by_id = {knob.get("id"): knob for knob in knobs}
    if len(by_id) != len(knobs) or set(by_id) != set(DEVICE_MAPPINGS):
        raise ValueError("IHP search knobs must map exactly to XRDRIVER and XRBIAS")
    for knob_id, mapping in DEVICE_MAPPINGS.items():
        knob = by_id[knob_id]
        if knob.get("default") != mapping["default_value"]:
            raise ValueError(f"{knob_id}: default does not match source identity")

    char = config.get("characterization", {})
    for key in ("script", "source_netlist"):
        value = char.get(key)
        if not isinstance(value, str) or not value:
            raise ValueError(f"characterization.{key} is required")
        path = (repo_root / value).resolve()
        if not path.is_file():
            raise ValueError(f"characterization.{key} not found: {path}")
    return None


def source_path(config, repo_root):
    return (repo_root / config["characterization"]["source_netlist"]).resolve()

def characterizer_path(config, repo_root):
    return (repo_root / config["characterization"]["script"]).resolve()


def _spice_um(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"geometry value must be numeric, got {value!r}")
    if not math.isfinite(float(value)) or value <= 0:
        raise ValueError(f"geometry value must be finite and positive, got {value!r}")
    text = str(int(value)) if float(value).is_integer() else format(value, "g")
    return text + "u"


def _replace_exact_device_line(source_text, knob_id, value):
    mapping = DEVICE_MAPPINGS[knob_id]
    expected = mapping["prefix"] + mapping["default_token"] + mapping["suffix"]
    replacement = mapping["prefix"] + _spice_um(value) + mapping["suffix"]

    lines = source_text.splitlines(keepends=True)
    matches = [index for index, line in enumerate(lines) if line.rstrip("\r\n") == expected]
    if len(matches) != 1:
        raise ValueError(
            f"expected exactly one identity line for {knob_id}; found {len(matches)}"
        )
    index = matches[0]
    # Recheck the declared baseline on every render: a stale/misconfigured
    # default must never cause a different source geometry to be overwritten.
    if mapping["default_token"] != _spice_um(mapping["default_value"]):
        raise ValueError(f"internal default token mismatch for {knob_id}")
    ending = "\r\n" if lines[index].endswith("\r\n") else "\n" if lines[index].endswith("\n") else ""
    lines[index] = replacement + ending
    return "".join(lines)


def render_netlist(config, repo_root, source_text, knobs):
    validate_config(config, repo_root)
    expected_ids = set(DEVICE_MAPPINGS)
    if set(knobs) != expected_ids:
        raise ValueError(f"IHP knob set mismatch: expected {sorted(expected_ids)}")

    # Exact, one-line replacement keeps the immutable source untouched and
    # guards both target multiplicity and the baseline identity before tuning.
    rendered = source_text
    for knob_id in DEVICE_MAPPINGS:
        knob_spec = next(k for k in config["search"]["knobs"] if k["id"] == knob_id)
        if knobs[knob_id] not in knob_spec.get("values", []):
            raise ValueError(f"{knob_id} value is outside its configured discrete set")
        rendered = _replace_exact_device_line(rendered, knob_id, knobs[knob_id])
    return rendered


def characterization_command(config, repo_root, netlist, case, vtt_offset_mv,
                              output, pdk_root):
    script = (repo_root / config["characterization"]["script"]).resolve()
    command = [
        sys.executable,
        str(script),
        "--cell-netlist", str(netlist.resolve()),
        "--case", str(case),
        "--vtt-offset-mv", str(int(vtt_offset_mv)),
        "--output", str(output.resolve()),
    ]
    if pdk_root is not None:
        command.extend(("--pdk-root", str(Path(pdk_root).expanduser().resolve())))
    return command
