#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# P1-4 ESD stress check on the extracted pad (NOT a qualification).
#
# Applies a 1 A / 10 ns-rise / 100 ns HBM-like current pulse into PAD with
# the output disabled and reports the peak pad voltage. This is a circuit
# stress sanity check, not HBM/TLP/CDM qualification: it has no package
# model, no tester impedance and no failure criteria.
set -e
cd "$(dirname "$0")/.."

GF=$(ls -d "$HOME"/.ciel/ciel/gf180mcu/versions/*/gf180mcuD 2>/dev/null | tail -1)
if [ -z "$GF" ] || [ ! -f reports/gf180_pad_core_pex_sim.spice ]; then
    echo "SKIP gf180_esd_stress: PDK or PEX netlist missing"
    exit 0
fi
export PDK_ROOT="$GF"
export PDK="$GF"

DECK=sim/char/gf180mcuD/esd_stress.spice
mkdir -p sim/char/gf180mcuD
cat > "$DECK" <<EOF
* ESD stress: 1 A / 100 ns pulse into PAD, output disabled. NOT a qualification.
.lib "\$PDK_ROOT/libs.tech/ngspice/sm141064.ngspice" typical
.lib "\$PDK_ROOT/libs.tech/ngspice/sm141064.ngspice" diode_typical
.include "\$PDK_ROOT/libs.tech/ngspice/design.ngspice"
.include "/grid/ddr-phy/reports/gf180_pad_core_pex_sim.spice"
.options rshunt=1e9 gmin=1e-8 reltol=1e-2 itl4=100
X_PAD GP GN PAD VSSIO VDDIO IN OUT OE_N PU_OK gf180_pad_core_flat
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
.meas tran v_pad_min MIN v(PAD) FROM=10n TO=400n
.end
EOF
ngspice -b "$DECK" > reports/gf180_esd_stress.log 2>&1
grep -E 'v_pad_max|v_pad_min' reports/gf180_esd_stress.log | head -2
echo GF180_ESD_STRESS_DONE
