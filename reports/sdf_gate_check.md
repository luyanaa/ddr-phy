# SDF-annotated gate-level check

**Status: PASS.** `sh sim/sdf_gate_check.sh` drives the post-PnR netlist with
the max_ss SDF and confirms the P1-3 half-cycle launch survives synthesis
and place-and-route.

```text
dq_o/dq_oe transitions: rising=0 falling=2
PASS sdf-gate-check
```

`rising=0` is the important number: every dq_o / dq_oe transition happens
while clk is low, i.e. on the falling edge, which is what gives the write
setup margin its half-cycle advance.

## 1. Two real defects the flow found

### (a) negedge launch was turned into posedge by synthesis

The first SDF run showed the netlist clocking the launch flops from the same
posedge tree as everything else; the synthesis log confirmed yosys built a
plain `$dff` for `dq_o_q`. The RTL said `always @(negedge clk)`.

Fix: derive an explicit inverted clock.

```verilog
wire clk_n = ~clk;
always @(posedge clk_n or posedge rst) ...
```

The post-PnR netlist now clocks them from inverter outputs (`net82/83/84`).

### (b) flops with no reset pin, so the gate-level datapath stayed X

`rst ? ... : ...` inside a synchronous always block makes yosys emit
`dfxtp` cells, which have **no reset pin**. The gate-level netlist then
starts at X and never clears, regardless of `rst`.

Fix: asynchronous reset on the dq datapath (`always @(posedge clk or
posedge rst)`), which maps to `dfrtp`. The command/status registers keep
the synchronous form deliberately - an async-reset mux on that path cost
0.17 ns of CMD_TX setup (measured: setup went +0.139 -> -0.169 ns and
recovered when reverted).

## 2. Simulation gotcha (documented, not a design issue)

iverilog leaves every sky130 flop at X unless the cells are compiled with
`-DFUNCTIONAL`. Without it the UDP timing variants are selected and even a
bare `dfrtp_2` with `RESET_B=0` still reads X (verified in isolation).
`sim/sdf_gate_check.sh` therefore compiles with `-g2005-sv -DFUNCTIONAL`.

## 3. Constrained PnR after the RTL changes

| corner | setup ws | hold ws |
|---|---|---|
| max_ss_100C_1v60 | +0.139 ns | +0.266 ns |

Flow complete, GDS/SDF/SPEF emitted, `sim/run.sh` 9/9 PASS.

## 4. Scope

This checks `sdr_phy` - the digital core - on sky130, with the max_ss SDF.
It does not cover `sdram_phy_top`, the GF180 backend, or the pad macro.
