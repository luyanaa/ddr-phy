#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""BSIM4 bin selection + nominal-corner expression evaluation for Xyce.

Xyce does NOT perform automatic BSIM4 binning (the lmin/lmax/wmin/wmax 2D
geometry table that ngspice/hspice use to pick .model.X per device). This
module:
  1. parses a binned .pm3 model file into per-bin parameter blocks,
  2. selects the unique bin for a given device (w, l),
  3. evaluates the instance-dependent {...} expressions to constants at the
     NOMINAL corner (mc_mm_switch=0 -> every mismatch/geometry term vanishes),
     yielding a flat single .model card Xyce can consume.

Nominal-corner exactness (verified on sky130 nfet/pfet g5v0d10v5 pm3):
  - 352 mismatch exprs `{c + MC_MM_SWITCH*AGAUSS(...)*(slope/sqrt(l*w*mult))}`
    collapse to the constant `c` because MC_MM_SWITCH=0 multiplies the whole
    second term. No sqrt(l*w) survives outside that scope (0 counterexamples).
  - 704 `{0 + <diff>}` well-proximity/process-variation corrections collapse to
    0 because the diff variables are 0 at the nominal corner (they exist only
    for Monte-Carlo injection).
So the evaluated model is NOT an approximation at tt; it is exactly the
nominal device the foundry extracted. signoff=false stands for other reasons
(device operated below rated voltage, version 4.5->4.8 remap).
"""

import re
import math


def _num(s):
    return float(s)


class Bin:
    __slots__ = ("name", "lmin", "lmax", "wmin", "wmax", "body")

    def __init__(self, name, lmin, lmax, wmin, wmax, body):
        self.name = name
        self.lmin = lmin
        self.lmax = lmax
        self.wmin = wmin
        self.wmax = wmax
        self.body = body  # raw param text (continuation lines) for this bin

    def covers(self, w, l):
        # ngspice uses lmin<=l<lmax, wmin<=w<wmax with floating tolerance
        eps = 1e-12
        return (self.lmin - eps) <= l < (self.lmax - eps) and \
               (self.wmin - eps) <= w < (self.wmax - eps)


def parse_bins(pm3_text):
    """Parse a binned pm3 into a list of Bin. Returns (bins, model_base).

    model_base is the shared prefix e.g. 'sky130_fd_pr__nfet_g5v0d10v5__model'.
    Only blocks matching '.model <base>.<N> nmos' (or pmos) are treated as bins.
    """
    blocks = re.split(r"(?m)^(?=\.model )", pm3_text)
    bins = []
    base = None
    for b in blocks:
        m = re.match(r"\.model\s+(\S+)\s+(nmos|pmos)\b", b)
        if not m:
            continue
        full = m.group(1)
        # split trailing .N bin index
        bm = re.match(r"(.+)\.(\d+)$", full)
        if not bm:
            continue
        this_base = bm.group(1)
        if base is None:
            base = this_base
        def gp(p):
            mm = re.search(r"\b" + p + r"\s*=\s*([0-9.eE+-]+)", b)
            return _num(mm.group(1)) if mm else None
        lmin, lmax = gp("lmin"), gp("lmax")
        wmin, wmax = gp("wmin"), gp("wmax")
        if None in (lmin, lmax, wmin, wmax):
            continue
        bins.append(Bin(full, lmin, lmax, wmin, wmax, b))
    return bins, base


def select_bin(bins, w, l):
    """Return the Bin covering device geometry (w, l) in meters, or None.

    Bins are non-overlapping and tile the w/l plane; exactly one should match.
    Floating tolerance: values on a boundary belong to the upper bin
    (matches ngspice lmin<=x<lmax).
    """
    for b in bins:
        if b.covers(w, l):
            return b
    return None


def eval_nominal(body):
    """Evaluate a bin body at the nominal corner.

    - Drops MC_MM_SWITCH mismatch terms entirely (they vanish).
    - Collapses `{const + diff}` / `{const}` braces to the constant.
    - Rewrites version -> 4.8 (Xyce input), preserves BINUNIT and geometry terms,
      drops value-less parasitic stubs (rds/rd/rs bare names; rdsmod=0 unused).
    Returns (flat_model_lines, n_residual_braces, n_empty).
    """
    out_lines = []
    residual = 0
    empty = 0

    def eval_value(val):
        """Reduce one parameter RHS to a constant string, or None if impossible."""
        v = val.strip()
        # braced expression
        if v.startswith("{"):
            inner = v.strip()[1:-1] if v.rstrip().endswith("}") else v[1:]
            # mismatch term present? -> keep only the leading constant before the first '+MC_MM'
            if "MC_MM_SWITCH" in inner:
                lead = inner.split("+MC_MM_SWITCH")[0].split("+ MC_MM_SWITCH")[0].strip()
                return lead
            # pure diff correction: {0+<something>_diff} -> 0 at nominal
            if re.fullmatch(r"0\s*\+\s*\w+_diff", inner):
                return "0"
            # leading constant + diff form {c+diff}
            m = re.fullmatch(r"([0-9.eE+-]+)\s*\+\s*\w+_diff", inner)
            if m:
                return m.group(1)
            # single constant in braces
            if re.fullmatch(r"[0-9.eE+-]+", inner):
                return inner
            return None
        return v

    assignment = re.compile(r"\s*([A-Za-z_]\w*)\s*=\s*(\{[^{}]*\}|[^\s={}]+)")
    for raw in body.splitlines():
        line = raw.strip()
        if line.startswith(".model"):
            out_lines.append(line)
        elif line.startswith("+"):
            params = line[1:].strip()
            if params.lower() in {"rds", "rd", "rs"}:
                empty += 1
                continue
            pos = 0
            while pos < len(params):
                match = assignment.match(params, pos)
                if not match:
                    raise ValueError(f"Unparsed BSIM4 parameters: {params[pos:]!r}")
                name, value = match.groups()
                pos = match.end()
                if name.lower() == "version":
                    value = "4.8"
                elif value.startswith("{"):
                    nominal = eval_value(value)
                    if nominal is None:
                        residual += 1
                    else:
                        value = nominal
                out_lines.append(f"+ {name} = {value}")

    return out_lines, residual, empty


def build_flat_model(pm3_text, w, l, mult=1, new_name=None):
    """End-to-end: parse bins, select for (w,l), evaluate nominal, return flat model text.

    Returns (model_text, info) where info has bin name, residual/empty counts, coverage.
    w, l in meters.
    """
    bins, base = parse_bins(pm3_text)
    b = select_bin(bins, w, l)
    if b is None:
        # find nearest by center distance for diagnostics
        return None, {"error": "no bin covers geometry", "w": w, "l": l,
                      "nbins": len(bins)}
    lines, residual, empty = eval_nominal(b.body)
    name = new_name or (b.name.replace(base, base + "_flat"))
    # rewrite the .model line name
    out = []
    for ln in lines:
        if ln.startswith(".model"):
            toks = ln.split()
            # keep type token (nmos/pmos)
            typ = toks[2] if len(toks) > 2 else "nmos"
            out.append(f".model {name} {typ}")
        else:
            out.append(ln)
    return "\n".join(out) + "\n", {
        "bin": b.name, "residual_braces": residual, "empty_dropped": empty,
        "l_range": (b.lmin, b.lmax), "w_range": (b.wmin, b.wmax),
    }
