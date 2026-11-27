#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
cd "$(dirname "$0")/.."

# Read-eye knobs added to sim/ddr1_device_model.sv:
#   READ_DQS_JITTER_PS : DQS edge excursion relative to nominal tDQSCK
#   READ_DQ_SKEW_PS    : per-bit DQ flight skew (bit 7 is 7x this value)
#   READ_SSO_PS        : extra DQ delay per simultaneously switching bit
#
# J0 is the baseline. J2000 is inside the 10 ns capture window with the current
# fixed phase; S500 and SSO300 are outside it and must fail. This is a
# functional read-eye hook, not a JEDEC/PVT signoff.
python=${PYTHON:-python3}
if ! "$python" -c 'import migen, litex' 2>/dev/null; then
    echo 'Install migen==0.9.2 and litex==2024.12 in the PYTHON environment.' >&2
    exit 1
fi
export PYTHONDONTWRITEBYTECODE=1

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
if ! "$python" generator/emit_ddr1.py "$work" --ck-period-ps 10000; then
    echo "emit_ddr1 failed" >&2
    exit 1
fi
if ! (cd "$work" && yosys -Q -q -p '
    read_verilog ddr1_controller.v
    prep -top ddr1_controller
    scc -expect 0
    check -assert
    write_verilog -noattr ddr1_controller_net.v
'); then
    echo "yosys failed" >&2
    exit 1
fi

run_case() {
    name=$1 expect=$2 jitter=$3 skew=$4 sso=$5
    vvp_file="$work/$name.vvp"
    log="$work/$name.log"
    iverilog -g2012 -I "$work" -s tb_ddr1_loop \
        -Ptb_ddr1_loop.READ_DQS_JITTER_PS="$jitter" \
        -Ptb_ddr1_loop.READ_DQ_SKEW_PS="$skew" \
        -Ptb_ddr1_loop.READ_SSO_PS="$sso" \
        -o "$vvp_file" \
        "$work/ddr1_controller_net.v" "$work/ddr1_top.sv" "$work/ddr1_init.sv" \
        "$work/ddr1_phy.sv" "$work/ddr_edge_out.sv" "$work/ddr_read_capture.sv" \
        "$work/ddr_dqs_train.sv" \
        sim/ddr1_device_model.sv sim/ddr1_timing_checker.sv tb/tb_ddr1_loop.sv
    if vvp "$vvp_file" +READ_CORNER=0 >"$log" 2>&1; then
        got=pass
    else
        got=fail
    fi
    if [ "$got" != "$expect" ]; then
        echo "FAIL read-eye $name expected=$expect got=$got" >&2
        cat "$log" >&2
        return 1
    fi
    echo "READ_EYE_$name $got jitter=$jitter skew=$skew sso=$sso"
}

fail=0
run_case J0     pass 0    0   0   || fail=1
run_case J2000  pass 2000 0   0   || fail=1
run_case S500   fail 0    500 0   || fail=1
run_case SSO300 fail 0    0   300 || fail=1
exit "$fail"
