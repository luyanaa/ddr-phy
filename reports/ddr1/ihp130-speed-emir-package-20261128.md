# IHP130 DDR1: speed, EM/IR, pad-macro and package closure (2026-11-28)

Status: experimental engineering note. **No signoff claim.** This note is a
follow-on to `ihp130-w12-pad-sdc-20261127.md` §6.8–§6.10. The RX 1.5 ns budget
question is closed for now; this note addresses 133.33/166.66 MHz, power
EM/IR, the first real pad-macro OpenROAD prototype, DQS-delay status and the
package/board timing budget.

## 0. Bottom line

| Item | Result | Confidence |
|---|---|---|
| 133.33 MHz, TT pad | **PASS** at `DQ_OE=800/1000/1200 ps`, `DQS_TX=PAD_TX=1242 ps`, `DQS_CAPTURE_DELAY=500 ps`, all three DRAM read corners | behavioural TB, one analog corner |
| 133.33 MHz, SS pad | **FAIL**: no overlap. `DQS_OE=1770 ps` fails tDS; `1775 ps` fails tDQSS. 5 ps gap | behavioural TB, one analog corner |
| 166.66 MHz, TT pad | **FAIL**: no overlap. `DQ_OE=1498 ps` fails tDS; `1500 ps` fails tDH. ~2 ps gap | behavioural TB |
| 166.66 MHz, SS pad | **FAIL**: tDQSS over the swept OE range | behavioural TB |
| Power, TT vectorless | 7.81 mW; VPWR worst IR 0.633 mV (0.05%); EM peak wire 34.3 µA | first-order OpenROAD PSM |
| Power, SS/FF | 6.14 / 9.64 mW; IR 0.550 / 0.726 mV | first-order OpenROAD PSM |
| Pad macro LEF | Generated, 125.67 × 206.91 µm, 9 pins, OpenROAD-readable | packaging abstract only |
| 8-lane chip-top prototype | 1050 × 950 µm die, global + detailed route complete, 0 DRT violations | floorplan/route feasibility only |
| Package + board estimate | 61 ps package flight worst, 68 ps total channel skew | analytical budget, not SI signoff |

The practical recommendation is: **keep 100 MHz as the release point; treat
133.33 MHz as an experimental TT-only point; drop 166.66 MHz for this pad.**
The SS 133 failure is a ~5 ps overlap failure in the write DQ/DQS window, not a
read-capture problem. It is too small to “fix” by adding another coarse
`#delay`; it needs a faster SS pad, a calibrated DQS phase trim, or a different
write-launch architecture.

## 1. Speed experiment, corrected setup

The earlier 7.5 ns / 6.0 ns experiments set `DQS_TX_PS=1980` while the TT pad
was `PAD_TX_PS=1242`. That is a 738 ps DQS-vs-DQ offset, not a matched launch.
It produced BAD_DQS faults and obscured the real window. The corrected rule is:

- `DQS_TX_PS` is an **absolute** delay, not an offset from `PAD_TX_PS`.
- For a matched launch, set `DQS_TX_PS = PAD_TX_PS`.
- `DQ_OE_PS` is the DQ output-enable delay; `PAD_OE_PS` is the DQS OE delay.
- `DQS_CAPTURE_DELAY_PS` shifts only the read capture strobe and must be
  recalibrated for the new `sys_clk` period.

The speed work used the temporary generator `/tmp/emit_ddr1_speed.py`, which
widens the CK range from the production 10–12 ns limit to 4–20 ns and fixes
`ROOT=/grid/ddr-phy`. It generated `/tmp/ddr1_speed_7500` (CK 7.5 ns,
133.33 MHz) and `/tmp/ddr1_speed_6000` (CK 6.0 ns, 166.66 MHz). The production
generator `generator/emit_ddr1.py` was not changed.

### 1.1 133.33 MHz

TT pad: `PAD_TX=1242 ps`, `PAD_RX=1207 ps`, `PAD_OE=1500 ps`,
`DQS_TX=1242 ps`, `DQS_CAPTURE_DELAY=500 ps`.

| `DQ_OE` | DRAM corner -1 | corner 0 | corner +1 |
|---:|---|---|---|
| 800 ps | PASS | PASS | PASS |
| 1000 ps | PASS | PASS | PASS |
| 1200 ps | PASS | PASS | PASS |

All nine runs end in `DDR1_LOOP_PASS`; the read capture delay 500 ps is the
value that also passes the fast DRAM corner. With 600 ps, corner +1 fails as a
PHY read fault (the same fixed `sys_clk` capture-slot mechanism documented in
§6.8 of the previous report).

SS pad: `PAD_TX=1980 ps`, `PAD_RX=1822 ps`, `PAD_OE` swept, `DQS_TX=1980 ps`.

| `PAD_OE` | Result |
|---:|---|
| 1700 ps | write beat 0 DQ=`zz` |
| 1760/1765/1770 ps | tDS violation |
| 1775/1780/1800/1900/2332 ps | tDQSS violation |

There is **no overlap**: at 1770 ps the DQ data is still too late for tDS; at
1775 ps the DQS edge is already outside the tDQSS window. Changing `DQ_OE`
from 1400 to 1780 ps or `DQ_TX` from 1800 to 1950 ps does not remove the
tDS failure at the tDQSS-passing OE point. The SS write window is closed by
about 5 ps.

This is a much narrower failure than the earlier “SS has no overlap over
hundreds of ps” description. It means a 5–10 ps DQS phase trim or a slightly
faster SS TX fall could open it; it does **not** mean the whole 133 MHz mode is
architecturally impossible.

### 1.2 166.66 MHz

TT pad, `PAD_TX=1242 ps`, `DQS_TX=1242 ps`, `DQS_CAPTURE_DELAY=500 ps`:

| `DQ_OE` | Result |
|---:|---|
| 1400/1420/1440/1450/1460/1480/1485/1490/1495/1497/1498 ps | tDS violation |
| 1500 ps and above | tDH violation (or DQ `zz` at 1800+) |

The TT tDS→tDH boundary is between 1498 and 1500 ps: about **2 ps**. There is
no passing point. SS is worse: the tested points fail tDQSS (this is not a
full SS sweep). Changing
`DQ_TX` to 1180–1220 ps or `PAD_OE` to 1400–1600 ps does not create an
overlap.

### 1.3 Interpretation

At 166.66 MHz the UI is 6.0 ns and the SS pad TX fall is 1.98 ns. The pad is
already one third of a UI slow; the remaining tDS/tDH window is below the
resolution of a single `#delay` launch. At 133.33 MHz the UI is 7.5 ns and the
TT pad has enough margin, but the SS pad does not. The next architecture step
is not another OE sweep: it is a **DQS phase interpolator / quarter-cycle
delay with 5–10 ps trim**, plus a capture-slot retune. The pending DQS delay
instance is the natural place for that, but it is not yet trustworthy.

These are behavioural results with the pad model, not full PVT. No jitter,
SSO, package flight or silicon corner interpolation is included. Treat the
TT pass as a green light for a 133 MHz experiment, not as a production
release.

## 2. Power EM/IR, first pass

### 2.1 Method

Reproducer: `scripts/run_ddr1_emir.sh`. It loads
`flow/runs/ihp130-ddr1_top/final/odb/ddr1_top.odb`, reads the matching
`sg13g2_stdcell` liberty, links the block hierarchically (the top is already a
hard macro, so the top-level `link_design -hier` prints `cell type ddr1_top
can not be linked` but the standard-cell instances link correctly), then runs
`report_power`, `set_pdnsim_net_voltage` and `analyze_power_grid` on VPWR and
VGND. `-source_type FULL` means every power-grid node is treated as an ideal
source; this is a **lower bound** on IR drop.

### 2.2 Results

| Corner | Total power | VPWR avg drop | VPWR worst drop | VPWR % | VGND worst drop | EM peak wire current |
|---|---:|---:|---:|---:|---:|---:|
| TT 1.20 V / 25 °C | 7.81 mW | 0.160 mV | 0.633 mV | 0.05% | 0.506 mV | 34.3 µA |
| SS 1.08 V / 125 °C | 6.14 mW | 0.140 mV | 0.550 mV | 0.05% | 0.441 mV | 29.8 µA |
| FF 1.32 V / -40 °C | 9.64 mW | 0.179 mV | 0.726 mV | 0.06% | 0.577 mV | 39.3 µA |

Power split at TT: sequential 4.58 mW (58.6%), combinational 3.22 mW
(41.2%), clock 0.016 mW (0.2%), leakage 0.017 mW (0.2%). The sequential
domination is expected for the controller/PHY flop count; the clock tree is
already small after the CTS split.

EM: the peak wire segment is on Metal1, 0.16 µm width, 34.3 µA at TT
(0.214 mA/µm). Metal1 `DCCURRENTDENSITY AVERAGE` is 1 mA/µm, so the
vectorless average current density is about 21% of the limit. The peak via
stack current is also 34.3 µA; Via1’s 0.4 mA limit is far away. There is no
EM violation in this vectorless average analysis.

The existing `metrics.json` reports a worst VPWR drop of 1.465 mV, larger
than the 0.633 mV above. That metric came from a different PDN source /
activity setup. Both are small; the difference is a reminder that PSM results
are assumption-driven.

### 2.3 What this does and does not prove

It proves:

- All VPWR/VGND shapes are connected (`PSM-0040` for both nets).
- At the default vectorless activity, IR is sub-mV and EM average current
  density is far below the tech limit at all three corners.
- There is no geometric power-grid violation.

It does **not** prove:

- Peak `di/dt` / SSO. `analyze_power_grid` is a static average-current solver.
- A realistic source location. `FULL` makes every grid node ideal; a real
  QFN bond pad / power ring source will increase the drop.
- Activity. There is no VCD/SAIF from the DDR1 loop; `set_power_activity
  -global` did not change the reported total in this build. The total is the
  vectorless default, not a workload.
- Electromigration at high-temperature/AC. Only the LEF `DCCURRENTDENSITY
  AVERAGE` check is represented.

To make this a closure item, the next run needs a gate-level VCD/SAIF
(`final/sdf` + a DDR1 gate TB), a `vsrc` at the actual bond pads (not `FULL`),
and a peak-current/SSO check. `design__power_grid_violation__count=0` in
`metrics.json` is only a geometric/connectivity check and must not be quoted
as IR/EM signoff.

## 3. Real pad macro and OpenROAD chip-top prototype

### 3.1 What the gf180mcu chip-top flow actually provides

The working gf180mcu SDRAM chip-top work uses:

- `generator/emit_chip_top.py` — builds a flattened structural P&R netlist of
  pad tiles + `sdram_phy_core`.
- `flow/chiptop_build/chiptop.tcl` — reads tech/cell/pad/core LEF, links the
  flattened netlist, makes a fixed die/core, places macros FIRM, then
  `global_route` + `detailed_route` and writes DEF/ODB.

The pattern is useful: **flatten the pad connections, use real LEF macros,
fix the pad ring and core, route**. It is not directly reusable as-is:

- The Python `tile_placement()` returns coordinates around 140–1710 µm, but
  the checked-in Tcl uses 527000–3180000 DBU coordinates on a 1800 µm die.
  The two placement descriptions do not agree.
- There is no PDN generation in `chiptop.tcl`; macro power pins are omitted
  from the netlist. It is a signal-route prototype, not a power-complete
  chip.
- It has no pad-ring DRC/LVS/ESD or package bondplan step.

So: use it as a **flow skeleton**, not as a golden reference.

### 3.2 Pad macro LEF

`scripts/emit_pad_macro_lef.py` reads the opt1 GDS, finds the nine port text
labels, and writes a BLOCK LEF:

- `SIZE 125.670 BY 206.910` µm.
- `OUT`, `IN`, `OE`, `VDD`, `PU_OK`, `VREF` on Metal1 at the bottom edge.
- `PAD`, `VSSIO`, `VDDIO` on Metal5 at the top edge.
- A conservative `OBS` keeps the bottom 4 µm and top 5 µm strips clear; the
  middle Metal1–Metal5 is blocked.
- Output: `flow/ihp130_chiptop_build/macro/sstl2_dq.lef` (source: `results/ihp130/sstl2-dq-w12-opt1/macro/sstl2_dq.lef`).

This is a **packaging/floorplanning abstract**, not a signoff LEF. The pins are
1 × 1 µm rectangles around the GDS labels; real pin access, enclosure,
antenna, ESD and latch-up need to be checked after the pad ring is frozen. The
GDS top cell already matches the LEF macro name `ihp130_sstl2_dq`.

### 3.3 Eight-lane OpenROAD prototype

Files are in `flow/ihp130_chiptop_build/`:

- `ddr1_pad_top_pnr.v` — `ddr1_top` + 8 × `ihp130_sstl2_dq`, DQ only.
- `ddr1_pad_top.tcl` — LEF read, link, 1050 × 950 µm floorplan, FIRM
  placement, global route.
- `ddr1_pad_top_drt.tcl` — detailed route.
- `ddr1_pad_top_grt.def`, `ddr1_pad_top_routed.def`, `.odb`, `_drc.rpt`.

Placement:

- Core at (202.2, 245.0) µm, 645.61 × 664.33 µm.
- Eight pads at y=0, x=22.3 + 125.67·i µm, orientation R180 so the Metal1
  signal pins face the core and the Metal5 PAD pins face the die edge.
- Die 1050 × 950 µm; core-to-pad channel 38.09 µm.

Route result:

- Global route: 17 nets, 13.15 mm wirelength, 0.54% total congestion, no
  overflow.
- Detailed route: 12.43 mm wirelength, 74 vias, all on Metal1–Metal3,
  **0 violations in `ddr1_pad_top_drc.rpt`** (empty report).
- This is a hard-macro route; there are no stdcells to place or optimize.
  It does not exercise the digital core’s timing, CTS or signal integrity.

The prototype image is `docs/images/ddr1_pad_top_proto.png` (source: `results/ihp130/ddr1_pad_top_proto.png`; rendered from
the routed DEF). It is a floorplan/route feasibility view, not a chip layout.

### 3.4 Area and pad-ring reality check

- Prototype die: 1050 × 950 µm = 0.9975 mm².
- Core macro: 428,898 µm².
- Eight pad macros: 8 × 125.67 × 206.91 = 207,990 µm².
- Total instance area: 636,917 µm², 63.9% of the prototype die.
- A full DDR1 x8 ring needs about 32 signal pads (8 DQ + DQS + DM + CK/CK# +
  13 A + 2 BA + 5 control). At 26,006 µm² per pad macro that is 832,192 µm²
  before power pads. With the 428,898 µm² core, active macro area alone is
  about 1.261 mm².
- The pad macro is 206.91 µm deep. A core of 645.61 × 664.33 µm plus a
  207 µm pad depth on every side needs a die of at least about
  1060 × 1078 µm just for the four sides, before routing gaps and power pads.
  A 32-pad single ring on a 1.1 mm die has only 4.4 mm perimeter; 32 × 125.67
  µm = 4.02 mm, leaving almost nothing for corners, power pads and bond-pad
  pitch. A realistic full-ring die is **1.3 × 1.3 mm or larger**, or the pad
  macro must be re-laid out with a narrower digital/analog footprint.

QFN48 7 × 7 mm can physically host a 1.3 mm die, but the bond wires get longer
than the 2.4 mm-die coupon (2.05–2.74 mm), so the package RLC must be
re-extracted. QFN64 has no project bondplan/RLC yet; it could be the better
choice if more power/ground pins are needed, but it is not a solved option.

### 3.5 What is still missing from the pad ring

- Only the DQ lane exists as a hard macro. DQS, DM, CK/CK#, CA and power/ground
  pads are still behavioural or absent.
- No level-shifter / 3.3 V-to-1.2 V interface ring around the digital core.
- No shared ESD clamp / pad-ring ESD network, no latch-up ring.
- No power pad ring, no PDN in the chip-top prototype; the 8-lane route has
  unconnected power pins by construction.
- No LVS/DRC on the merged pad ring; the single-lane opt1 DRC/LVS result does
  not transfer to an 8/32-lane ring.
- The pad LEF pin access is a 1 µm abstract; it has not been through real
  detailed routing at the pad edge with the ESD/guard ring.

This prototype answers “can the existing hard macros be packaged and routed by
OpenROAD?” with **yes, for the DQ group**. It does not answer “is the pad ring
tapeout-ready?” — that is still a full custom-layout task.

## 4. DQS delay instance status

**2026-11-28 update: the ideal `#delay` has been replaced.**  The wrapper now
uses the repaired 128-tap `DDR1_DQS_DELAY_LINE_PHYS` (2 fine cells/tap,
7-bit code), and `ddr1_ihp130_io.sv` instantiates it.  `ddr1_top` defaults to
`TAP_BITS=7` and applies `DQS_TAP_CODE` once at startup when training is off.
`read_capture_busy` gates delay-line updates to idle windows.  The 100 MHz
TT and SS regressions pass with the line at code 9/35 ps and 5/61 ps
respectively.  The 133/166 MHz sweeps in this report are still ideal-delay
results and must be re-run with the line before they are quoted as physical.

Remaining limits: `LINE_IMPL=0` is the behavioral cell model in simulation;
there is no routed IHP130 structural delay line, no SDF/GLS, and the hardened
`ddr1_top` ODB still has the old 4-bit tap port.  The 133 TT 500 ps target is
therefore still not proven on a physical line.

The instance cannot fix the SS **write** tDS/tDQSS gap; that is a TX launch
problem. It can fix the read capture slot and track PVT once it works.

## 5. Package and board SI budget

`scripts/pkg_si_budget.py` reads `reports/ddr1/qfn48_pkg_rlc.json` and adds an
explicit board estimate. Output: `reports/ddr1/pkg_si_budget.json`.

QFN48 coupon (2.4 mm die):

- L 2.1945–3.0365 nH, R 0.10818–0.14196 Ω, C 0.1 pF.
- `L/50Ω` flight 43.89–60.73 ps; `sqrt(LC)` 14.81–17.43 ps.
- Pin-to-pin flight skew 16.84 ps.
- The current SDC `PKG_FLIGHT=0.050 ns` is **below the 0.061 ns worst case**.
  For a common flight this cancels in DQ-vs-DQS timing, but it is not a
  conservative number; use 0.061 ns for the package term.

Board estimate (explicitly a placeholder):

- 4-layer FR4, 50 Ω microstrip, 25 mm, εeff 3.4, 6.2 ps/mm.
- Absolute flight 155 ps; 5 mm length mismatch = 31 ps; connector/SSN 20 ps.
- Total channel skew = 16.84 + 31 + 20 = **67.84 ps**.
- At 133.33 MHz (7.5 ns UI) that is 0.90% UI; at 166.66 MHz (6.0 ns UI) it
  is 1.13% UI. The absolute 216 ps flight is matched and should not be added
  directly to the internal SDC; the skew is the term that matters.

Recommended SDC experiment:

```tcl
set PKG_FLIGHT   0.061
set CHANNEL_SKEW 0.068
set_clock_uncertainty -setup [expr {0.200 + $CHANNEL_SKEW}] [get_clocks {sys_clk ck ck90 dqs_capture pad_ck pad_ck_n}]
set_clock_uncertainty -hold  [expr {0.050 + $CHANNEL_SKEW}] [get_clocks {sys_clk ck ck90 dqs_capture pad_ck pad_ck_n}]
```

This is deliberately conservative: it assumes no DQS training removes the
channel skew. `TRAIN_ENABLE=0` in the current top, so that is the honest
assumption today. The experimental file is `flow/ddr1_top_realio_pkg.sdc`
(not a replacement for the signoff SDC). A quick OpenROAD typ-corner replay
with the final ODB/SPEF and the stdcell typ liberty gives:

| SDC | worst setup slack | worst hold slack |
|---|---:|---:|
| `flow/ddr1_top_realio.sdc` (PKG_FLIGHT=0.050) | +1.54 ns | +0.19 ns |
| `flow/ddr1_top_realio_pkg.sdc` (0.061 + 0.068 skew) | +1.48 ns | +0.12 ns |

The deltas are 60–70 ps, as expected from the added 18 ps package flight and
68 ps channel uncertainty. Both remain positive at this typ point, but this is
a standalone replay, not the full multi-corner STA; the `metrics.json` numbers
(+1.128/+0.114 ns) remain the flow-of-record values. Do not freeze this into
the signoff SDC until the board stack-up/length table and the QFN64-vs-QFN48
decision are real.

What is still absent: IBIS models, 3D EM of the package, VTT/VREF decoupling,
SSN/return-path analysis, and a per-pin bondplan for the actual die size.
The current QFN48 RLC is a coupon model for a 2.4 mm die; the prototype die is
1.05 mm and a full ring is ~1.3 mm, so the wire lengths and L/R values must be
re-extracted before this budget is used for signoff.

## 6. Remaining IHP130 DDR1 closure gaps (outside RX 1.65 ns)

1. **SS write window at 133.33 MHz** — 5 ps tDS/tDQSS overlap failure. Needs a
   faster SS pad or a calibrated DQS phase trim; not fixable by another OE
   sweep.
2. **166.66 MHz** — ~2 ps TT tDS/tDH gap; SS fails tDQSS. Not a viable target
   for this pad without an architecture change.
3. **Full PVT** — the speed matrix is one TT and one SS analog pad point plus
   three DRAM read corners. No FF/SS digital timing, jitter, SSO or silicon
   interpolation.
4. **Power EM/IR signoff** — vectorless average only; `FULL` ideal source;
   no VCD/SAIF, peak current or bond-pad `vsrc`. The 0.633 mV number is a
   lower bound, not a signoff result.
5. **Pad ring** — only one DQ lane macro; no DQS/DM/CK/CA/power pads, no
   level shifters, no ESD/latch-up ring, no merged-ring DRC/LVS.
6. **Chip-top PDN** — the 8-lane prototype does not connect power pins; no
   power pad ring or package-aware PDN.
7. **DQS delay instance** — RTL integration is done: repaired 128-tap wrapper
   replaces the ideal `#delay` in `ddr1_ihp130_io`, and 100 MHz TT/SS pass in
   behavioral simulation.  Still open: structural IHP130 line/SDF/GLS, PVT
   tap calibration, and a hardened top re-run with the 7-bit tap port.
8. **Package SI** — QFN48 first-order RLC only, QFN64 has no bondplan/RLC;
   `PKG_FLIGHT=0.050` is a placeholder; no IBIS/3D EM/VTT/VREF/SSN.
9. **Post-route GLS** — the DDR1 SDF exists but there is no DDR1 gate-level TB
   consuming it; `dqs_capture` is still an asynchronous group, 41
   unannotated nets, `t_uncertainty` 0.200/0.050.
10. **DRAM model** — clean-room 32 MiB x8 single-rank BL4 CL2; no vendor
    MT46V32M8 differential, no BL8/CL3/auto-precharge/DLL-off coverage; read
    eye `S500/SSO300` still fails.
11. **Package selection** — QFN48 vs QFN64 not frozen; actual leadframe,
    gold-wire diameter and 64-pad bondplan are vendor inputs.
12. **Board** — flight/length/VTT/VREF assumptions are estimates, not a
    characterized board.

## 7. Recommended next actions

1. Freeze 100 MHz as the release point. Keep 133.33 MHz as an experimental
   TT-only mode; do not claim SS or production.
2. Re-run the 133 TT capture sweep and the SS 1770/1775 ps boundary with the
   repaired line (the earlier sweeps were ideal-delay only). Target a 5–10 ps
   trim, not a bulk OE change.
3. Decide 133 vs 166: 166 should be dropped for this pad unless a quarter-cycle
   launch or a faster pad is funded.
4. Generate a gate-level VCD/SAIF and run PSM with a bond-pad `vsrc`; replace
   the vectorless `FULL` lower bound.
5. Build the remaining pad variants (DQS/DM/CK/CA/power) and a 32-pad ring;
   run merged DRC/LVS and a PDN-enabled chip-top.
6. Re-extract QFN48 RLC for a 1.3 mm die or get QFN64 bondplan/RLC; replace
   `PKG_FLIGHT=0.050` with 0.061 and add 0.068 ns channel skew in the
   experimental SDC.

## 8. Reproducers and artifacts

- Speed: `/tmp/emit_ddr1_speed.py`, `/tmp/ddr1_speed_7500/`,
  `/tmp/ddr1_speed_6000/`; logs `m2_*`, `tt133_*`, `ss133*`, `tt166*`.
- EM/IR: `scripts/run_ddr1_emir.sh`; `reports/ddr1/emir/` (power, IR, EM
  reports for typ/slow/fast).
- Pad macro: `scripts/emit_pad_macro_lef.py`;
  `flow/ihp130_chiptop_build/macro/sstl2_dq.lef` (source: `results/ihp130/sstl2-dq-w12-opt1/macro/sstl2_dq.lef`).
- Chip-top prototype: `flow/ihp130_chiptop_build/`; image
  `docs/images/ddr1_pad_top_proto.png` (source: `results/ihp130/ddr1_pad_top_proto.png`).
- Package: `scripts/pkg_si_budget.py`; `reports/ddr1/pkg_si_budget.json`.
- Previous RX/PEX closure: `reports/ddr1/ihp130-w12-pad-sdc-20261127.md`
  §6.8–§6.10.
