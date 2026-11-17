# P1-3: CK output and end-to-end timing margins

**Status: NO_GO** (design assumption; unplaced STA netlist, first-pass pad fixture, no board/package terms).

Operating point `baseline_100_cl2`, tCK = 10.0 ns, device MT48LC16M16A2.

## Method

- Digital `clk -> pad` and `pad -> capture FF` delays: OpenSTA on a
  yosys-synthesised `sdram_phy_top` with the GF180 `mcu7t5v0` liberty
  (`reports/sta/`). Unplaced, zero wire load.
- Pad `OUT -> PAD` and `PAD -> IN` delays: ngspice on the sized pad
  slice (`reports/pad_delay_gf180mcuD_*.json`).
- Device terms: `specs/devices/micron_mt48lc16m16a2-75.yaml`.

## Per-corner results (ns)

| corner | tco_ck | tco_dq | pad_out | pad_in | tCLK,fwd | tDQ,tx | tDQ,rx | W setup | W hold | R setup | R hold | OE on | OE off |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| tt | 0.307-0.453 | 0.940-1.089 | 0.271-0.317 | 0.0079-0.0852 | 0.578-0.770 | 1.212-1.406 | 0.359-0.720 | -2.327 | +9.642 | +3.280 | +3.359 | +3.577 | +5.877 |
| ss | 0.616-0.907 | 1.878-2.219 | 0.375-0.441 | 0.0285-0.0960 | 0.992-1.349 | 2.254-2.660 | 0.719-1.379 | -3.168 | +10.105 | +2.621 | +3.719 | +3.408 | +5.737 |
| ff | 0.176-0.261 | 0.544-0.613 | 0.208-0.239 | -0.0023-0.0735 | 0.384-0.499 | 0.752-0.851 | 0.204-0.432 | -1.967 | +9.453 | +3.568 | +3.204 | +3.680 | +5.973 |

## Worst case

| check | margin (ns) |
|---|---|
| write_setup_ns | -3.168 |
| write_hold_ns | +9.453 |
| read_setup_ns | +2.621 |
| read_hold_ns | +3.204 |
| oe_off_ns | +5.737 |
| oe_on_ns | +3.408 |

## Reading

- Write setup is **negative**: the forwarded CK leaves the chip
  ~0.6 ns earlier than DQ (2-gate mux vs register + mux), so the
  DRAM sees DQ after its CK edge. This is the `assign ck = clk`
  limitation from `docs/TIMING_BUDGET.md` section 5, now with
  numbers. It needs a characterized CK phase/delay (gate G6) or a
  write-scheme change; no constraint tweak fixes it.

## Not included

- Board/package: included as the P1-4 channel (matched traces).
- The channel is a pre-layout RLC/T-line model, not an EM extraction.
- Clock jitter/DCD/OCV: the SDC uncertainty term is still TBD.
- Placement, routing, CTS, wire load, SDF back-annotation.
- OE turn-on: needs the DRAM release reference through the board.

`reports/capability_report.md` stays `NO_GO`.
