#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate per-corner cornerparams_<corner>.inc for ics55 ngspice flat include.

Why this exists: the foundry hspice wrapper (ICsprout_55LLULP1225_V1p1_hsp.lib)
uses nested .lib sections whose inner sections re-.INC the subckt/.mdl files.
ngspice cannot parse that (subckt redefinition -> fatal exit), so the char
engine cannot select corners through the wrapper. Instead we extract the
per-corner .PARAM delta values from the wrapper sections here and emit flat
cornerparams_<corner>.inc files that the ics55 char profile includes via
extra_model_lines().

Method / caveats:
- Parse one ".LIB <corner> ... .ENDL" section per file; collect name=value.
- Values are literals or '(expr)*corner_ratio' strings; corner_ratio is 1.0 in
  every foundry corner, so the delta is the parenthesised constant.
- agauss()/gauss() statistical (mismatch) terms are forced to 0: this is a
  corner simulation, not Monte Carlo, and mos_total's mismatch params are
  meaningless here.
- Parameter set = union of (the original tt skeleton params) and (every wrapper
  delta for the device families this witness design uses). The hand-written tt
  skeleton MISSED drsh_re_hrpo_3t / ddw_re_hrpo_3t / dtoxp_pm2p5_lp, which only
  matters once corners are non-zero, so we take the union rather than trusting
  the skeleton.
- fnsp/snfs (mixed) corners have NO dedicated res/dio sections in the foundry
  wrapper (only tt/ff/ss/mc exist); we pair them with res_ss/dio_ss as the
  nearest slow-interconnect approximation and document that approximation.

NOT a foundry file. evaluation/research only; signoff=False always.
"""
import re
from pathlib import Path

FAMILIES = ["nm2p5_lp", "pm2p5_lp", "re_hrpo_3t",
            "dio_2p5_np_pw_lp", "dio_2p5_pp_nw_lp"]
CORNERS = ["tt", "ff", "ss", "fnsp", "snfp"]
# mos corner -> (mos_section, res_section, dio_section)
SECMAP = {
    "tt":   ("tt",   "res_tt", "dio_tt"),
    "ff":   ("ff",   "res_ff", "dio_ff"),
    "ss":   ("ss",   "res_ss", "dio_ss"),
    "fnsp": ("fnsp", "res_ss", "dio_ss"),  # no fnsp res/dio section; nearest
    "snfp": ("snfp", "res_ss", "dio_ss"),
}


def parse_section(path, section):
    """Return dict of param->raw-value-string for one .LIB <section> block."""
    txt = Path(path).read_text()
    m = re.search(r'^\s*\.lib\s+' + re.escape(section) + r'\b(.*?)^\s*\.endl',
                  txt, re.S | re.M | re.I)
    if not m:
        return {}
    body = m.group(1)
    body = re.sub(r'^\s*\.inc\b.*$', '', body, flags=re.M | re.I)  # nested .INC
    body = re.sub(r'\n\s*\+', ' ', body)                            # continuations
    body = re.sub(r'\.param', ' ', body, flags=re.I)
    params = {}
    for mm in re.finditer(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*('[^']*'|[^\s]+)", body):
        params[mm.group(1)] = mm.group(2)
    return params


def eval_value(raw, corner_ratio=1.0):
    s = raw.strip()
    if s.startswith("'") and s.endswith("'"):
        s = s[1:-1]
    if 'agauss' in s.lower() or 'gauss' in s.lower():
        return 0.0
    s = s.replace('corner_ratio', repr(corner_ratio))
    if not re.fullmatch(r'[0-9eE\.\+\-\*/\(\) ]+', s):
        raise ValueError("unparseable expr: %r" % raw)
    return eval(s, {"__builtins__": {}}, {})


def load_skeleton(path):
    t = Path(path).read_text()
    t = re.sub(r'\n\s*\+', ' ', t)
    names = set(re.findall(r'([A-Za-z_][A-Za-z0-9_]*)\s*=', t))
    names.discard("prelayout"); names.discard("sigma_mis_r")
    return names


def corner_values(corner, w1, w2):
    ms, rs, ds = SECMAP[corner]
    vals = {}
    for sec, file in ((ms, w1), (rs, w2), (ds, w2)):
        for k, raw in parse_section(file, sec).items():
            try:
                vals[k] = eval_value(raw)
            except ValueError:
                pass
    return vals


def main():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pdk-root", type=Path, required=True,
                    help="ics55 PDK root containing libs.tech/spice/foundry/ngspice")
    ap.add_argument("--out-dir", type=Path,
                    help="where to write cornerparams_<corner>.inc; default: the ngspice model dir")
    args = ap.parse_args()
    ng = args.pdk_root / "libs.tech/spice/foundry/ngspice"
    w1, w2 = ng / "model_wrapper1_hsp.lib", ng / "model_wrapper2_hsp.lib"
    skeleton = load_skeleton(ng / "cornerparams.inc")
    union = set(skeleton)
    for c in CORNERS:
        for k in corner_values(c, w1, w2):
            if any(f in k for f in FAMILIES):
                union.add(k)
    union = sorted(union)
    outdir = args.out_dir or ng
    for c in CORNERS:
        vals = corner_values(c, w1, w2)
        lines = [
            "* %s corner offsets extracted from foundry hspice wrapper." % c,
            "* generated for ngspice flat-include evaluation use; NOT a foundry file.",
            "* values = wrapper delta at corner_ratio=1; mismatch/statistical terms forced 0.",
            ".param prelayout=1  sigma_mis_r=0",
        ]
        row = []
        for name in union:
            row.append("%s=%s" % (name, format(vals.get(name, 0.0), ".6g")))
            if len(row) == 2:
                lines.append("+" + "  ".join(row)); row = []
        if row:
            lines.append("+" + "  ".join(row))
        out = outdir / ("cornerparams_%s.inc" % c)
        out.write_text("\n".join(lines) + "\n")
        print("wrote %s params:%d" % (out, len(union)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
