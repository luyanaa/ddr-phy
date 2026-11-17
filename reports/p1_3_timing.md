# P1-3: CK output and end-to-end timing margins

**Status: GO** (design assumption; unplaced STA netlist, first-pass pad fixture, no board/package terms).

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
| tt | 0.307-0.453 | 0.872-1.124 | 0.271-0.317 | 0.0079-0.0852 | 0.578-0.770 | 1.144-1.441 | 0.359-0.722 | +2.637 | +4.574 | +3.278 | +3.359 | +3.577 | +5.877 |
| ss | 0.616-0.907 | 1.737-2.269 | 0.375-0.441 | 0.0285-0.0960 | 0.992-1.349 | 2.112-2.711 | 0.719-1.383 | +1.781 | +4.963 | +2.617 | +3.719 | +3.408 | +5.737 |
| ff | 0.176-0.261 | 0.507-0.641 | 0.208-0.239 | -0.0023-0.0735 | 0.384-0.499 | 0.715-0.880 | 0.204-0.433 | +3.005 | +4.416 | +3.567 | +3.204 | +3.680 | +5.973 |

## Worst case

| check | margin (ns) |
|---|---|
| write_setup_ns | +1.781 |
| write_hold_ns | +4.416 |
| read_setup_ns | +2.617 |
| read_hold_ns | +3.204 |
| oe_off_ns | +5.737 |
| oe_on_ns | +3.408 |

## Reading


## Fix (P1-3 path B)

The negative write setup was structural. Path B is implemented in
`rtl/sdr_phy.sv`: the pin command is pipelined one cycle and DQ/DM/OE are
launched on the falling edge, so the DRAM sees the data half a period plus
a full period before the command edge it samples. The DFI read latency is
now CL+2. A characterised delay line (path A) was evaluated and removed:
its PVT slope is steeper than the DQ path and the ff corner stayed
negative.

| corner | write setup | write hold | read setup | read hold |
|---|---|---|---|---|
| tt | +2.637 | +4.574 | +3.278 | +3.359 |
| ss | +1.781 | +4.963 | +2.617 | +3.719 |
| ff | +3.005 | +4.416 | +3.567 | +3.204 |

## Not included

- Board/package: included as the P1-4 channel (matched traces).
- The channel is a pre-layout RLC/T-line model, not an EM extraction.
- Clock jitter/DCD/OCV: the SDC uncertainty term is still TBD.
- Placement, routing, CTS, wire load, SDF back-annotation.
- OE turn-on: needs the DRAM release reference through the board.

`reports/capability_report.md` stays `NO_GO`.
