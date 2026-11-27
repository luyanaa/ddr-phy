# SPDX-License-Identifier: Apache-2.0
# Generate the OpenROAD chip-top macro-integration flow inputs and run script.
#
# Produces (in flow/chiptop_build/):
#   sdram_chip_top_pnr.v   flattened structural netlist + black-box stubs
#   chiptop.tcl            OpenROAD flow: lef/netlist/floorplan/place/pdn/route/write
#
# Method: 30 gf180_pad_tile ring macros + 1 sdram_phy_core macro + 1
# gf180mcu_as_sc_mcu7t3v3__inv_2 dq_oe inverter, placed at the fixed ring/cavity
# coordinates of generator/emit_chip_top.py, then OpenROAD global+detail route
# does pad<->core interconnect.  Power (VDDIO/VSSIO ring, VDD/VSS core) via pdngen.
import os

HERE = os.path.dirname(os.path.abspath(__file__))

ASSIGN = {
    0:"VDDIO",1:"cmd_o[11]",2:"cmd_o[12]",3:"cmd_o[13]",4:"ck",5:"cmd_o[14]",
    6:"cmd_o[15]",7:"cmd_o[16]",8:"VSSIO",
    9:"dq[0]",10:"dq[1]",11:"dq[2]",12:"dq[3]",13:"dq[4]",14:"dq[5]",15:"dq[6]",
    16:"dq[7]",17:"cmd_o[20]",18:"cmd_o[19]",19:"cmd_o[18]",20:"cmd_o[17]",
    21:"cmd_o[10]",22:"cmd_o[9]",23:"cmd_o[8]",24:"cmd_o[7]",
    25:"cmd_o[6]",26:"cmd_o[5]",27:"cmd_o[4]",28:"cmd_o[3]",29:"cmd_o[2]",
    30:"cmd_o[1]",31:"cmd_o[0]",
}
def bitof(net):
    return net[net.index("[")+1:net.index("]")]

# Normalize LEF pin coords, then undo the oriented shift at placement so the
# pins retain their original absolute positions in the physical ring.
LEF_SHIFT = (66.5, 65.0)
# OpenDB orientation rotations applied to LEF_SHIFT, in um.
LEF_SHIFT_BY_ORIENT = {
    "R0": LEF_SHIFT,
    "R90": (-LEF_SHIFT[1], LEF_SHIFT[0]),
    "R180": (-LEF_SHIFT[0], -LEF_SHIFT[1]),
    "R270": (LEF_SHIFT[1], -LEF_SHIFT[0]),
}
# setLocation uses the lower-left of the oriented SIZE bbox; subtract this
# offset as well to place the normalized LEF origin at the physical ring origin.
LEF_BBOX_ORIGIN_BY_ORIENT = {
    "R0": (0.0, 0.0),
    "R90": (185.0, 0.0),
    "R180": (111.5, 185.0),
    "R270": (0.0, 111.5),
}

def tile_placement(index):
    if index <= 8:
        orient, x, y = "R0", 140.0 + 190.0*index, 90.0
    elif index <= 15:
        orient, x, y = "R90", 1710.0, 281.66 + 190.0*(index-9)
    elif index <= 24:
        orient, x, y = "R180", 1660.0 - 190.0*(index-16), 1710.0
    else:
        orient, x, y = "R270", 90.0, 1421.66 - 190.0*(index-25)
    dx, dy = LEF_SHIFT_BY_ORIENT[orient]
    bx, by = LEF_BBOX_ORIGIN_BY_ORIENT[orient]
    return orient, x - dx - bx, y - dy - by

CORE_X, CORE_Y = 762.9825, 754.0225
INVERTER_X, INVERTER_Y = 1042.0175, 985.9925
DBU = 2000  # per um
MANUFACTURING_GRID = 10  # DBU (0.005 um)

def dbu(um):
    value = int(round(um*DBU))
    return ((value + MANUFACTURING_GRID//2) // MANUFACTURING_GRID) * MANUFACTURING_GRID

def emit_netlist(path):
    L = []
    L.append("// SPDX-License-Identifier: Apache-2.0")
    L.append("// Flattened structural chip-top P&R netlist for OpenROAD macro integration.")
    L.append("// Power pins omitted (bound via add_global_connection + pdngen).")
    L.append("")
    L.append("")
    L.append("module sdram_chip_top_pnr ();")
    L.append("  wire dq_oe, n_dq_oe;")
    L.append("  wire [20:0] cmd_o;")
    L.append("  wire [7:0] dq_o;")
    L.append("  wire [7:0] dq_i;")
    L.append("  wire ck_o;")
    L.append("")
    L.append("  gf180mcu_as_sc_mcu7t3v3__inv_2 u_dqoe_inv (.A(dq_oe), .Y(n_dq_oe));")
    L.append("")
    L.append("  sdram_phy_core u_core (")
    L.append("    .cmd_o(cmd_o), .dq_o(dq_o), .dq_i(dq_i), .dq_oe(dq_oe), .ck_o(ck_o)")
    L.append("  );")
    L.append("")
    for idx in range(32):
        net = ASSIGN[idx]
        if net in ("VDDIO","VSSIO"):
            continue
        inst = "u_pad_%d" % idx
        if net == "ck":
            L.append("  gf180_pad_tile %s (.OUT(ck_o), .IN(), .OE_N(), .PU_OK(), .PAD());" % inst)
        elif net.startswith("cmd_o"):
            L.append("  gf180_pad_tile %s (.OUT(cmd_o[%s]), .IN(), .OE_N(), .PU_OK(), .PAD());" % (inst, bitof(net)))
        elif net.startswith("dq["):
            L.append("  gf180_pad_tile %s (.OUT(dq_o[%s]), .IN(dq_i[%s]), .OE_N(n_dq_oe), .PU_OK(), .PAD());" % (inst, bitof(net), bitof(net)))
    L.append("endmodule")
    open(path,"w").write("\n".join(L)+"\n")
    print("wrote netlist %s" % path)

def emit_tcl(path):
    t = []
    t.append("# SPDX-License-Identifier: Apache-2.0")
    t.append("# OpenROAD chip-top macro-integration flow (generated).")
    t.append("set GF [lindex [glob -nocomplain /home/yanlu/.ciel/ciel/gf180mcu/versions/*/gf180mcuD] end]")
    t.append("")
    t.append("# ---- LEF: tech first, then cells, then macros ----")
    t.append("read_lef $GF/libs.ref/gf180mcu_as_sc_mcu7t3v3/techlef/gf180mcu_as_sc_mcu7t3v3__nom.tlef")
    t.append("read_lef $GF/libs.ref/gf180mcu_as_sc_mcu7t3v3/lef/gf180mcu_as_sc_mcu7t3v3.lef")
    t.append("read_lef /grid/ddr-phy/sch/pads/gf180mcuD/pcell/gf180_pad_tile.lef")
    t.append("read_lef /grid/ddr-phy/flow/runs/gf180-as-7t3v3-sdram_phy_core/final/lef/sdram_phy_core.lef")
    t.append("")
    t.append("# ---- netlist ----")
    t.append("read_verilog /grid/ddr-phy/flow/chiptop_build/sdram_chip_top_pnr.v")
    t.append("link_design sdram_chip_top_pnr")
    t.append('puts "LINK_OK"')
    t.append("")
    t.append("# ---- floorplan: fixed 1800x1800 die ----")
    t.append("initialize_floorplan -die_area {0 0 1800 1800} -core_area {210 210 1590 1590} -site unithd")
    # routing tracks (from PDK tracks.info, converted to make_tracks)
    t.append("make_tracks Metal1 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56")
    t.append("make_tracks Metal2 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56")
    t.append("make_tracks Metal3 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56")
    t.append("make_tracks Metal4 -x_offset 0.28 -x_pitch 0.56 -y_offset 0.28 -y_pitch 0.56")
    t.append("make_tracks Metal5 -x_offset 0.45 -x_pitch 0.90 -y_offset 0.45 -y_pitch 0.90")
    t.append('puts "FLOORPLAN_OK"')
    t.append("")
    # macro placement
    t.append("# ---- macro placement (FIRM, ring + core + inverter) ----")
    t.append("set block [ord::get_db_block]")
    for idx in range(32):
        net = ASSIGN[idx]
        if net in ("VDDIO","VSSIO"):
            continue
        o,x,y = tile_placement(idx)
        t.append("set inst [$block findInst u_pad_%d]" % idx)
        t.append("$inst setOrient %s" % o)
        t.append("$inst setLocation %d %d" % (dbu(x), dbu(y)))
        t.append('$inst setPlacementStatus FIRM')
    # core
    t.append("set cinst [$block findInst u_core]")
    t.append("$cinst setOrient R0")
    t.append("$cinst setLocation %d %d" % (dbu(CORE_X), dbu(CORE_Y)))
    t.append("$cinst setPlacementStatus FIRM")
    # inverter
    t.append("set iinst [$block findInst u_dqoe_inv]")
    t.append("$iinst setOrient R0")
    t.append("$iinst setLocation %d %d" % (dbu(INVERTER_X), dbu(INVERTER_Y)))
    t.append("$iinst setPlacementStatus FIRM")
    t.append('puts "PLACE_OK"')
    t.append("")
    t.append("")
    t.append("# ---- signal routing ----")
    t.append("set_routing_layers -signal Metal1-Metal5 -clock Metal1-Metal5")
    t.append("set_macro_extension 2")
    t.append("global_route -congestion_iterations 50 -verbose")
    t.append('puts "GRT_DONE"')
    t.append("write_def /grid/ddr-phy/flow/chiptop_build/chiptop_grt.def")
    t.append("set_thread_count 8")
    t.append("detailed_route -droute_end_iter 64 -or_seed 42 -verbose 1 -output_drc /grid/ddr-phy/flow/chiptop_build/drt.rpt")
    t.append('puts "DRT_DONE"')
    t.append("write_def /grid/ddr-phy/flow/chiptop_build/chiptop_routed.def")
    t.append("write_db /grid/ddr-phy/flow/chiptop_build/chiptop.odb")
    t.append('puts "DONE"')
    open(path,"w").write("\n".join(t)+"\n")
    print("wrote tcl %s" % path)

if __name__ == "__main__":
    emit_netlist(os.path.join(HERE,"sdram_chip_top_pnr.v"))
    emit_tcl(os.path.join(HERE,"chiptop.tcl"))
