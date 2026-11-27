# SPDX-License-Identifier: Apache-2.0
"""Emit the LVS view of the chip top: full layout with the core internals
replaced by the pin-only abstract (sdram_phy_core_lvs_abstract.gds).

Why: flat-mode KLayout LVS extraction descends into every cell.  With the
real core present it extracts 3665 stdcell devices and the black-box
schematic can never match (proven).  The abstract carries only the labelled
boundary pins, so extraction sees the core as an empty black box whose pins
land exactly where the top-level wires connect - matching the schematic.

Reads  : gf180mcu_sdram_chip_top_filled.gds  (full core, for DRC)
Writes : gf180mcu_sdram_chip_top_lvsview.gds (abstract core, for LVS)
Run    : klayout -b -r generator/emit_chip_lvs_view.py
"""
import os
import pya

HERE = os.path.dirname(os.path.abspath(__file__))
PCELL = os.path.join(HERE, "..", "sch", "pads", "gf180mcuD", "pcell")
IN_GDS = os.path.join(PCELL, "gf180mcu_sdram_chip_top_filled.gds")
ABSTRACT = os.path.join(PCELL, "sdram_phy_core_lvs_abstract.gds")
OUT_GDS = os.path.join(PCELL, "gf180mcu_sdram_chip_top_lvsview.gds")


def main():
    ly = pya.Layout()
    ly.read(IN_GDS)
    top = ly.cell("gf180mcu_sdram_chip_top") or ly.top_cell()

    # Find instances of the full core cell and retarget them to the abstract.
    full_core = ly.cell("sdram_phy_core")
    if full_core is None:
        print("no sdram_phy_core cell present; copying unchanged")
        ly.write(OUT_GDS)
        return

    # load abstract into a temp layout and import
    absly = pya.Layout()
    absly.read(ABSTRACT)
    abs_top = absly.top_cell()

    # import abstract cell hierarchy into ly under a unique name
    order = []
    seen = set()

    def visit(ci):
        if ci in seen:
            return
        seen.add(ci)
        for it in absly.cell(ci).each_inst():
            visit(it.cell_index)
        order.append(ci)
    visit(abs_top.cell_index())
    ni = {}
    for ci in order:
        cell = absly.cell(ci)
        nm = "sdram_phy_core" if ci == abs_top.cell_index() else cell.name
        # create/replace
        existing = ly.cell(nm)
        if existing is not None and nm == "sdram_phy_core":
            nc = existing
            # wipe internals: delete all shapes + instances
            for li in range(ly.layers()):
                nc.shapes(li).clear()
            nc.clear_insts()
        else:
            nc = ly.create_cell(nm)
        ni[ci] = nc.cell_index()
    # copy shapes/insts bottom-up
    for ci in order:
        cell = absly.cell(ci)
        nc = ly.cell(ni[ci])
        for li in range(absly.layers()):
            inf = absly.get_info(li)
            dli = ly.layer(inf.layer, inf.datatype)
            nc.shapes(dli).insert(cell.shapes(li))
        for it in cell.each_inst():
            nc.insert(pya.CellInstArray(ni[it.cell_index], it.trans))

    ly.write(OUT_GDS)
    print("wrote LVS view (abstract core) to", OUT_GDS)


main()
