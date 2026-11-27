#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Single DQ geometry, official macro DRC and LVS, and Magic RC extraction.
set -eu
cd "$(dirname "$0")/.."

case $# in
    0) mkdir -p results/ihp130; out=$(mktemp -d results/ihp130/sstl2-dq.XXXXXXXX) ;;
    1) out=$1; mkdir -p "$(dirname "$out")"; mkdir "$out" ;;
    *) echo "usage: $0 [fresh-results-directory]" >&2; exit 2 ;;
esac
out=$(cd "$out" && pwd)
printf 'IHP SG13G2 DQ artifacts: %s\n' "$out"

recent_klayout() {
    "$1" -b -v 2>/dev/null | awk '/KLayout / {
        split($2, p, ".");
        if (p[1]>0 || p[2]>30 || (p[2]==30 && p[3]>=12)) ok=1;
    } END {exit !ok}'
}
if [ -z "${KLAYOUT:-}" ]; then
    for candidate in klayout /nix/store/*-klayout-*/bin/klayout; do
        if recent_klayout "$candidate"; then KLAYOUT=$candidate; break; fi
    done
fi
if [ -z "${KLAYOUT:-}" ] || ! recent_klayout "$KLAYOUT"; then
    echo "Set KLAYOUT to KLayout >= 0.30.12" >&2
    exit 2
fi
IHP_PDK=${IHP_PDK:-$HOME/.ciel/ciel/ihp-sg13/versions/89d42ee6d2fd9b50b86a1aada6fee6673c3e6008/ihp-sg13g2}
IHP_PDK=$(cd "$IHP_PDK" && pwd)
IHP_LAYOUT_OUT=$out
export IHP_PDK IHP_LAYOUT_OUT
tech=$IHP_PDK/libs.tech
top=ihp130_sstl2_dq
gds=$out/sstl2_dq.gds

run() {
    name=$1; shift
    echo "RUN $name"
    if ! "$@" >"$out/$name.log" 2>&1; then
        tail -n 35 "$out/$name.log" >&2
        return 1
    fi
}
{
    "$KLAYOUT" -b -v
    magic --version
    printf 'PDK=%s\n' "$IHP_PDK"
} >"$out/tools.log"
run generator "$KLAYOUT" -b -r generator/ihp130_dq_layout.py
test -s "$gds"

# The main deck checks the cell's FEOL, BEOL, geometry, pins, etc. Standalone
# macro DRC does not claim chip-context density, antenna, or ESD qualification.
run drc "$KLAYOUT" -b -r "$tech/klayout/tech/drc/ihp-sg13g2.drc" \
    -rd "input=$gds" -rd "report=$out/sstl2_dq_drc.lyrdb" \
    -rd "topcell=$top" -rd tables=main -rd run_mode=flat -rd threads=2
run lvs "$KLAYOUT" -b -r "$tech/klayout/tech/lvs/sg13g2.lvs" \
    -rd "input=$gds" -rd "schematic=$out/sstl2_dq_lvs.spice" \
    -rd "target_netlist=$out/sstl2_dq_extracted.cir" -rd "report=$out/sstl2_dq_lvs.lvsdb" \
    -rd "topcell=$top" -rd run_mode=flat -rd disable_tap_extraction=true -rd combine_devices=true

python3 - "$out/sstl2_dq_drc.lyrdb" <<'PY' | tee "$out/drc_markers.log"
import sys
from collections import Counter
from xml.etree import ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
items = root.find("items")
if root.tag != "report-database" or items is None:
    raise SystemExit("Missing official KLayout DRC markers section")
counts = Counter()
for item in items.findall("item"):
    counts[item.findtext("category")] += int(item.findtext("multiplicity", "1"))
for name, count in counts.most_common():
    print(name, count)
print(f"DRC markers: {sum(counts.values())}")
PY
grep -qx 'DRC markers: 0' "$out/drc_markers.log"
test -s "$out/sstl2_dq_lvs.lvsdb"
test -s "$out/sstl2_dq_extracted.cir"
if ! grep -Fq 'Congratulations! Netlists match.' "$out/lvs.log"; then
    tail -n 35 "$out/lvs.log" >&2
    exit 1
fi
echo "LVS: netlists match"

# extresist needs a live layout window; no interactive display is required.
(
    cd "$out"
    xvfb-run -a magic -d X11 -noconsole -rcfile "$tech/magic/ihp-sg13g2.magicrc" <<'TCL'
gds read "$env(IHP_LAYOUT_OUT)/sstl2_dq_rc.gds"
load ihp130_sstl2_dq
select top cell
extract style ngspice()
extresist threshold 0
extresist minresist 0
extresist mindelay 0
extresist simplify off
extract do resistance
extract all
ext2spice scale off
ext2spice cthresh 0
ext2spice rthresh 0
ext2spice extresist on
ext2spice subcircuit top on
ext2spice hierarchy on
ext2spice short resistor
ext2spice -o sstl2_dq_rc.spice
quit -noprompt
TCL
) >"$out/magic_rc.log" 2>&1
python3 generator/pex_ihp130_dq.py "$out"
printf 'GDS, DRC/LVS reports, and RC netlists: %s\n' "$out"
