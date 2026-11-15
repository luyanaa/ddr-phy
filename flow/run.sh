#!/bin/sh
# LibreLane harden of sdr_phy.
#
#   flow/run.sh [pdk-spec]
#
# Specs: sky130, ihp130, ics55, gf180-as-7t3v3.
# gf180 uses the 3.3 V AS library. The 5 V stdcell library is not a spec:
# it is the wrong voltage for this PHY, and the 3.3 V cells are an overlay
# that has to be composed under ./pdks first.
set -e
cd "$(dirname "$0")/.."

if [ -z "${IN_LIBRELANE_SHELL:-}" ]; then
    unset ALL_PROXY all_proxy
    exec nix-shell /opt/librelane --run "IN_LIBRELANE_SHELL=1 sh flow/run.sh $*"
fi

unset ALL_PROXY all_proxy
SPEC=${1:-sky130}

ciel_root() {
    fam=$1
    base=$HOME/.ciel/ciel/$fam/versions
    ver=$(ls -1 "$base" | sort | tail -1)
    echo "$base/$ver"
}

case "$SPEC" in
sky130)
    PDK_NAME=sky130A
    SCL=sky130_fd_sc_hd
    PDKROOT=$(ciel_root sky130)
    ;;
ihp130)
    PDK_NAME=ihp-sg13g2
    SCL=sg13g2_stdcell
    PDKROOT=$(ciel_root ihp-sg13)
    ;;
ics55)
    PDK_NAME=icsprout55-pdk
    SCL=ics55_LLSC_H7CL
    PDKROOT=/grid
    ;;
gf180-as-7t3v3)
    PDK_NAME=gf180mcuD
    SCL=gf180mcu_as_sc_mcu7t3v3
    PDKROOT=$PWD/pdks
    if [ ! -d "$PDKROOT/gf180mcuD/libs.ref/$SCL" ]; then
        echo "gf180-as-7t3v3 needs a 3.3 V PDK view at $PDKROOT/gf180mcuD" >&2
        echo "The foundry 5 V stdcell library is not a substitute." >&2
        exit 2
    fi
    ;;
*)
    echo "unknown pdk-spec '$SPEC'" >&2
    exit 2
    ;;
esac

echo "LibreLane sdr_phy  pdk=$PDK_NAME  scl=$SCL  root=$PDKROOT"
rm -rf "flow/runs/$SPEC"
librelane flow/config.librelane.json \
    --manual-pdk \
    --pdk-root "$PDKROOT" \
    --pdk "$PDK_NAME" \
    --scl "$SCL" \
    --run-tag "$SPEC" \
    --ef-save-views-to "results/$SPEC/sdr_phy"
