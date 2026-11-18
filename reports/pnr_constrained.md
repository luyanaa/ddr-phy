# Constrained LibreLane run (sdr_phy, sky130)

**Status: GO for the digital core, on sky130 stdcells, pre-layout pad.**
Every setup and hold corner is positive with the generated SDC wired in.
This is NOT the GF180 harden and NOT `sdram_phy_top` with the real pad.

## 1. What changed to make this run

`python3 generator/emit_sdc.py --check` now passes (0 TBD) and
`flow/config.librelane.json` wires the SDC in via `PNR_SDC_FILE` and
`SIGNOFF_SDC_FILE`. Two blockers had to be fixed first:

| blocker | fix |
|---|---|
| DPL-0036 at PostCTS | the 0.6 ns uncertainty makes hold repair insert ~57 buffers, so the core was resized from 40 % util / 50 % density to **25 % / 35 %** |
| OE_TURNAROUND -4.4 ns | the old `-max` form was `tCK - tLZ - toe_on - unc` = 1.6 ns, i.e. it demanded dq_oe within 1.6 ns. tLZ describes when the DRAM releases the bus, not a deadline for this register. Replaced with `pad_out_max + board_dq_max + unc` |

## 2. Result (`reports/pnr_sky130.json`)

| corner | setup ws (ns) | hold ws (ns) |
|---|---|---|
| max_ss_100C_1v60 | **+0.222** | +2.429 |
| max_tt_025C_1v80 | +1.363 | +0.918 |
| max_ff_n40C_1v95 | +1.530 | +0.254 |
| min_ss_100C_1v60 | +0.278 | +2.423 |
| min_tt_025C_1v80 | +1.369 | +0.914 |
| min_ff_n40C_1v95 | +1.535 | +0.248 |
| nom_ss_100C_1v60 | +0.251 | +2.427 |
| nom_tt_025C_1v80 | +1.367 | +0.917 |
| nom_ff_n40C_1v95 | +1.534 | +0.250 |

Worst setup **+0.222 ns** (ss), worst hold **+0.248 ns** (ff), TNS 0 in
both. The flow completes with `Flow complete` and emits GDS, SDF and SPEF
under `flow/runs/sky130/final/`.

Reproduce: `sh flow/run.sh sky130` then `python3 generator/check_pnr.py`.

## 3. Constraints that are measured vs assumed

Measured (P1-1..P1-4): `pad_out_min/max` 0.208/0.441, `pad_in_min/max`
-0.002/0.096, `toe_on/off` 0.608/3.299, `board_*` 0.337-0.348,
`tCLK_fwd` 0.385-1.349, `tDQ_tx` 0.715-2.711.

Explicit conservative bound, **not measured**: `t_uncertainty` 0.600 ns
(0.25 jitter/DCD + 0.20 OCV/PVT + 0.10 SSN + 0.05 pad skew). Replacing it
with a measured value is required before any signoff claim.

## 4. Not covered

- **The harden is `sdr_phy`, the digital core.** `sdram_phy_top` (with
  `clock_forward`, `read_capture_ctrl`, `dq_turnaround` and the GF180 pad
  macro) has not been through PnR.
- **sky130 standard cells, not GF180.** The GF180 run needs the
  `gf180-as-7t3v3` 3.3 V view under `./pdks`, which is still missing.
- SDF back-annotated gate-level simulation has not been run (the SDF is
  emitted, not exercised).
- The pad macro is not in this netlist, so the pad delays enter only
  through the SDC coefficients.

`reports/capability_report.md` stays `NO_GO`.
