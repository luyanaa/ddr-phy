#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# P0-3: capability report + pad adapter contract tests.
set -e
cd "$(dirname "$0")/.."

if [ -z "${IN_LIBRELANE_SHELL:-}" ] && [ -f /opt/librelane/shell.nix ]; then
    exec nix-shell /opt/librelane --run "IN_LIBRELANE_SHELL=1 sh sim/pad.sh"
fi

mkdir -p sim/obj
python3 generator/check_capabilities.py

iverilog -g2012 -o sim/obj/tb_pad_adapter \
    rtl/phy_io_adapter.sv sim/pad_cell_generic.sv tb/tb_pad_adapter.sv
vvp sim/obj/tb_pad_adapter

# An unsupported backend must fail loudly, not silently wire core cells
# to a pad. Capture the output and require the FATAL message.
iverilog -g2012 -Ptb_pad_adapter.BACKEND=1 -o sim/obj/tb_pad_bad \
    rtl/phy_io_adapter.sv sim/pad_cell_generic.sv tb/tb_pad_adapter.sv
if vvp sim/obj/tb_pad_bad 2>&1 | grep -q 'FATAL phy_io_adapter'; then
    echo "PASS unsupported backend fails loudly"
else
    echo "FAIL unsupported backend did not fail loudly" >&2
    exit 1
fi

echo PAD_DONE
