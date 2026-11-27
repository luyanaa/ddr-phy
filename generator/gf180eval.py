#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""gf180mcu BSIM4 model flattener for Xyce.

gf180 organizes models as nested .lib sections in one file (sm141064.spice):
  - top-level PVT corners typical/ff/ss/fs/sf set scaling .param values
    (nfet_06v0_cgdo=1/0.9/1.1/0.93/1.07 etc).
  - device sections nfet_06v0_t etc contain the binned .model; the model is the
    SAME across corners, corner dependence is purely the scaling .param values.
  - model params use SPICE quoted-expr values 'expr' referencing those .param
    symbols, e.g. vth0='0.67314+nfet_06v0_vth0', cgdo='1e-10*nfet_06v0_cgdo'.

This module resolves the corner scaling symbols and evaluates the quoted exprs
to constants, emitting a flat single .model Xyce can consume. At the nominal
(typical) corner the scalings are 1 and offsets 0, so the evaluation is exact.
Noise params use conditional exprs on fnoicor; fnoicor defaults to 0.
"""

import re


def parse_corner_params(lines, corner):
    """Collect .param values inside the top-level .lib <corner> section."""
    start = None
    for i, l in enumerate(lines):
        if re.match(rf"\.lib {corner}\s*$", l):
            start = i
            break
    if start is None:
        return {}
    params = {}
    for l in lines[start + 1:]:
        if re.match(r"\.endl\b", l):
            break
        m = re.match(r"\.param (\w+)\s*=\s*(.+)", l)
        if m:
            params[m.group(1)] = m.group(2).strip()
    return params


def parse_noise_params(lines):
    """Noise corner params (noia/noib/noic) defined with conditional exprs.

    These live in the noise_corner section as .param with '(fnoicor==0)*A+...'
    forms. We resolve them at fnoicor=0.
    """
    params = {}
    for i, l in enumerate(lines):
        m = re.match(r"\.param (\w+)\s*=\s*'(.+)'", l)
        if m and ("noia" in m.group(1) or "noib" in m.group(1) or "noic" in m.group(1)):
            params[m.group(1)] = m.group(2)
    return params


def find_model_bins(lines, modelname):
    """Return list of (start_idx, binidx, type) for .model <name>.<binidx>."""
    hits = []
    for i, l in enumerate(lines):
        m = re.match(rf"\.model {re.escape(modelname)}\.(\d+)\s+(nmos|pmos)", l)
        if m:
            hits.append((i, int(m.group(1)), m.group(2)))
    return hits


def extract_body(lines, start):
    """Capture continuation lines of a .model block until next directive."""
    body = [lines[start]]
    for l in lines[start + 1:]:
        if re.match(r"\.(model|subckt|lib|endl|ends|end)\b", l):
            break
        if l.strip():
            body.append(l)
    return body


def select_bin_by_l(bins, lines, l_m):
    """Pick bin whose [lmin,lmax) contains device length l_m (meters)."""
    best = None
    for (start, idx, typ) in bins:
        body = extract_body(lines, start)
        lmin = lmax = None
        for l in body:
            mm = re.search(r"\blmin\s*=\s*([0-9.eE+-]+)", l)
            if mm: lmin = float(mm.group(1))
            mm = re.search(r"\blmax\s*=\s*([0-9.eE+-]+)", l)
            if mm: lmax = float(mm.group(1))
        if lmin is not None and lmax is not None:
            if lmin - 1e-12 <= l_m < lmax - 1e-12 or abs(l_m - lmin) < 1e-9:
                return (start, idx, typ, lmin, lmax)
            # gf180 bins: .1 is short-l, .0 is long-l; boundary at exactly lmax of short
            if abs(l_m - lmax) < 1e-9:
                best = (start, idx, typ, lmin, lmax)
    return best


def _safe_eval(expr, symtab):
    """Evaluate a SPICE-ish arithmetic expr with a symbol table. Returns float or None."""
    e = expr.strip().strip("'")
    # resolve conditional (fnoicor==0)*A+(fnoicor==1)*B with fnoicor=0
    # substitute symbols
    def repl(m):
        s = m.group(0)
        if s in symtab:
            return repr(symtab[s])
        if s in ("e",):
            return s  # part of exponent, leave
        if re.fullmatch(r"[a-zA-Z_]\w*", s):
            # bare function or unknown symbol
            if s in ("sqrt", "exp", "log", "abs"):
                return s
            return "0"  # unknown param default 0 (conservative)
        return s
    # tokenize: replace identifiers but not those in scientific notation
    # first protect scientific notation by temporarily marking
    e2 = re.sub(r"(\d)e([+-]\d)", r"\1E\2", e)  # normalize exponent
    e2 = re.sub(r"\b([a-zA-Z_]\w*)\b", repl, e2)
    # handle conditional equality: replace (x==0) with truthiness using fnoicor
    # simple approach: evaluate with fnoicor in symtab
    try:
        val = eval(e2, {"__builtins__": {}}, {"sqrt": __import__("math").sqrt,
                                               "exp": __import__("math").exp,
                                               "abs": abs})
        return float(val)
    except Exception:
        return None


def flatten_model(lines, modelname, l_m, corner, new_name, extra_symtab=None):
    """End-to-end gf180 flatten. Returns (model_text, info)."""
    corner_params = parse_corner_params(lines, corner)
    noise_params = parse_noise_params(lines)

    # build numeric symbol table for this corner
    symtab = {"fnoicor": 0.0}
    # corner scalings: numeric values
    for k, v in corner_params.items():
        try:
            symtab[k] = float(v)
        except ValueError:
            pass  # leave non-numeric for later
    if extra_symtab:
        symtab.update(extra_symtab)

    bins = find_model_bins(lines, modelname)
    if not bins:
        return None, {"error": f"model {modelname} not found"}
    sel = select_bin_by_l(bins, lines, l_m)
    if sel is None:
        # fallback: use the long-l bin (.0)
        sel = (bins[0][0], bins[0][1], bins[0][2], None, None)
    start, binidx, typ, lmin, lmax = sel
    body = extract_body(lines, start)

    out = [f".model {new_name} {typ}"]
    nresid = 0
    nparam = 0
    for l in body[1:]:
        ls = l.strip()
        if not ls.startswith("+"):
            continue
        m = re.match(r"\+\s*(\w+)\s*=\s*(.+)", ls)
        if not m:
            # bare or malformed; drop binning lines
            continue
        name, val = m.group(1), m.group(2).strip()
        if name in ("lmin", "lmax", "wmin", "wmax", "binunit"):
            continue
        if name == "version":
            val = "4.8"
        if val.startswith("'"):
            # need corner params that may themselves be exprs (noise). resolve.
            # first inject noise param constant values into symtab
            for nk, nexpr in noise_params.items():
                if nk not in symtab:
                    nv = _safe_eval(nexpr, symtab)
                    if nv is not None:
                        symtab[nk] = nv
            rv = _safe_eval(val, symtab)
            if rv is None:
                nresid += 1
                out.append(f"+ {name} = {val}")
                continue
            val = format(rv, ".6g")
        out.append(f"+ {name} = {val}")
        nparam += 1

    info = {"bin": binidx, "l_range": (lmin, lmax), "residual": nresid,
            "nparams": nparam, "corner": corner, "model": modelname}
    return "\n".join(out) + "\n", info
