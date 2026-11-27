#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Emit LEF + Liberty for the verified `gf180_pad_tile`.

Both views are derived from one pin table so the GDS, LEF and Liberty cannot
drift.  The electrical numbers come from the SPICE characterization already
in reports/pad_char_gf180mcuD_*.json and reports/pad_delay_gf180mcuD_*.json
(worst-case over the three characterized corners), not from a datasheet.

The LEF OBS geometry is extracted from the GDS with KLayout's `pya`, so run
this generator inside the LibreLane nix-shell environment.

Status: design-assumption views for place-and-route and chip-top STA.  They
are NOT ESD-qualified and carry no IBIS/package model.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "sch" / "pads" / "gf180mcuD" / "pcell"

# GDS-frame pin geometry (um), straight from generator/gf180_pad_layout.py
# Shift GDS-frame pin coordinates into the positive LEF macro bbox.
LEF_SHIFT = (66.5, 65.0)
PINS = {
    "OUT":   ("INPUT",  [("Metal2", (-66.5, 54.5, -64.5, 56.5))]),
    "OE_N":  ("INPUT",  [("Metal2", (-63.5, 57.5, -61.5, 59.5))]),
    "PU_OK": ("OUTPUT", [("Metal2", (-60.5, 60.5, -58.5, 62.5))]),
    "IN":    ("OUTPUT", [("Metal2", (-10.75, -64.23, -10.35, -51.63))]),
    "PAD":   ("INOUT",  [("MetalTop", (-32.0, -32.0, 32.0, 32.0)),
                          ("Metal3", (33.0, 21.0, 33.6, 72.5)),
                          ("Metal3", (33.0, 71.5, 36.8, 72.5))]),
    "VDDIO": ("INOUT",  [("Metal2", (-58.3, -39.5, -57.3, -38.5)),
                          ("Metal3", (-57.9, -65.0, -57.5, -39.6))]),
    "VSSIO": ("INOUT",  [("Metal4", (35.0, 9.5, 35.6, 86.3)),
                          ("Metal4", (35.0, 85.0, 35.6, 91.2)),
                          ("Metal2", (-50.0, 90.0, 45.0, 92.0))]),
}
SIZE = (111.5, 185.0)   # bbox -66.5,-65 .. 45,120


def obstruction_lines():
    """Emit the pad master's exact routing-metal occupancy as LEF OBS."""
    import pya

    gds_path = OUT / "gf180_pad_tile.gds"
    layout = pya.Layout()
    layout.read(str(gds_path))
    cell = layout.cell("gf180_pad_tile")
    if cell is None:
        raise RuntimeError("gf180_pad_tile missing from %s" % gds_path)

    layers = (
        ("Metal1", 34),
        ("Metal2", 36),
        ("Metal3", 42),
        ("Metal4", 46),
        ("MetalTop", 81),  # PAD top-metal geometry in the GDS layer map
    )
    shift_x = int(round(LEF_SHIFT[0] / layout.dbu))
    shift_y = int(round(LEF_SHIFT[1] / layout.dbu))
    max_x = int(round(SIZE[0] / layout.dbu))
    max_y = int(round(SIZE[1] / layout.dbu))
    lines = ["  OBS"]

    for name, number in layers:
        layer_index = layout.find_layer(number, 0)
        if layer_index is None or layer_index < 0:
            raise RuntimeError("GDS layer %d/0 missing for %s" % (number, name))
        lines.append("    LAYER %s ;" % name)
        count = 0
        iterator = cell.begin_shapes_rec(layer_index)
        while not iterator.at_end():
            shape = iterator.shape()
            if not shape.is_text():
                if not shape.is_box():
                    raise RuntimeError(
                        "expected rectangular %s geometry in %s" % (name, gds_path))
                box = shape.box.transformed(iterator.trans())
                x0 = max(0, box.left + shift_x)
                y0 = max(0, box.bottom + shift_y)
                x1 = min(max_x, box.right + shift_x)
                y1 = min(max_y, box.top + shift_y)
                if x0 < x1 and y0 < y1:
                    scale = layout.dbu
                    lines.append(
                        "      RECT %.3f %.3f %.3f %.3f ;" %
                        (x0 * scale, y0 * scale, x1 * scale, y1 * scale))
                    count += 1
            iterator.next()
        if count == 0:
            raise RuntimeError("no metal occupancy found for %s" % name)

    lines.append("  END")
    return lines



# SPICE numbers (worst over tt/ss/ff characterization)
T_OUT_PAD = 0.441      # ns, pad_delay out_max
T_PAD_IN = 0.096       # ns, pad_delay in_max
T_OE_ON = 0.608        # ns, toe_on max over PVT used by the SDC
T_OE_OFF = 3.299       # ns, toe_off max over PVT
TR_OUT = 0.129         # ns
TF_OUT = 0.151         # ns
C_PAD = 2.0            # pF, bond pad + package assumption
C_CTRL = 0.05          # pF


def lef():
    lines = [
        "VERSION 5.8 ;",
        "BUSBITCHARS \"[]\" ;",
        "DIVIDERCHAR \"/\" ;",
        "MACRO gf180_pad_tile",
        "  CLASS PAD ;",
        "  FOREIGN gf180_pad_tile ;",
        "  ORIGIN 0 0 ;",
        "  SIZE %.3f BY %.3f ;" % SIZE,
    ]
    for name, (direction, rects) in PINS.items():
        lines.append("  PIN %s" % name)
        lines.append("    DIRECTION %s ;" % direction)
        if name == "VDDIO":
            lines.append("    USE POWER ;")
        elif name == "VSSIO":
            lines.append("    USE GROUND ;")
        else:
            lines.append("    USE SIGNAL ;")
        lines.append("    PORT")
        sx, sy = LEF_SHIFT
        for layer, (x0, y0, x1, y1) in rects:
            lines.append("      LAYER %s ;" % layer)
            lines.append("        RECT %.3f %.3f %.3f %.3f ;"
                         % (x0 + sx, y0 + sy, x1 + sx, y1 + sy))
        lines.append("    END")
        lines.append("  END %s" % name)
    lines += obstruction_lines()
    lines += ["END gf180_pad_tile", "END LIBRARY", ""]
    return "\n".join(lines)


def lib():
    def arc(name, rel, typ, cell_r, cell_f, tr, tf, when=None):
        s = ["      timing() {", "        related_pin : \"%s\" ;" % rel,
             "        timing_type : %s ;" % typ]
        if when:
            s.append("        when : \"%s\" ;" % when)
        s += ["        cell_rise(delay_template_5x5) {",
              "          values ( \\"]
        for i in range(5):
            s.append("            \"%.4f, %.4f, %.4f, %.4f, %.4f%s \\"
                     % ((cell_r,) * 5 + ("," if i < 4 else "",)))
        s += ["          ) ;", "        }",
              "        cell_fall(delay_template_5x5) {", "          values ( \\"]
        for i in range(5):
            s.append("            \"%.4f, %.4f, %.4f, %.4f, %.4f%s \\"
                     % ((cell_f,) * 5 + ("," if i < 4 else "",)))
        s += ["          ) ;", "        }",
              "        rise_transition(delay_template_5x5) {", "          values ( \\"]
        for i in range(5):
            s.append("            \"%.4f, %.4f, %.4f, %.4f, %.4f%s \\"
                     % ((tr,) * 5 + ("," if i < 4 else "",)))
        s += ["          ) ;", "        }",
              "        fall_transition(delay_template_5x5) {", "          values ( \\"]
        for i in range(5):
            s.append("            \"%.4f, %.4f, %.4f, %.4f, %.4f%s \\"
                     % ((tf,) * 5 + ("," if i < 4 else "",)))
        s += ["          ) ;", "        }", "      }"]
        return s

    t = [
        "/* gf180_pad_tile: generated by generator/emit_pad_lef_lib.py",
        " * Design-assumption Liberty built from the SPICE characterization.",
        " * No IBIS, no package model, no ESD qualification. */",
        "library (gf180_pad_tile) {",
        "  technology (cmos) ;",
        "  delay_model : table_lookup ;",
        "  time_unit : \"1ns\" ;",
        "  voltage_unit : \"1V\" ;",
        "  current_unit : \"1mA\" ;",
        "  capacitive_load_unit (1, pF) ;",
        "  pulling_resistance_unit : \"1kohm\" ;",
        "  leakage_power_unit : \"1mW\" ;",
        "  nom_process : 1 ; nom_temperature : 27 ; nom_voltage : 3.3 ;",
        "  operating_conditions (tt_27_3v30) {",
        "    process : 1 ; temperature : 27 ; voltage : 3.3 ;",
        "  }",
        "  default_operating_conditions : tt_27_3v30 ;",
        "  lu_table_template (delay_template_5x5) {",
        "    variable_1 : input_net_transition ;",
        "    variable_2 : total_output_net_capacitance ;",
        "    index_1 (\"0.01, 0.05, 0.1, 0.5, 1.0\") ;",
        "    index_2 (\"0.01, 0.05, 0.1, 0.5, 1.0\") ;",
        "  }",
    ]
    t += ["  cell (gf180_pad_tile) {", "    pad_cell : true ;",
          "    area : %.3f ;" % (SIZE[0] * SIZE[1]),
          "    dont_touch : true ;", "    dont_use : true ;",
          "    pg_pin (VDDIO) { pg_type : primary_power ; voltage_name : VDDIO ; }",
          "    pg_pin (VSSIO) { pg_type : primary_ground ; voltage_name : VSSIO ; }",
          "    pin (OUT) { direction : input ; capacitance : %.3f ; }" % 0.2,
          "    pin (OE_N) { direction : input ; capacitance : %.3f ; }" % C_CTRL,
          "    pin (PU_OK) { direction : output ; function : \"1'b1\" ; }",
          "    pin (IN) {",
          "      direction : output ; function : \"PAD\" ;",
          "      max_capacitance : 0.5 ;"]
    t += arc("IN", "PAD", "combinational", T_PAD_IN, T_PAD_IN, 0.05, 0.05)
    t += ["    }", "    pin (PAD) {", "      direction : inout ;",
          "      function : \"OE_N ? 1'bz : OUT\" ;",
          "      capacitance : %.3f ;" % C_PAD]
    t += arc("PAD", "OUT", "combinational", T_OUT_PAD, T_OUT_PAD,
             TR_OUT, TF_OUT, when="!OE_N")
    t += arc("PAD", "OE_N", "three_state_enable", T_OE_ON, T_OE_ON,
             0.1, 0.1, when="!OE_N")
    t += arc("PAD", "OE_N", "three_state_disable", T_OE_OFF, T_OE_OFF,
             0.1, 0.1, when="OE_N")
    t += ["    }", "  }", "}", ""]
    return "\n".join(t)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    lef_path = OUT / "gf180_pad_tile.lef"
    lib_path = OUT / "gf180_pad_tile.lib"
    lef_path.write_text(lef())
    lib_path.write_text(lib())
    man = {
        "generated_by": "generator/emit_pad_lef_lib.py",
        "status": "design_assumption views (no IBIS, no ESD qualification)",
        "macro": "gf180_pad_tile",
        "size_um": SIZE,
        "gds": "sch/pads/gf180mcuD/pcell/gf180_pad_tile.gds",
        "lef": str(lef_path.relative_to(ROOT)),
        "lib": str(lib_path.relative_to(ROOT)),
        "timing_source": {
            "out_to_pad_ns": T_OUT_PAD, "pad_to_in_ns": T_PAD_IN,
            "oe_on_ns": T_OE_ON, "oe_off_ns": T_OE_OFF,
            "note": "worst over reports/pad_char_gf180mcuD_*.json and "
                    "reports/pad_delay_gf180mcuD_*.json",
        },
    }
    (OUT / "gf180_pad_tile_views.json").write_text(
        json.dumps(man, indent=2) + "\n")
    print("wrote %s and %s" % (lef_path, lib_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
