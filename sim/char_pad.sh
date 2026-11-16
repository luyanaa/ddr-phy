#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# First-pass pad characterization slice. The sizing fixtures are DESIGN
# ASSUMPTIONS; this is not signoff, not PVT, and not ESD qualification.
set -e
cd "$(dirname "$0")/.."

if [ -z "${IN_LIBRELANE_SHELL:-}" ] && [ -f /opt/librelane/shell.nix ]; then
    exec nix-shell /opt/librelane --run "IN_LIBRELANE_SHELL=1 sh sim/char_pad.sh \"$@\""
fi

if [ "$#" -gt 0 ]; then
    BACKENDS="$*"
else
    BACKENDS="gf180mcuD sky130 ihp130"
fi
for b in $BACKENDS; do
    python3 generator/emit_char_pad.py --backend "$b"
done
python3 generator/check_char_pad.py
echo CHAR_PAD_DONE
