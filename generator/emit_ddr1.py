# SPDX-License-Identifier: Apache-2.0
"""Generate a process-independent DDR1 x8 PHY bundle and optional LiteDRAM top."""

import argparse
import hashlib
import json
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROFILE = ROOT / "specs/ddr1/mt46v32m8-75e.yaml"
GEOMETRY = dict(bank_bits=2, row_bits=13, col_bits=10, dq_bits=8)
PHY = dict(memtype="DDR", databits=8, dfi_databits=16, nphases=2,
           rdphase=1, wrphase=1, cl=2, cwl=1, read_latency=5, write_latency=1)
BL = 4


def ceil_div(num, den):
    return (num + den - 1) // den


def require_keys(obj, keys, label):
    if not isinstance(obj, dict) or set(obj) != set(keys.split()):
        raise ValueError(f"{label}: expected keys {keys}")


def require_positive_ints(obj, label):
    for key, value in obj.items():
        if type(value) is not int or value <= 0:
            raise ValueError(f"{label}.{key}: expected a positive integer")


def load_profile(text, override):
    spec = yaml.safe_load(text)
    require_keys(spec, "device geometry ck_period_ps powerup_ps dll_lock_ck timing_ps timing_ck", "profile")
    if not isinstance(spec["device"], str) or not spec["device"].strip():
        raise ValueError("device: expected a part name")
    require_keys(spec["geometry"], "bank_bits row_bits col_bits dq_bits", "geometry")
    require_positive_ints(spec["geometry"], "geometry")
    if spec["geometry"] != GEOMETRY:
        raise ValueError("this PHY supports only x8, 2 bank bits, 13 row bits and 10 column bits")
    require_keys(spec["timing_ps"], "RCD RP RAS RC RRD RFC REFI WR MRD DQSCK DQSQ DS DH", "timing_ps")
    require_keys(spec["timing_ck"], "WTR", "timing_ck")
    require_positive_ints(spec["timing_ps"], "timing_ps")
    require_positive_ints(spec["timing_ck"], "timing_ck")
    require_positive_ints({k: spec[k] for k in ("ck_period_ps", "powerup_ps", "dll_lock_ck")}, "profile")
    ck_ps = spec["ck_period_ps"] if override is None else override
    if not 10_000 <= ck_ps <= 12_000 or ck_ps % 4:
        raise ValueError("CK must be 10000–12000 ps and divisible by four for the 90-degree phase")
    if spec["powerup_ps"] < 200_000_000 or spec["dll_lock_ck"] < 200:
        raise ValueError("DDR1 requires at least 200 us power-up and 200 CK DLL settling")
    if spec["timing_ps"]["REFI"] < PHY["nphases"] * ck_ps:
        raise ValueError("tREFI is smaller than one controller clock")
    return spec, ck_ps


def controller_cycles(ps, ck, ck_ps):
    sys_ps = PHY["nphases"] * ck_ps
    # Mixed command phases can shorten a sys-to-sys distance by one CK.
    # CAS→CAS distances do not need this extra margin: both use phase 1.
    return dict(
        **{f"t{name}": ceil_div(ps[name] + ck_ps, sys_ps)
           for name in ("RP", "RCD", "WR", "RFC", "RRD", "RC", "RAS")},
        tREFI=ps["REFI"] // sys_ps,  # An interval maximum, never round it up.
        tWTR=ceil_div(ck["WTR"], PHY["nphases"]), tCCD=ceil_div(BL // 2, PHY["nphases"]),
        tRTP=ceil_div((BL // 2 + 1) * ck_ps, sys_ps),
        tFAW=None, tZQCS=None, nWR=ceil_div(ps["WR"], ck_ps), nCCD=BL // 2,
    )


def controller_verilog(timings, sys_ps):
    # PHY-only generation uses no LiteDRAM or PDK dependencies.
    litedram = ROOT / "third_party/litedram"
    if not (litedram / "litedram/core/controller.py").is_file():
        raise ValueError("initialize third_party/litedram, or use --phy-only")
    sys.path.insert(0, str(litedram))
    from migen import Cat, ClockDomain, Module, Signal
    from migen.fhdl import verilog
    from litedram.common import GeomSettings, PhySettings, TimingSettings
    from litedram.core.controller import ControllerSettings, LiteDRAMController
    from litedram.core.crossbar import LiteDRAMCrossbar

    phy = PhySettings(phytype="DDR1SingleLane", **PHY)
    geom = GeomSettings(GEOMETRY["bank_bits"], GEOMETRY["row_bits"], GEOMETRY["col_bits"])
    top = Module()
    top.clock_domains.cd_sys = ClockDomain("sys")
    controller = LiteDRAMController(
        phy, geom, TimingSettings(**timings), 10**12 / sys_ps,
        ControllerSettings(with_auto_precharge=False),
    )
    crossbar = LiteDRAMCrossbar(controller.interface)
    port = crossbar.get_port()
    top.submodules += controller, crossbar
    ios = {top.cd_sys.clk, top.cd_sys.rst}

    def expose(name, internal, is_input):
        pin = Signal(len(internal), name_override=name)
        ios.add(pin)
        top.comb += internal.eq(pin) if is_input else pin.eq(internal)

    for prefix, endpoint, inputs, outputs in (
        ("cmd", port.cmd, ("valid", "we", "addr"), ("ready",)),
        ("w", port.wdata, ("data", "we"), ("ready",)),
        ("r", port.rdata, (), ("valid", "data")),
    ):
        for field in inputs + outputs:
            expose(f"{prefix}_{field}", getattr(endpoint, field), field in inputs)

    for field in (
        "address", "bank", "ras_n", "cas_n", "we_n", "cs_n", "cke",
        "wrdata", "wrdata_mask", "wrdata_en", "rddata_en", "rddata", "rddata_valid",
    ):
        packed = Cat(*(getattr(p, field) for p in controller.dfi.phases))
        expose(f"dfi_{field}", packed, field in ("rddata", "rddata_valid"))

    return verilog.convert(top, ios=ios, name="ddr1_controller").main_source


def init_sequence(ps, ck_ps, sys_ps, dll_lock_ck):
    # Micron Rev. O power-up steps. All commands use DFI phase 0, so their
    # separation at the pins is an exact multiple of sys_clk.
    mr = (BL.bit_length() - 1) | (PHY["cl"] << 4)
    return [
        ("CKE high",        1, 0b111, 0, 0,        1),
        ("PRECHARGE ALL",   0, 0b010, 0, 1 << 10, ceil_div(ps["RP"], sys_ps)),
        ("EMRS DLL enable", 0, 0b000, 1, 0,        ceil_div(ps["MRD"], sys_ps)),
        ("MRS DLL reset",   0, 0b000, 0, mr | 256, ceil_div(max(ps["MRD"], dll_lock_ck * ck_ps), sys_ps)),
        ("PRECHARGE ALL",   0, 0b010, 0, 1 << 10, ceil_div(ps["RP"], sys_ps)),
        ("AUTO REFRESH",    0, 0b001, 0, 0,        ceil_div(ps["RFC"], sys_ps)),
        ("AUTO REFRESH",    0, 0b001, 0, 0,        ceil_div(ps["RFC"], sys_ps)),
        # This step releases the scheduler, not another phase-0 command.
        # Include one CK of launch latency before starting tMRD.
        ("MRS normal",      0, 0b000, 0, mr,       ceil_div(ps["MRD"] + ck_ps, sys_ps)),
    ]


def generated_files(spec, ck_ps):
    ps, ck = spec["timing_ps"], spec["timing_ck"]
    sys_ps = PHY["nphases"] * ck_ps
    timing = dict(TCK_PS=ck_ps, SYS_PS=sys_ps, CL=PHY["cl"], CWL=PHY["cwl"], BL=BL,
                  T_MRD_CK=ceil_div(ps["MRD"], ck_ps), T_RTP_CK=BL // 2, T_CCD_CK=BL // 2)
    timing.update({f"T_{name}_PS": value for name, value in ps.items()})
    timing.update({f"T_{name}_CK": value for name, value in ck.items()})
    header = ["`ifndef DDR1_TIMING_VH", "`define DDR1_TIMING_VH"]
    header.extend(f"`define DDR1_{name} {value}" for name, value in timing.items())
    header.append("`endif")

    steps = init_sequence(ps, ck_ps, sys_ps, spec["dll_lock_ck"])
    powerup = ceil_div(spec["powerup_ps"], sys_ps)
    max_cycles = max(powerup, *(row[-1] for row in steps))
    params = dict(INIT_STEPS=len(steps), INIT_POWERUP_CYCLES=powerup, INIT_MAX_CYCLES=max_cycles)
    init_params = [f"    localparam integer {name} = {value};" for name, value in params.items()]
    init_steps = [
        f"            STEP_BITS'({i}): {{selected, opcode, bank, address, interval}} = "
        f"{{1'b{1-cs}, 3'b{op:03b}, 2'd{bank}, 13'd{addr}, WAIT_BITS'({cycles})}}; // {name}"
        for i, (name, cs, op, bank, addr, cycles) in enumerate(steps)
    ]
    return {
        "ddr1_timing.vh": "\n".join(header) + "\n",
        "ddr1_init_params.vh": "\n".join(init_params) + "\n",
        "ddr1_init_steps.vh": "\n".join(init_steps) + "\n",
    }, sys_ps, powerup, steps


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--profile", type=Path, default=DEFAULT_PROFILE)
    parser.add_argument("--ck-period-ps", type=int, help="override CK period in the device profile")
    parser.add_argument("--phy-only", action="store_true", help="omit LiteDRAM and the Native port top")
    args = parser.parse_args()
    try:
        source = args.profile.read_bytes()
        spec, ck_ps = load_profile(source, args.ck_period_ps)
        files, sys_ps, powerup, steps = generated_files(spec, ck_ps)
        sv_names = ["ddr1_phy.sv", "ddr1_init.sv", "ddr_edge_out.sv",
                    "ddr_read_capture.sv", "ddr_dqs_train.sv"]
        if not args.phy_only:
            cycles = controller_cycles(spec["timing_ps"], spec["timing_ck"], ck_ps)
            files["ddr1_controller.v"] = controller_verilog(cycles, sys_ps)
            sv_names.append("ddr1_top.sv")
        for name in sv_names:
            files[name] = (ROOT / "rtl" / name).read_text(encoding="utf-8")
    except (OSError, ValueError, ImportError, yaml.YAMLError) as exc:
        parser.error(str(exc))
    contract = dict(
        profile=args.profile.name, profile_sha256=hashlib.sha256(source).hexdigest(),
        device=spec["device"], geometry=GEOMETRY, phy=PHY, bl=BL, ck_ps=ck_ps, sys_ps=sys_ps,
        powerup_sys_cycles=powerup, dll_lock_ck=spec["dll_lock_ck"],
        init=[dict(command=name, cs_n=cs, opcode=op, bank=bank, address=a, interval_sys=gap)
              for name, cs, op, bank, a, gap in steps],
        timing_ps=spec["timing_ps"], timing_ck=spec["timing_ck"],
        top=None if args.phy_only else "ddr1_top",
        files=sorted(files),
    )
    if not args.phy_only:
        contract["controller_timing_sys"] = cycles
    files["ddr1_contract.json"] = json.dumps(contract, indent=2) + "\n"
    args.output.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (args.output / name).write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
