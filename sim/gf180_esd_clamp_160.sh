#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# 160 um ggNMOS clamp: generate + DRC + LVS + Magic PEX + end-to-end ESD.
#
# This is the clamp the pad ring instances (the pad cell itself is limited to
# 80 um by the die-level Poly2 density rule).
set -e
cd "$(dirname "$0")/.."

GF=$(ls -d "$HOME"/.ciel/ciel/gf180mcu/versions/*/gf180mcuD 2>/dev/null | tail -1)
if [ -z "$GF" ]; then echo "SKIP gf180_esd_clamp_160: PDK not found"; exit 0; fi
PDKROOT=$(dirname "$GF")
export PDK_ROOT="$PDKROOT"

NAME=gf180_esd_clamp_160
ESD_NF=40 ESD_W=4.0 ESD_NAME=$NAME klayout -b -r generator/emit_esd_clamp.py

nix-shell /opt/librelane --run "\
  cd '$GF/libs.tech/klayout/tech/drc' && \
  klayout -b -r gf180mcu.drc \
    -rd input=/grid/ddr-phy/sch/pads/gf180mcuD/pcell/$NAME.gds \
    -rd report=/grid/ddr-phy/reports/${NAME}_drc.lyrdb \
    -rd topcell=$NAME -rd variant=gf180mcuD \
    -rd run_mode=flat -rd threads=4" \
  > reports/${NAME}_drc.log 2>&1
bad=$(grep -E "^.*:   '" reports/${NAME}_drc.log \
      | grep -vE "DCF\.1b|PL\.8|M[0-9]\.4|MT\.3" | wc -l)
if [ "$bad" -ne 0 ]; then
    echo "FAIL $NAME DRC ($bad non-density rule groups)"
    grep -E "^.*:   '" reports/${NAME}_drc.log | head -10
    exit 1
fi
echo "PASS $NAME DRC (geometry clean; die-level density only)"

cat > /tmp/${NAME}_sch.spice <<SP
.SUBCKT $NAME PAD VSSIO
MCLAMP PAD VSSIO VSSIO VSSIO nfet_03v3 W=160u L=0.28u
.ENDS
SP
( cd "$GF/libs.tech/klayout/tech/lvs" && \
  klayout -b -r gf180mcu.lvs \
    -rd input=/grid/ddr-phy/sch/pads/gf180mcuD/pcell/$NAME.gds \
    -rd schematic=/tmp/${NAME}_sch.spice \
    -rd target_netlist=/grid/ddr-phy/reports/${NAME}_extracted.spice \
    -rd report=/grid/ddr-phy/reports/${NAME}_lvs.lyrdb \
    -rd topcell=$NAME -rd run_mode=flat -rd metal_top=11K \
    -rd metal_level=5LM -rd check_ports=false -rd combine=true -rd thr=2 \
    > /grid/ddr-phy/reports/${NAME}_lvs.log 2>&1 )
grep -q 'Netlists match' reports/${NAME}_lvs.log
echo "PASS $NAME LVS (Netlists match)"

# Magic flat RC-PEX for the end-to-end ESD run.
PEXDIR=/tmp/opencode/${NAME}_pex
mkdir -p "$PEXDIR"
cat > "$PEXDIR/rc.tcl" <<RC
set PDK_ROOT $PDKROOT
source \$PDK_ROOT/gf180mcuD/libs.tech/magic/gf180mcuD.magicrc
RC
( cd "$PEXDIR" && PDK_ROOT="$PDKROOT" magic -d X11 -noconsole \
    -rcfile "$PEXDIR/rc.tcl" <<MAG > "$PEXDIR/magic.log" 2>&1
gds read /grid/ddr-phy/sch/pads/gf180mcuD/pcell/$NAME.gds
load $NAME
flatten ${NAME}_flat
load ${NAME}_flat
extract do resistance
extract
ext2spice extresist on
ext2spice -o /grid/ddr-phy/reports/${NAME}_pex.spice
quit -noprompt
MAG
)
test -s reports/${NAME}_pex.spice
echo "PASS $NAME Magic RC-PEX ($(grep -c '^R' reports/${NAME}_pex.spice) R elements)"

python3 - <<'PY'
import re
src = 'reports/gf180_esd_clamp_160_pex.spice'
dst = '/tmp/opencode/clamp160_sim.spice'
node_rx = re.compile(r'^[A-Za-z_][A-Za-z0-9_$]*[./#][A-Za-z0-9_$./#]*$')
num_rx = re.compile(r'^[+-]?[0-9]')
out = []
for line in open(src):
    if line.startswith('*') or (line.startswith('.option') and 'scale' in line):
        continue
    if line.startswith('.'):
        continue
    toks = line.rstrip('\n').split()
    if not toks:
        continue
    for i, t in enumerate(toks):
        if i == 0 or '=' in t or num_rx.match(t):
            continue
        if any(c in t for c in './#') and node_rx.match(t):
            toks[i] = re.sub(r'[./#]', '_', t)
    _m = next((t for t in toks if t.startswith(('nfet_03v3', 'pfet_03v3'))), None)
    if _m is not None and toks[0].startswith('X'):
        for i, t in enumerate(toks):
            for key, sc in (("w=", 5e-9), ("l=", 5e-9), ("ad=", 25e-18),
                            ("as=", 25e-18), ("pd=", 5e-9), ("ps=", 5e-9)):
                if t.startswith(key):
                    try:
                        toks[i] = "%s%g" % (key, float(t[len(key):]) * sc)
                    except ValueError:
                        pass
    out.append(' '.join(toks))
open(dst, 'w').write(
    ".SUBCKT gf180_esd_clamp_160_flat PAD VSSIO\n" + "\n".join(out) + "\n.ENDS\n")
PY

cat > /tmp/opencode/esd160.spice <<EOS
* End-to-end ESD: pad macro PEX + 160 um clamp PEX (NOT a qualification).
.lib "\$PDK_ROOT/libs.tech/ngspice/sm141064.ngspice" typical
.lib "\$PDK_ROOT/libs.tech/ngspice/sm141064.ngspice" diode_typical
.include "\$PDK_ROOT/libs.tech/ngspice/design.ngspice"
.include "/grid/ddr-phy/reports/gf180_pad_core_pex_sim.spice"
.include "/tmp/opencode/clamp160_sim.spice"
.options rshunt=1e9 gmin=1e-8 reltol=1e-2 itl4=100
X_PAD GP GN PAD VSSIO VDDIO IN OUT OE_N PU_OK gf180_pad_core_flat
X_C160 PAD VSSIO gf180_esd_clamp_160_flat
VDDIO VDDIO 0 3.3
VSSIO VSSIO 0 0
VPU PU_OK 0 0
VOE OE_N 0 3.3
VOUT OUT 0 0
RGP GP VSSIO 1G
RGN GN VSSIO 1G
RIN IN VSSIO 1G
I_ESD 0 PAD PULSE(0 1 10n 10n 1n 100n 1)
.tran 1n 400n
.meas tran v_pad_max MAX v(PAD) FROM=10n TO=400n
.end
EOS
PDK_ROOT="$GF" PDK="$GF" ngspice -b /tmp/opencode/esd160.spice \
  > reports/gf180_esd_stress_160.log 2>&1
grep -E 'v_pad_max' reports/gf180_esd_stress_160.log
echo GF180_ESD_CLAMP_160_DONE
