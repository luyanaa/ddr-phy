#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
cd "$(dirname "$0")/.."

# Profile-driven generator: emits ddr1_controller.v, timing header, init
# parameter/case fragments and copies the portable RTL into the workdir.
# Corner sweep: 10/11/12 ns CK x tDQSCK in {-max, 0, +max}; the device model
# shifts its DQS launch by the corner, the TB injects the sampled offset.
python=${PYTHON:-python3}
if ! "$python" -c 'import migen, litex' 2>/dev/null; then
    echo 'Install migen==0.9.2 and litex==2024.12 in the PYTHON environment.' >&2
    exit 1
fi
export PYTHONDONTWRITEBYTECODE=1

fail=0
for ck in 10000 11000 12000; do
    work=$(mktemp -d)
    if ! "$python" generator/emit_ddr1.py "$work" --ck-period-ps "$ck"; then
        echo "emit_ddr1 failed at CK=$ck" >&2
        rm -rf "$work"
        exit 1
    fi
    # The raw Migen combinational NBA processes can spin in Icarus on the first
    # write. Lower processes to logic and check the generated controller for SCCs.
    if ! (cd "$work" && yosys -Q -q -p '
        read_verilog ddr1_controller.v
        prep -top ddr1_controller
        scc -expect 0
        check -assert
        write_verilog -noattr ddr1_controller_net.v
    '); then
        echo "yosys failed at CK=$ck" >&2
        rm -rf "$work"
        exit 1
    fi
    if ! iverilog -g2012 -I "$work" -s tb_ddr1_loop -o "$work/ddr1.vvp" \
        "$work/ddr1_controller_net.v" "$work/ddr1_top.sv" "$work/ddr1_init.sv" "$work/ddr1_phy.sv" \
        "$work/ddr_edge_out.sv" "$work/ddr_read_capture.sv" "$work/ddr_dqs_train.sv" \
        sim/ddr1_device_model.sv sim/ddr1_timing_checker.sv tb/tb_ddr1_loop.sv; then
        echo "iverilog failed at CK=$ck" >&2
        rm -rf "$work"
        exit 1
    fi
    for corner in 0 -1 1; do
        if ! vvp "$work/ddr1.vvp" "+READ_CORNER=$corner" >"$work/ddr1.$corner.log" 2>&1; then
            echo "FAIL CK=$ck corner=$corner:" >&2
            cat "$work/ddr1.$corner.log" >&2
            fail=1
        else
            grep -q '^DDR1_LOOP_PASS' "$work/ddr1.$corner.log" || fail=1
            cat "$work/ddr1.$corner.log"
        fi
    done
    if [ "$ck" = 10000 ]; then
        for mode in 0 1; do
            train_vvp="$work/ddr1_train.$mode.vvp"
            if ! iverilog -g2012 -I "$work" -s tb_ddr1_train \
                -Ptb_ddr1_train.FAIL_MODE="$mode" -o "$train_vvp" \
                "$work/ddr1_controller_net.v" "$work/ddr1_top.sv" "$work/ddr1_init.sv" \
                "$work/ddr1_phy.sv" "$work/ddr_edge_out.sv" \
                "$work/ddr_read_capture.sv" "$work/ddr_dqs_train.sv" \
                sim/ddr1_device_model.sv sim/ddr1_timing_checker.sv tb/tb_ddr1_train.sv; then
                echo "iverilog DDR1 training failed at mode=$mode" >&2
                rm -rf "$work"
                exit 1
            fi
            if ! vvp "$train_vvp" >"$work/ddr1_train.$mode.log" 2>&1; then
                echo "FAIL DDR1 training mode=$mode:" >&2
                cat "$work/ddr1_train.$mode.log" >&2
                fail=1
            elif ! grep -q '^DDR1_TRAIN_PASS' "$work/ddr1_train.$mode.log"; then
                echo "FAIL DDR1 training mode=$mode (missing pass marker):" >&2
                cat "$work/ddr1_train.$mode.log" >&2
                fail=1
            else
                cat "$work/ddr1_train.$mode.log"
            fi
        done
    fi
    rm -rf "$work"
done
exit "$fail"
