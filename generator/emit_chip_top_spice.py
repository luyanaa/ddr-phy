# SPDX-License-Identifier: Apache-2.0
"""Emit sch/pads/gf180mcuD/pcell/sdram_chip_top.spice.

Top-level LVS schematic for the SDRAM chip.  Structure:
  - 30 gf180_pad_tile instances (21 cmd + 8 dq + 1 ck), matching
    rtl/sdram_chip_top.sv exactly.
  - 1 black-box sdram_phy_core instance.  The core is an empty subckt here:
    its interior is signed off by the LibreLane run, so top-level LVS proves
    only pad<->core connectivity and pad internals (user-confirmed method).
  - tie-off nets: the DFI/config inputs tied to constants are connected to
    VSS (logic 0) or VDD (logic 1) of the core supply, matching the RTL.

Pin order of the core instance MUST match the extracted-layout pin order in
flow/runs/.../final/spice/sdram_phy_core.spice line 215+.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "sch", "pads", "gf180mcuD", "pcell",
                   "sdram_chip_top.spice")

ADDR_BITS = 13
BANK_BITS = 2
DATA_BITS = 8
CMD_BITS = 21

def main():
    # core pin order exactly as in the LibreLane final spice (line 215+),
    # buses expanded in the same [n] order they appear.
    pins = ["VDD", "VSS", "cap_clk", "capture_ready", "ck_active", "ck_o"]
    pins += [f"ck_phase_clks[{i}]" for i in range(4)]
    pins += ["ck_phase_clocks_ready", "ck_phase_sel[0]", "ck_phase_sel[1]", "clk"]
    # cmd_o appears in scrambled order in the header: 0,10..19,1,20,2..9
    cmd_order = [0, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 1, 20, 2, 3, 4, 5, 6, 7, 8, 9]
    pins += [f"cmd_o[{i}]" for i in cmd_order]
    pins += ["contention", "dfi_act_n"]
    pins += [f"dfi_address[{i}]" for i in [0, 10, 11, 12, 1, 2, 3, 4, 5, 6, 7, 8, 9]]
    pins += ["dfi_bank[0]", "dfi_bank[1]", "dfi_cas_n", "dfi_cke", "dfi_cs_n",
             "dfi_odt", "dfi_ras_n"]
    pins += [f"dfi_rddata[{i}]" for i in range(8)]
    pins += ["dfi_rddata_en", "dfi_rddata_valid", "dfi_reset_n", "dfi_we_n"]
    pins += [f"dfi_wrdata[{i}]" for i in range(8)]
    pins += ["dfi_wrdata_en", "dfi_wrdata_mask"]
    pins += [f"dq_i[{i}]" for i in range(8)]
    pins += [f"dq_o[{i}]" for i in range(8)]
    pins += ["dq_oe", "io_power_ok"]
    pins += [f"pad_config[{i}]" for i in range(8)]
    pins += ["pad_ready"]
    pins += [f"phase_clks[{i}]" for i in range(4)]
    pins += ["phase_clocks_ready", "phase_sel[0]", "phase_sel[1]",
             "phase_sel_valid", "read_latency_error", "rst", "turnaround_busy"]

    # Net each core pin connects to.  Output pins -> their wire; input pins
    # tied to constants -> VSS (0) or VDD (1) of the core supply.
    HI = {"io_power_ok", "dfi_ras_n", "dfi_cas_n", "dfi_we_n", "dfi_cs_n",
          "dfi_reset_n", "dfi_act_n", "rst"}
    def netfor(p):
        base = p.split("[")[0]
        if base in ("VDD", "VSS"):
            return base
        if base in ("cmd_o", "dq_o", "dq_i"):
            return "n_" + p.replace("[", "_").replace("]", "")
        if base in ("ck_o", "dq_oe"):
            return "n_" + base
        if base in ("cap_clk", "capture_ready", "ck_active", "contention",
                    "pad_ready", "read_latency_error", "turnaround_busy",
                    "dfi_rddata", "dfi_rddata_valid"):
            return "n_open_" + base  # unconnected core outputs
        # everything else is a tied input
        return "VDD" if base in HI else "VSS"

    lines = []
    lines.append("* SPDX-License-Identifier: Apache-2.0")
    lines.append("* sdram_chip_top LVS schematic.  Black-box core; see header comment in")
    lines.append("* generator/emit_chip_top_spice.py.  Generated - do not edit by hand.")
    lines.append("")

    # black-box core subckt: pins listed, body empty.
    lines.append(".SUBCKT sdram_phy_core " + " ".join(pins))
    lines.append(".ENDS")
    lines.append("")

    # top subckt
    toppins = ([f"pad_cmd[{i}]" for i in range(CMD_BITS)] +
               [f"pad_dq[{i}]" for i in range(DATA_BITS)] +
               ["pad_ck", "VDDIO", "VSSIO", "VDD", "VSS"])
    lines.append(".SUBCKT gf180mcu_sdram_chip_top " + " ".join(toppins))

    # pads
    idx = 0
    for i in range(CMD_BITS):
        net = f"n_cmd_o_{i}"
        lines.append(f"Xcmd{i} {net} VSSIO nc_pu_cmd{i} pad_cmd[{i}] nc_in_cmd{i} VDDIO VSSIO gf180_pad_tile")
        idx += 1
    for i in range(DATA_BITS):
        lines.append(f"Xdq{i} n_dq_o_{i} n_dq_oe_b nc_pu_dq{i} pad_dq[{i}] n_dq_i_{i} VDDIO VSSIO gf180_pad_tile")
    lines.append(f"Xck n_ck_o VSSIO nc_pu_ck pad_ck nc_in_ck VDDIO VSSIO gf180_pad_tile")
    lines.append("Xinv_oe VDD VDD VSS VSS n_dq_oe_b n_dq_oe gf180mcu_as_sc_mcu7t3v3__inv_2")
    lines.append("")

    # core instance
    inst_nets = " ".join(netfor(p) for p in pins)
    lines.append("Xcore " + inst_nets + " sdram_phy_core")
    lines.append("")
    lines.append(".ENDS")
    lines.append("")

    # pad tile + core subckts appended from the tile spice so the deck has
    # device-level detail for the pads.
    tilespice = os.path.join(HERE, "..", "sch", "pads", "gf180mcuD", "pcell",
                             "gf180_pad_tile.spice")
    txt = open(tilespice).read()
    for blk in (".SUBCKT gf180_pad_tile", ".SUBCKT gf180_pad_core"):
        s = txt.find(blk)
        if s >= 0:
            e = txt.find(".ENDS", s) + 6
            lines.append(txt[s:e].strip())
            lines.append("")


    lines.append(".SUBCKT gf180mcu_as_sc_mcu7t3v3__inv_2 VDD VNW VPW VSS Y A")
    lines.append("X_M0 VDD A Y VNW pfet_03v3 ad=0.6072p pd=3.64u as=0.3588p ps=1.9u w=1.38u l=0.28u")
    lines.append("X_M1 Y A VSS VPW nfet_03v3 ad=0.26p pd=1.52u as=0.44p ps=2.88u w=1u l=0.28u")
    lines.append("X_M2 Y A VDD VNW pfet_03v3 ad=0.3588p pd=1.9u as=0.6072p ps=3.64u w=1.38u l=0.28u")
    lines.append("X_M3 VSS A Y VPW nfet_03v3 ad=0.44p pd=2.88u as=0.26p ps=1.52u w=1u l=0.28u")
    lines.append(".ENDS")
    lines.append("")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w").write("\n".join(lines))
    print("wrote", OUT, len(lines), "lines", len(pins), "core pins")

main()
