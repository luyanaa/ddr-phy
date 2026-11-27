# QFN40 / QFN48 package study for IHP130 DDR1

Status: first-order package/padring study, **signoff=false**. Full rationale
and pinout tables are in `docs/PACKAGE_PADFRAME_PLAN.md`.

## Result

Full x8 DDR1 needs 32 signal pins plus at least 5 power/reference pins
(37 total), or 39 with duplicated VDDIO/VSSIO. QFN24/28/32 cannot carry it.
Two coupon versions were built and run through the IHP AMS template's
`run_bondplan.py`:

| Metric | QFN32 reference | QFN40 coupon | QFN48 coupon |
|---|---:|---:|---:|
| Package | `OP_QFN32_A4_FIT` | `OP_QFN40_6x6mm` | `OP_QFN48` |
| Die | 1.6 mm | 2.0 mm | 2.4 mm |
| Pads / bondwires | 32 | 40 | 48 |
| Wire length | 1296–1701 µm | 1771–2459 µm | 2056–2735 µm |
| Series L (25 µm Au + lead allowance) | 1.31–1.77 nH | 1.85–2.69 nH | 2.19–3.04 nH |
| Series R | 0.070–0.091 Ω | 0.094–0.128 Ω | 0.108–0.142 Ω |
| 50 Ω L/R bound | 26–35 ps | 37–54 ps | 44–61 ps |
| Min wire-to-wire gap | — | −25 µm (pins 29/30) | +67 µm |
| Max lead skew | — | 4.3° | 2.0° |
| Power/ground leads | — | 7 + 1 NC | 16, no NC |

QFN40 is the minimum package: 39 used + 1 NC, but its 40-lead corner
assignment still has a negative-gap warning. QFN48 uses all 48 leads
(32 signal + 16 power/ground) and is geometrically clean, at the cost of a
larger die and ~7 ps more worst-case L/R bound.

## Impact on the SS tDS failure

The SS 10 ns failure is a 168 ps first-write DQS tDS violation. The package
bound is 54 ps (QFN40) or 61 ps (QFN48); the Open-Padrings 32 digital
pad→core SPEF bound is 492 Ω × 0.086 pF ≈ 42 ps. Even summed, 96–103 ps <
168 ps. Packaging/padring cannot explain the failure; pad TX/OE and DQS
capture remain the primary suspects.

Do not replace the behavioral pad model with package RLC. Keep
`rtl/ihp130_sstl2_dq_model.sv` for the digital boundary; attach
`spice/package/qfn40_pkg.spice` or `qfn48_pkg.spice` outside the transistor-level pad PEX, and
give the digital TB at most a bounded package skew derate (≤60 ps).

## Pinout starting points

- QFN40: W1–10 control/clock/VREF, S11–20 A0–A9, E21–30 A10–A12/BA/
  power/NC, N31–40 DQ0–DQ7/DQS/DM. 39 used + 1 NC.
- QFN48: W1–12 control/clock/VREF/VSS/VDD, S13–24 A0–A11, E25–36
  A12/BA/power, N37–48 DQ0–DQ7/DQS/DM/VSSIO/VDDIO. 32 signal + 16 power.

Both pinouts still need lead-to-lead coupling, return-path, bondwire
crossing and package-house rule checks before freezing.

## Files

- `reports/ddr1/qfn40_pkg_rlc.json`, `qfn48_pkg_rlc.json`,
  `qfn32_template_pkg_rlc.json` — per-pin first-order RLC.
- `spice/package/qfn40_pkg.spice`, `spice/package/qfn48_pkg.spice` — generic
  ngspice series R-L + shunt C per package.
- `generator/extract_qfn_rlc.py` — bond-table → RLC.
- `generator/gen_qfn_padring_coupon.py` — parameterized 40/48-pad coupon GDS.
- `docs/PACKAGE_PADFRAME_PLAN.md` — full plan and references.
