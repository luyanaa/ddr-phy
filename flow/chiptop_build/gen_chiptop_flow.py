# SPDX-License-Identifier: Apache-2.0
# Generate the OpenROAD chip-top macro-integration flow inputs:
#   1. flattened structural P&R netlist (30 named pad tiles + core + inverter)
#   2. OpenROAD Tcl: lef/lib read, floorplan, macro placement, PDN, route
# Run in the librelane nix-shell (OpenROAD 2026-02).
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ---- padmap: ring index -> net (from specs/pads/sdram_chip_padmap.yaml) ----
ASSIGN = {
    0:"VDDIO",1:"cmd_o[11]",2:"cmd_o[12]",3:"cmd_o[13]",4:"ck",5:"cmd_o[14]",
    6:"cmd_o[15]",7:"cmd_o[16]",8:"VSSIO",
    9:"dq[0]",10:"dq[1]",11:"dq[2]",12:"dq[3]",13:"dq[4]",14:"dq[5]",15:"dq[6]",
    16:"dq[7]",17:"cmd_o[20]",18:"cmd_o[19]",19:"cmd_o[18]",20:"cmd_o[17]",
    21:"cmd_o[10]",22:"cmd_o[9]",23:"cmd_o[8]",24:"cmd_o[7]",
    25:"cmd_o[6]",26:"cmd_o[5]",27:"cmd_o[4]",28:"cmd_o[3]",29:"cmd_o[2]",
    30:"cmd_o[1]",31:"cmd_o[0]",
}

def tile_placement(index):
    """Return (orient_odb, x_um, y_um) for ring index. Mirrors emit_chip_top._site_transform."""
    if index <= 8:      # bottom row, R0
        return "R0", 140.0 + 190.0*index, 90.0
    elif index <= 15:   # right column, R90
        j = index - 9
        return "R90", 1710.0, 281.66 + 190.0*j
    elif index <= 24:   # top row, R180
        i = index - 16
        return "R180", 1660.0 - 190.0*i, 1710.0
    else:               # left column, R270
        j = index - 25
        return "R270", 90.0, 1421.66 - 190.0*j

CORE_X, CORE_Y = 762.9825, 754.0225
INVERTER_X, INVERTER_Y = 1042.0175, 985.9925

def emit_netlist(path):
    L = []
    L.append("// SPDX-License-Identifier: Apache-2.0")
    L.append("// Flattened structural chip-top P&R netlist for OpenROAD macro integration.")
    L.append("// 30 gf180_pad_tile + sdram_phy_core + dq_oe inverter. Connectivity matches")
    L.append("// rtl/sdram_chip_top.sv; instances are flattened/named for exact placement.")
    L.append("// Power pins are omitted (bound via add_global_connection + pdngen).")
    L.append("module sdram_chip_top_pnr ();")
    L.append("  wire dq_oe, n_dq_oe;")
    # core output wires
    L.append("  wire [20:0] cmd_o;")
    L.append("  wire [7:0] dq_o;")
    L.append("  wire [7:0] dq_i;")
    L.append("  wire ck_o;")
    # the inverter: dq_oe (core, active high) -> n_dq_oe (pads, active low)
    L.append("  gf180mcu_as_sc_mcu7t3v3__inv_2 u_dqoe_inv (.A(dq_oe), .Y(n_dq_oe));")
    # core instance: only the pins we connect; inputs tied off are left unconnected here
    # (the physical core already implements them; this netlist proves pad<->core connectivity)
    L.append("  sdram_phy_core u_core (")
    L.append("    .cmd_o(cmd_o), .dq_o(dq_o), .dq_i(dq_i), .dq_oe(dq_oe), .ck_o(ck_o)")
    L.append("  );")
    # pad instances
    for idx in range(32):
        net = ASSIGN[idx]
        if net in ("VDDIO","VSSIO"):
            continue
        inst = "u_pad_%d" % idx
        if net == "ck":
            # output-only pad: OUT driven by ck_o, IN/OE_N unconnected/tied
            L.append("  gf180_pad_tile %s (.OUT(ck_o), .IN(), .OE_N(), .PAD());" % inst)
        elif net.startswith("cmd_o"):
            bit = net[net.index("[")+1:net.index("]")]
            L.append("  gf180_pad_tile %s (.OUT(cmd_o[%s]), .IN(), .OE_N(), .PAD());" % (inst, bit))
        elif net.startswith("dq["):
            bit = net[net.index("[")+1:net.index("]")]
            L.append("  gf180_pad_tile %s (.OUT(dq_o[%s]), .IN(dq_i[%s]), .OE_N(n_dq_oe), .PAD());" % (inst, bit, bit))
    L.append("endmodule")
    open(path,"w").write("\n".join(L)+"\n")
    print("wrote netlist", path)

if __name__ == "__main__":
    emit_netlist(os.path.join(HERE,"sdram_chip_top_pnr.v"))
    # report placements for the tcl
    for idx in range(32):
        if ASSIGN[idx] in ("VDDIO","VSSIO"): continue
        o,x,y = tile_placement(idx)
        print("pad idx%d %s (%.3f,%.3f) %s" % (idx,o,x,y,ASSIGN[idx]))
