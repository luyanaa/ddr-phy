#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# GF180 pad core: generate, full DRC, KLayout LVS, Magic RC-PEX.
# The pad core is output stage + series R + ESD diodes + receiver. OE logic,
# pre-driver, guard ring, pad ring and signoff are NOT included.
set -e
cd "$(dirname "$0")/.."

GF=$(ls -d "$HOME"/.ciel/ciel/gf180mcu/versions/*/gf180mcuD 2>/dev/null | tail -1)
PDK_ROOT=$(dirname "$GF")
export PDK_ROOT
if [ -z "$GF" ] || [ ! -f "$GF/libs.tech/klayout/tech/drc/gf180mcu.drc" ]; then
    echo "SKIP gf180_pad_layout: local gf180mcuD PDK not found"
    exit 0
fi

klayout -b -r generator/gf180_pad_layout.py

# Full DRC. The system KLayout 0.30.0 deck fails on the dnwell connectivity
# paths; KLayout 0.30.7 from the LibreLane shell runs the whole deck.
nix-shell /opt/librelane --run "\
  cd '$GF/libs.tech/klayout/tech/drc' && \
  klayout -b -r gf180mcu.drc \
    -rd input=/grid/ddr-phy/sch/pads/gf180mcuD/pcell/gf180_pad_core.gds \
    -rd report=/grid/ddr-phy/reports/gf180_pad_core_drc.lyrdb \
    -rd topcell=gf180_pad_core -rd variant=gf180mcuD \
    -rd run_mode=flat -rd threads=4" \
  > reports/gf180_pad_core_drc.log 2>&1
grep -q 'DRC RESULT: SUCCESS (0 violations)' reports/gf180_pad_core_drc.log
echo "PASS gf180_pad_core full DRC (0 violations)"

# LVS: layout extracted netlist vs the emitted schematic.
(
  cd "$GF/libs.tech/klayout/tech/lvs"
  klayout -b -r gf180mcu.lvs \
    -rd input=/grid/ddr-phy/sch/pads/gf180mcuD/pcell/gf180_pad_core.gds \
    -rd schematic=/grid/ddr-phy/sch/pads/gf180mcuD/pcell/gf180_pad_core.spice \
    -rd target_netlist=/grid/ddr-phy/reports/gf180_pad_core_extracted.spice \
    -rd report=/grid/ddr-phy/reports/gf180_pad_core_lvs.lyrdb \
    -rd topcell=gf180_pad_core -rd run_mode=flat \
    -rd metal_top=11K -rd metal_level=5LM \
    -rd check_ports=false -rd combine=true -rd thr=2
) > reports/gf180_pad_core_lvs.log 2>&1
grep -q 'Netlists match' reports/gf180_pad_core_lvs.log
echo "PASS gf180_pad_core LVS"

# Magic RC-PEX. This needs an X display for Magic's layout window; the
# extresist step is a window command and does not run with -dnull.
if [ -z "${DISPLAY:-}" ]; then
    echo "SKIP gf180_pad_core PEX: DISPLAY is not set (Magic extresist needs a window)"
    echo GF180_PAD_LAYOUT_DONE
    exit 0
fi

PEXDIR=reports/pex
mkdir -p "$PEXDIR"
rm -f reports/gf180_pad_core_pex.spice
rm -f "$PEXDIR"/*.ext "$PEXDIR"/*.res.ext "$PEXDIR"/*.mag
cat > /tmp/opencode/gf180_pad_magicrc <<EOF
set PDK_ROOT $PDK_ROOT
source \$PDK_ROOT/gf180mcuD/libs.tech/magic/gf180mcuD.magicrc
EOF
(
  cd "$PEXDIR"
  PDK_ROOT="$PDK_ROOT" magic -d X11 -noconsole -rcfile /tmp/opencode/gf180_pad_magicrc <<EOF
gds read /grid/ddr-phy/sch/pads/gf180mcuD/pcell/gf180_pad_core.gds
load gf180_pad_core
flatten gf180_pad_core_flat
load gf180_pad_core_flat
extresist threshold 0
extresist minres 0
extresist mindelay 0
extract do resistance
extract
ext2spice extresist on
ext2spice subcircuits descend on
ext2spice hierarchy on
ext2spice -o /grid/ddr-phy/reports/gf180_pad_core_pex.spice
quit -noprompt
EOF
) > "$PEXDIR/gf180_pad_core_pex.log" 2>&1

test -s reports/gf180_pad_core_pex.spice
grep -q '^R' reports/gf180_pad_core_pex.spice
echo "PASS gf180_pad_core Magic RC-PEX ($(grep -c '^R' reports/gf180_pad_core_pex.spice) R elements)"

# Node names from Magic contain '.', '/', '#'; ngspice needs them sanitized.
# The pack's only ppolyf_u instance is replaced by its extracted 22.2727 ohm
# value because the PDK poly model is not usable stand-alone.
python3 - <<'PY'
import re
src = 'reports/gf180_pad_core_pex.spice'
dst = 'reports/gf180_pad_core_pex_sim.spice'
node_rx = re.compile(r'^[A-Za-z_][A-Za-z0-9_$]*[./#][A-Za-z0-9_$./#]*$')
num_rx = re.compile(r'^[+-]?[0-9]')
out = []
for line in open(src):
    if line.startswith('*') or line.startswith('.'):
        out.append(line)
        continue
    toks = line.rstrip('\n').split()
    if len(toks) >= 5 and toks[4] == 'ppolyf_u':
        # the resistor terminals need the same '.'/'/'/'#' sanitizing as
        # every other node, otherwise R_SERIES lands on a nonexistent node
        # and the output stage is left disconnected from PAD.
        n1 = re.sub(r'[./#]', '_', toks[1])
        n2 = re.sub(r'[./#]', '_', toks[2])
        out.append('R_SERIES %s %s 22.272727\n' % (n1, n2))
        continue
    for i, t in enumerate(toks):
        if i == 0 or '=' in t or num_rx.match(t):
            continue
        if any(c in t for c in './#') and node_rx.match(t):
            toks[i] = re.sub(r'[./#]', '_', t)
    # Magic writes diode area/pj in layout units (scale = 5 nm); ngspice does
    # not apply .option scale to these two instance parameters, so convert
    # them to SI here (800000 * 25e-18 = 20p, 3600 * 5e-9 = 18u).
    if len(toks) >= 4 and toks[3].startswith('diode'):
        for i, t in enumerate(toks):
            if t.startswith('area='):
                toks[i] = 'area=%g' % (float(t[5:]) * 25e-18)
            elif t.startswith('pj='):
                toks[i] = 'pj=%g' % (float(t[3:]) * 5e-9)
    out.append(' '.join(toks) + '\n')
open(dst, 'w').writelines(out)
PY
grep -q '^R_SERIES' reports/gf180_pad_core_pex_sim.spice
echo "PASS gf180_pad_core PEX node sanitize + series-R substitution"

if command -v ngspice >/dev/null 2>&1; then
  TMP=$(mktemp -d /tmp/opencode/padpex.XXXX)
  printf '* local\n' > "$TMP/.spiceinit"
  cat > "$TMP/pex_tb.spice" <<EOF
.lib "$GF/libs.tech/ngspice/sm141064.ngspice" typical
.lib "$GF/libs.tech/ngspice/sm141064.ngspice" diode_typical
.include "$GF/libs.tech/ngspice/design.ngspice"
.include "/grid/ddr-phy/reports/gf180_pad_core_pex_sim.spice"
.options rshunt=1e12 gmin=1e-10
XTOP GP GN PAD VSSIO VDDIO IN OUT OE_N PU_OK gf180_pad_core_flat
VDDIO VDDIO 0 3.3
VSSIO VSSIO 0 0
VPAD PAD 0 1.65
VOUT OUT 0 0
VOE OE_N 0 3.3
VPU PU_OK 0 0
* GP/GN are driven by the on-cell pre-driver and IN is the receiver output:
* high-value loads keep the nodes defined without overriding the drivers.
RGP GP 0 1G
RGN GN 0 1G
RIN IN 0 1G
.op
.end
EOF
  ( cd "$TMP" && timeout 300 env PDK_ROOT="$GF" ngspice -b pex_tb.spice > pex.log 2>&1 )
  test -f "$TMP/pex.log"
  if grep -q 'singular matrix' "$TMP/pex.log"; then
      echo "FAIL gf180_pad_core PEX ngspice .op (singular matrix)"
      exit 1
  fi
  if grep -q 'Error' "$TMP/pex.log"; then
      echo "FAIL gf180_pad_core PEX ngspice .op (Error)"
      exit 1
  fi
  echo "PASS gf180_pad_core PEX ngspice .op"
fi

echo GF180_PAD_LAYOUT_DONE
