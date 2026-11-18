# SDF-annotated gate-level check

**Status: the SDF flow runs and caught a real synthesis defect; the
functional assertion is still blocked on X-initialisation.**

## 1. What the run found (the important result)

The first SDF-annotated run exposed a synthesis bug that the unit tests and
the pre-layout STA both missed:

```text
pre-fix netlist:
  _112_.._115_  (.CLK(clknet_2_x__leaf_clk_regs))   <- rising edge
  _156_.._158_  (.CLK(net89/90/91))                 <- also rising
  net89/90/91   <- driven by inv_2 from the same clknet
```

Yosys turned `always @(negedge clk)` into ordinary rising-edge flops: the
synthesis log shows `Creating register for dq_o_q ... ($dff)` with no edge
qualifier. That silently destroys the half-cycle write advance that the
P1-3 write-setup margin (+1.78 ns at ss) depends on - the STA number was
correct for the RTL but wrong for the netlist.

## 2. Fix

`rtl/sdr_phy.sv` now derives an explicit inverted clock:

```verilog
wire clk_n = ~clk;
always @(posedge clk_n) begin
    dq_o <= dq_o_q; dm <= dm_q; dq_oe <= dq_oe_q;
end
```

After re-running PnR the launch flops are clocked from inverter outputs:

```text
_156_ (.CLK(net89))  _157_ (.CLK(net90))  _158_ (.CLK(net91))
_103__89 (.A(clknet_2_1__leaf_clk_regs), .Y(net89))   <- real inversion
```

So the falling-edge launch now survives synthesis. `sim/run.sh` still passes
9/9 and the constrained PnR keeps setup +0.222 ns / hold +0.248 ns.

## 3. Still blocked

The functional assertion in `sim/tb_sdf_gate.sv` (dq_o must change only on a
falling edge and must carry the written byte) does not run yet: the post-PnR
netlist uses `dfxtp` cells with **no reset pin**, so `rst` cannot clear X and
`dq_o` stays `xx`. The testbench forces all 53 flop outputs at time 0.5 ns
and releases them at 20.5 ns, but the datapath still resolves to X.

Next concrete step: initialise through the clock-tree inputs instead (drive
`rst` long enough for the combinational reset path to propagate, or add
`+define+RANDOM_SEED`-free initial blocks in a netlist wrapper), and only
then assert the edge/値 checks.

## 4. What is already proven

| claim | evidence |
|---|---|
| SDF annotates and the gate netlist simulates | `reports/sdf_gate_check.log`, `$sdf_annotate` accepted |
| the negedge launch was lost in synthesis | netlist before/after diff above |
| the fix survives PnR | `_156_.._158_` clocked from `inv_2` outputs |
| functional behaviour unchanged | `sh sim/run.sh` 9/9 PASS |
| constrained PnR unaffected | setup +0.222, hold +0.248 ns |
