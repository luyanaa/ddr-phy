#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run a bounded process-backend search using the common characterization API.

A backend adapter (contract version 1) supplies validate_config, source_path,
characterizer_path, render_netlist, and characterization_command. It owns
process-specific device geometry; this runner owns deterministic discrete
search, report interpretation, ranking, and persistable evidence. Characterizer
electrical limits remain authoritative.

Exit status: 0 = development winner and holdout pass; 2 = no feasible design
or holdout rejection; 1 = setup/adapter/simulator/protocol error. A valid
characterizer report with exit 1 is an electrical result, not a simulator
error. Evidence is written for all completed searches, including rejection.
"""

import argparse
import hashlib
import importlib.util
import itertools
import json
import math
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

import yaml


ROOT = Path(__file__).resolve().parent.parent
ADAPTER_CONTRACT_VERSION = 1
CASE_ID = re.compile(r"^[A-Za-z0-9_-]+$")
DELAY_MEASURES = ("rx_rise", "rx_fall", "tx_rise", "tx_fall")
CURRENT_MEASURES = ("rx_io_bias", "rx_core_bias", "tx_io_peak")
LOG_TAIL_CHARS = 6000
CASE_TIMEOUT_S = 1900


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _load_adapter(path):
    spec = importlib.util.spec_from_file_location("ddr1_process_backend", path)
    if spec is None or spec.loader is None:
        raise ValueError(f"cannot load process backend adapter: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if getattr(module, "CONTRACT_VERSION", None) != ADAPTER_CONTRACT_VERSION:
        raise ValueError("backend adapter must implement contract version 1")
    required = (
        "validate_config", "source_path", "characterizer_path", "render_netlist",
        "characterization_command",
    )
    missing = [name for name in required if not callable(getattr(module, name, None))]
    if missing:
        raise ValueError(f"backend adapter missing contract functions: {missing}")
    return module


def _load_config(path):
    with path.open(encoding="utf-8") as source:
        config = yaml.safe_load(source)
    if not isinstance(config, dict):
        raise ValueError("backend YAML must contain a mapping")
    return config


def _number(value, where):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{where} must be a number")
    if not math.isfinite(float(value)):
        raise ValueError(f"{where} must be finite")
    return value


def _search_space(config):
    search = config.get("search")
    if not isinstance(search, dict):
        raise ValueError("backend search must be a mapping")
    knobs = search.get("knobs")
    if not isinstance(knobs, list) or not knobs:
        raise ValueError("backend search.knobs must be a non-empty list")

    ids = set()
    choices = []
    defaults = {}
    for item in knobs:
        if not isinstance(item, dict):
            raise ValueError("each search knob must be a mapping")
        knob_id = item.get("id")
        if not isinstance(knob_id, str) or not knob_id or knob_id in ids:
            raise ValueError("search knob ids must be unique non-empty strings")
        ids.add(knob_id)
        values = item.get("values")
        if not isinstance(values, list) or not values:
            raise ValueError(f"{knob_id}.values must be a non-empty discrete list")
        values = [_number(value, f"{knob_id}.values") for value in values]
        if len(set(values)) != len(values):
            raise ValueError(f"{knob_id}.values contains duplicates")
        default = _number(item.get("default"), f"{knob_id}.default")
        if default not in values:
            raise ValueError(f"{knob_id}.default must be in its discrete values")
        choices.append((knob_id, values))
        defaults[knob_id] = default

    max_trials = search.get("max_trials")
    if isinstance(max_trials, bool) or not isinstance(max_trials, int) or max_trials < 1:
        raise ValueError("search.max_trials must be a positive integer")
    return choices, defaults, max_trials


def _case_specs(config):
    search = config["search"]
    development = search.get("development")
    holdout = search.get("holdout")
    if not isinstance(development, list) or not development:
        raise ValueError("search.development must be a non-empty list")
    if not isinstance(holdout, dict):
        raise ValueError("search.holdout must be one case mapping")

    def normalize(item, where):
        if not isinstance(item, dict):
            raise ValueError(f"{where} must be a mapping")
        case_id = item.get("id")
        case = item.get("case")
        offset = item.get("vtt_offset_mv")
        if not isinstance(case_id, str) or not CASE_ID.fullmatch(case_id):
            raise ValueError(f"{where}.id must contain only letters, digits, '_' or '-'")
        if not isinstance(case, str) or not case:
            raise ValueError(f"{where}.case is required")
        if isinstance(offset, bool) or not isinstance(offset, int):
            raise ValueError(f"{where}.vtt_offset_mv must be an integer")
        return {"id": case_id, "case": case, "vtt_offset_mv": offset}

    dev = [normalize(item, f"search.development[{i}]") for i, item in enumerate(development)]
    holdout_spec = normalize(holdout, "search.holdout")
    all_ids = [item["id"] for item in dev + [holdout_spec]]
    if len(set(all_ids)) != len(all_ids):
        raise ValueError("development and holdout case ids must be unique")
    if holdout_spec["vtt_offset_mv"] in {case["vtt_offset_mv"] for case in dev}:
        raise ValueError("holdout must use a termination offset not used in development")
    return dev, holdout_spec


def _trial_grid(choices, defaults, limit):
    combinations = list(itertools.product(*(values for _, values in choices)))
    baseline = tuple(defaults[knob_id] for knob_id, _ in choices)
    if baseline not in combinations:
        raise ValueError("baseline knob combination is not in the discrete grid")
    ordered = [baseline] + [combination for combination in combinations if combination != baseline]
    return [
        {knob_id: value for (knob_id, _), value in zip(choices, combination)}
        for combination in ordered[:limit]
    ], len(combinations)


def _report_case(report, case_name):
    if not isinstance(report, dict):
        raise ValueError("characterizer output must be a JSON object")
    cases = report.get("cases")
    if not isinstance(cases, dict) or case_name not in cases:
        raise ValueError(f"characterizer report is missing requested case {case_name!r}")
    case_result = cases[case_name]
    if not isinstance(case_result, dict):
        raise ValueError("characterizer case result must be a JSON object")
    if not isinstance(case_result.get("measurements_si"), dict):
        raise ValueError("characterizer case is missing measurements_si")
    if not isinstance(case_result.get("failures"), dict):
        raise ValueError("characterizer case is missing failures")
    return case_result


def _text_tail(value):
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="replace")
    return str(value or "")[-LOG_TAIL_CHARS:]


def _run_case(backend, config, repo_root, netlist, case_spec, pdk_root, workdir):
    output = workdir / f"{case_spec['id']}.json"
    command = backend.characterization_command(
        config, repo_root, netlist, case_spec["case"], case_spec["vtt_offset_mv"], output, pdk_root
    )
    result = {
        "id": case_spec["id"],
        "case": case_spec["case"],
        "vtt_offset_mv": case_spec["vtt_offset_mv"],
    }
    try:
        completed = subprocess.run(
            command,
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=CASE_TIMEOUT_S,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        result.update(
            status="simulator_error",
            exit_code=None,
            error=f"characterizer timed out after {CASE_TIMEOUT_S}s",
            log_tail=_text_tail(error.stdout) + _text_tail(error.stderr),
        )
        return result
    except OSError as error:
        result.update(status="simulator_error", exit_code=None, error=str(error))
        return result

    result["exit_code"] = completed.returncode
    if not output.is_file():
        result.update(
            status="simulator_error",
            error="characterizer produced no JSON report",
            log_tail=_text_tail(completed.stdout + "\n" + completed.stderr),
        )
        return result
    try:
        report = json.loads(output.read_text(encoding="utf-8"))
        raw_case = _report_case(report, case_spec["case"])
    except (OSError, json.JSONDecodeError, ValueError) as error:
        result.update(
            status="simulator_error",
            error=f"invalid characterizer report: {error}",
            log_tail=_text_tail(completed.stdout + "\n" + completed.stderr),
        )
        return result

    result["report"] = report
    if completed.returncode not in (0, 1):
        result.update(
            status="simulator_error",
            error=f"characterizer exited {completed.returncode} despite writing a report",
            log_tail=_text_tail(completed.stdout + "\n" + completed.stderr),
        )
        return result
    # char_ihp130_sstl2.py returns 1 when a completed electrical report has
    # hard-limit failures; only a well-formed report makes exit 1 electrical.
    result["status"] = "electrical_fail" if raw_case["failures"] else "electrical_pass"
    return result


def _finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _normalize_failure(failure):
    actual = failure.get("actual")
    bounds = failure.get("limit")
    if not _finite(actual) or not isinstance(bounds, list) or len(bounds) != 2:
        return None
    lo, hi = bounds
    if not _finite(lo) or not _finite(hi) or hi < lo:
        return None
    actual = float(actual)
    lo = float(lo)
    hi = float(hi)
    violation = max(lo - actual, actual - hi, 0.0)
    if violation == 0:
        return 0.0
    scale = hi - lo
    if scale == 0:
        scale = max(abs(lo), abs(hi), abs(actual), 1e-30)
    return violation / scale


def _trial_summary(trial, case_results):
    failures = []
    normalized = []
    no_cross = False
    simulator_error = False
    delays = {}
    currents = {}

    for result in case_results:
        if result["status"] == "simulator_error":
            simulator_error = True
            continue
        raw_case = result["report"]["cases"][result["case"]]
        measurements = raw_case["measurements_si"]
        for key in DELAY_MEASURES:
            value = measurements.get(key)
            if _finite(value):
                delays.setdefault(key, []).append(float(value))
        for key in CURRENT_MEASURES:
            value = measurements.get(key)
            if _finite(value):
                currents.setdefault(key, []).append(abs(float(value)))
        for key, failure in raw_case["failures"].items():
            entry = {"case_id": result["id"], "measurement": key, **failure}
            failures.append(entry)
            if failure.get("reason") == "no_target_crossing" or failure.get("actual") is None:
                no_cross = True
                normalized.append(None)
            else:
                normalized.append(_normalize_failure(failure))

    numeric = [value for value in normalized if _finite(value)]
    worst = max(numeric) if numeric else None
    max_delay = max((value for values in delays.values() for value in values), default=None)
    peak_current = max((value for values in currents.values() for value in values), default=None)
    if simulator_error:
        classification = "simulator_error"
    elif no_cross:
        classification = "no_cross"
    elif failures:
        classification = "infeasible"
    else:
        classification = "feasible"

    trial.update(
        classification=classification,
        hard_limits_pass=(classification == "feasible"),
        worst_normalized_violation=worst,
        normalized_violation_unavailable_for_no_cross=no_cross,
        failures=failures,
        metrics={
            "max_rx_tx_propagation_s": max_delay,
            "max_abs_bias_or_tx_io_peak_current_a": peak_current,
            "per_measurement_max_delay_s": {
                key: max(values) for key, values in delays.items()
            },
            "per_measurement_max_abs_current_a": {
                key: max(values) for key, values in currents.items()
            },
        },
    )
    return trial


def _rank_key(trial):
    feasible = trial["classification"] == "feasible"
    violation = trial["worst_normalized_violation"]
    # Passing every authoritative hard limit dominates every rejected design.
    # Among infeasible designs, a no-cross has unbounded/unavailable severity.
    failure_rank = 0.0 if feasible else (float("inf") if violation is None else violation)
    metrics = trial["metrics"]
    delay = metrics["max_rx_tx_propagation_s"]
    current = metrics["max_abs_bias_or_tx_io_peak_current_a"]
    return (
        0 if feasible else 1,
        failure_rank,
        float("inf") if delay is None else delay,
        float("inf") if current is None else current,
        trial["trial_index"],
    )


def _write_result(path, result):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(result, indent=2, sort_keys=True, allow_nan=False) + "\n"
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(data, encoding="utf-8")
    temporary.replace(path)


def _evaluate(backend, config, repo_root, source_text, knobs, case_specs, pdk_root, trial_index):
    trial = {"trial_id": f"trial-{trial_index:02d}", "trial_index": trial_index, "knobs": knobs, "cases": {}}
    netlist_text = backend.render_netlist(config, repo_root, source_text, knobs)
    with tempfile.TemporaryDirectory(prefix="ddr1-tune-") as temp_dir:
        workdir = Path(temp_dir)
        netlist = workdir / "cell.spice"
        netlist.write_text(netlist_text, encoding="utf-8")
        for case_spec in case_specs:
            trial["cases"][case_spec["id"]] = _run_case(
                backend, config, repo_root, netlist, case_spec, pdk_root, workdir
            )
    return _trial_summary(trial, list(trial["cases"].values()))


def _parser():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "The backend adapter is process-specific; it must provide contract v1. "
            "The selected characterizer remains the only source of hard electrical limits. "
            "Exit 1 from the IHP characterizer is accepted only with a valid JSON electrical report."
        ),
    )
    parser.add_argument("--backend", required=True, help="process-backend YAML, e.g. specs/ddr1/ihp130-sstl2.yaml")
    parser.add_argument("--output", required=True, type=Path, help="persistable JSON evidence output")
    parser.add_argument("--sampler", choices=("grid",), default="grid", help="deterministic Cartesian grid (default)")
    parser.add_argument("--max-trials", type=int, help="cap configured grid trials; baseline always runs first")
    parser.add_argument("--pdk-root", help="optional PDK root forwarded to the registered process characterizer")
    return parser


def main(argv=None):
    args = _parser().parse_args(argv)
    backend_spec = Path(args.backend).expanduser()
    if not backend_spec.is_absolute():
        backend_spec = (Path.cwd() / backend_spec).resolve()
    output = args.output.expanduser()
    if not output.is_absolute():
        output = (Path.cwd() / output).resolve()

    try:
        config = _load_config(backend_spec)
        choices, defaults, configured_limit = _search_space(config)
        development, holdout_spec = _case_specs(config)
        limit = configured_limit if args.max_trials is None else args.max_trials
        if isinstance(limit, bool) or not isinstance(limit, int) or limit < 1 or limit > configured_limit:
            raise ValueError(f"--max-trials must be between 1 and configured max_trials ({configured_limit})")
        grid, grid_size = _trial_grid(choices, defaults, limit)
        adapter_rel = config.get("adapter")
        if not isinstance(adapter_rel, str) or not adapter_rel:
            raise ValueError("backend adapter path is required")
        adapter_path = (ROOT / adapter_rel).resolve()
        backend = _load_adapter(adapter_path)
        backend.validate_config(config, ROOT)
        source_path = backend.source_path(config, ROOT)
        source_text = source_path.read_text(encoding="utf-8")
        config_sha = _sha256(backend_spec)
        source_sha = _sha256(source_path)
        adapter_sha = _sha256(adapter_path)
        characterizer_path = (ROOT / config["characterization"]["script"]).resolve()
        characterizer_sha = _sha256(characterizer_path)
    except (OSError, ValueError, KeyError, TypeError, yaml.YAMLError) as error:
        print(f"tune_ddr1: {error}", file=sys.stderr)
        return 1

    result = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "status": "running",
        "signoff": False,
        "method": {
            "sampler": "deterministic_grid",
            "description": (
                "Enumerate the configured discrete Cartesian grid with the source baseline first. "
                "Require all characterizer hard limits at every development case; then minimize "
                "maximum measured RX/TX propagation, using maximum absolute measured bias/TX-I/O "
                "current as a tie-breaker. Run the holdout only for the development winner."
            ),
            "grid_size": grid_size,
            "trials_requested": len(grid),
            "development_cases": development,
            "holdout_case": holdout_spec,
            "limits_source": "the registered characterizer JSON failures; no thresholds are duplicated here",
        },
        "provenance": {
            "backend_spec": str(backend_spec),
            "backend_spec_sha256": config_sha,
            "adapter": str(adapter_path),
            "adapter_sha256": adapter_sha,
            "source_netlist": str(source_path),
            "source_netlist_sha256": source_sha,
            "characterizer": str(characterizer_path),
            "characterizer_sha256": characterizer_sha,
            "pdk_root_override": str(Path(args.pdk_root).expanduser().resolve()) if args.pdk_root else None,
        },
        "reproduction": {
            "command": shlex.join([
                sys.executable,
                str(ROOT / "generator/tune_ddr1.py"),
                "--backend", str(backend_spec),
                "--output", str(output),
                "--sampler", args.sampler,
            ] + (["--max-trials", str(args.max_trials)] if args.max_trials is not None else [])
              + (["--pdk-root", str(Path(args.pdk_root).expanduser().resolve())] if args.pdk_root else [])),
            "python": sys.version.split()[0],
            "sampler": args.sampler,
        },
        "trials": [],
        "selection": {"ranked_trial_ids": [], "winner_trial_id": None},
        "winner": None,
        "holdout": {"status": "not_run_no_feasible_candidate"},
        "recommended": None,
        "exit_code": None,
    }

    for index, knobs in enumerate(grid, start=1):
        try:
            trial = _evaluate(backend, config, ROOT, source_text, knobs, development, args.pdk_root, index)
        except (OSError, ValueError, KeyError, TypeError) as error:
            trial = {
                "trial_id": f"trial-{index:02d}",
                "trial_index": index,
                "knobs": knobs,
                "classification": "simulator_error",
                "hard_limits_pass": False,
                "worst_normalized_violation": None,
                "normalized_violation_unavailable_for_no_cross": False,
                "failures": [],
                "metrics": {
                    "max_rx_tx_propagation_s": None,
                    "max_abs_bias_or_tx_io_peak_current_a": None,
                    "per_measurement_max_delay_s": {},
                    "per_measurement_max_abs_current_a": {},
                },
                "error": f"backend/search failure: {error}",
                "cases": {},
            }
        result["trials"].append(trial)

    ranked = sorted(result["trials"], key=_rank_key)
    result["selection"]["ranked_trial_ids"] = [trial["trial_id"] for trial in ranked]
    feasible = [trial for trial in result["trials"] if trial["classification"] == "feasible"]
    winner_trial = min(feasible, key=_rank_key) if feasible else None
    all_trials_simulated = all(trial["classification"] != "simulator_error" for trial in result["trials"])

    holdout_pass = False
    if winner_trial is not None:
        result["selection"]["winner_trial_id"] = winner_trial["trial_id"]
        try:
            holdout_trial = _evaluate(
                backend, config, ROOT, source_text, winner_trial["knobs"],
                [holdout_spec], args.pdk_root, winner_trial["trial_index"],
            )
            holdout_case = holdout_trial["cases"][holdout_spec["id"]]
            holdout_pass = holdout_trial["classification"] == "feasible"
            result["holdout"] = {
                "status": "pass" if holdout_pass else holdout_trial["classification"],
                "knobs": winner_trial["knobs"],
                "case_result": holdout_case,
                "metrics": holdout_trial["metrics"],
                "failures": holdout_trial["failures"],
            }
        except (OSError, ValueError, KeyError, TypeError) as error:
            result["holdout"] = {
                "status": "simulator_error",
                "knobs": winner_trial["knobs"],
                "error": f"backend/search failure: {error}",
            }
        result["winner"] = {
            "trial_id": winner_trial["trial_id"],
            "knobs": winner_trial["knobs"],
            "development_metrics": winner_trial["metrics"],
            "development_classification": winner_trial["classification"],
            "holdout_passed": holdout_pass,
            "recommended": bool(holdout_pass and all_trials_simulated),
        }
        if holdout_pass and all_trials_simulated:
            result["recommended"] = {
                "trial_id": winner_trial["trial_id"],
                "knobs": winner_trial["knobs"],
                "metrics": winner_trial["metrics"],
                "holdout_case_id": holdout_spec["id"],
            }

    if not all_trials_simulated or result["holdout"].get("status") == "simulator_error":
        result["status"] = "simulator_error"
        exit_code = 1
    elif winner_trial is None:
        result["status"] = "no_feasible_candidate"
        exit_code = 2
    elif not holdout_pass:
        result["status"] = "holdout_failed"
        exit_code = 2
    else:
        result["status"] = "pass"
        exit_code = 0
    result["exit_code"] = exit_code
    _write_result(output, result)

    print(f"DDR1 search: {result['status']}; trials={len(result['trials'])}; evidence={output}", flush=True)
    if result["recommended"] is not None:
        print(f"recommended: {result['recommended']['trial_id']} knobs={result['recommended']['knobs']}", flush=True)
    elif result["winner"] is not None:
        print(f"no recommendation: winner failed holdout or search was incomplete", flush=True)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
