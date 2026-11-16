#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# GF180 pad first-pass PVT sweep. DESIGN ASSUMPTION, not signoff.
set -e
cd "$(dirname "$0")/.."

if [ -z "${IN_LIBRELANE_SHELL:-}" ] && [ -f /opt/librelane/shell.nix ]; then
    exec nix-shell /opt/librelane --run "IN_LIBRELANE_SHELL=1 sh sim/char_pvt.sh"
fi

for ct in "tt 27" "ss 125" "ff -40"; do
    set -- $ct
    python3 generator/emit_char_pad.py --backend gf180mcuD \
        --corner "$1" --temp "$2" --tag "_$1_$2"
done
for v in 2.97 3.63; do
    python3 generator/emit_char_pad.py --backend gf180mcuD \
        --corner tt --temp 27 --vdd "$v" --vddio "$v" --tag "_tt_27_v$v"
done
python3 generator/check_char_pad.py
echo CHAR_PVT_DONE
