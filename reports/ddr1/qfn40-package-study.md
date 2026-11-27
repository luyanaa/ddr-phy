# QFN40 package study for IHP130 DDR1

Status: first-order package/padring study, **signoff=false**. Full rationale
and pin-budget tables are in `docs/PACKAGE_PADFRAME_PLAN.md`.

## Result

Full x8 DDR1 needs 32 signal pins plus at least 5 power/reference pins
(37 total), or 39 with duplicated VDDIO/VSSIO. QFN24/28/32 cannot carry it;
QFN40 6x6 is the minimum (39 used + 1 NC); QFN48 7x7 is the safer choice.

A 2.0 mm × 2.0 mm, 40-pad coupon die was run through the IHP AMS template's
`run_bondplan.py` in `OP_QFN40_6x6mm`:

| Metric | QFN32 template | QFN40 coupon |
|---|---:|---:|
| Die | 1.6 mm | 2.0 mm |
| Bondwires | 32 | 40 |
| Wire length | 1296–1701 µm | 1771–2459 µm |
| Series L (25 µm Au + lead allowance) | 1.31–1.77 nH | 1.85–2.69 nH |
| Series R | 0.070–0.091 Ω | 0.094–0.128 Ω |
| 50 Ω L/R bound | 26–35 ps | 37–54 ps |

The QFN40 bondplan has a known pinout warning near pins 29/30 (two wires on
one lead, min gap −25 µm). It is deliberately kept as evidence that the
40-lead corner assignment must be re-run before freezing the pinout.

## Impact on the SS tDS failure

The SS 10 ns failure is a 168 ps first-write DQS tDS violation. The package
bound is 54 ps; the Open-Padrings 32 digital pad→core SPEF bound is
492 Ω × 0.086 pF ≈ 42 ps. Even summed, 96 ps < 168 ps. Packaging/padring
cannot explain the failure; pad TX/OE and DQS capture remain the primary
suspects.

Do not replace the behavioral pad model with package RLC. Keep
`rtl/ihp130_sstl2_dq_model.sv` for the digital boundary; attach
`spice/package/qfn40_pkg.spice` outside the transistor-level pad PEX, and
give the digital TB at most a bounded package skew derate (≤50 ps).

## Files

- `reports/ddr1/qfn40_pkg_rlc.json`, `qfn32_template_pkg_rlc.json` — per-pin
  first-order RLC.
- `spice/package/qfn40_pkg.spice` — generic ngspice series R-L + shunt C.
- `generator/extract_qfn_rlc.py` — bond-table → RLC.
- `generator/gen_qfn40_coupon.py` — 40-pad coupon GDS.
- `docs/PACKAGE_PADFRAME_PLAN.md` — full plan and references.
