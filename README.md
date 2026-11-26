# ddr-phy

An external-DRAM ASIC PHY for the [LiteDRAM](https://github.com/enjoy-digital/litedram) controller, covering four open PDKs: **sky130, gf180mcu, IHP SG13G2 (130 nm), and ICsprout 55**. The controller stays LiteDRAM, with its scheduling, refresh and interleaving unchanged; this repository provides a synthesizable digital PHY and hand-made I/O pads. All four processes share one digital PHY and one pad schematic. Only the devices and supplies change, not the architecture.

The authoritative record of design decisions, evidence boundaries and the phased plan is [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

> 中文版：[`README.zh-cn.md`](README.zh-cn.md)

## Design classes

| Class | Memory | Interface | Processes | VDDIO | Status |
|---|---|---|---|---|---|
| S | SDR SDRAM | Same DFI as `GENSDRPHY`, 1:1 | All four | 3.3 V | Digital core implemented, passes multi-level verification |
| D | DDR1 | New 1:2 DFI | sky130, IHP, ics55 | 2.5 V | Planned, RTL not started |
| D2 | DDR2 | LiteDRAM DDR2 DFI, 1:2, with ODT | 55 nm only (needs an in-house SSTL_18 IO) | 1.8 V | Long term |

The first silicon target is a single point-to-point x8 device, SDR at CK = 100 MHz. No DIMM, fly-by or write leveling; SPD and ECC are outside the PHY.

## Current progress (P0)

What exists on the Class S digital side:

- `rtl/sdr_phy.sv` — 1:1 SDR PHY, a synthesizable translation of `GENSDRPHY`: write latency 0, read latency CL+1, one register stage each for command/DQ/DM, tristate drive left to the pad.
- `rtl/sdram_phy_top.sv` — integration top: CK takes the dedicated `clock_forward` path, DQ goes through `dq_turnaround` + `phy_io_adapter`, and the first read-capture FF is clocked by `cap_clk` from `read_capture_ctrl`.
- `rtl/sdr_ctrl.sv` — a 1:1 controller for closed-loop testing (not the LiteDRAM netlist), copying `GENSDRPHY`'s DFI timing and initialization command sequence; WRITE is gated by the PHY's `turnaround_busy`; optional tREFI refresh.
- `rtl/sdr_bist.sv` — PRBS-8 write/read-compare BIST with optional `phase_sel` sweep. A diagnostic aid, not timing signoff, and it does not implement DRAM training.
- `rtl/read_capture_cdc.sv`, `rtl/dq_turnaround.sv`, `rtl/clock_forward.sv`, `rtl/phy_io_adapter.sv` — read-capture CDC, read/write turnaround guard, clock forwarding, pad adapter.

Verification and implementation evidence (layered; no level is claimed from a lower one):

1. **DFI behavior**: `tb/tb_sdr_phy.sv`, CL 2/3 × x8/x16 pass.
2. **Pin-level closed loop**: `sim/sdram_model.sv` + `tb/tb_sdr_loop.sv`; row hit, bank change, row change, masked write, BL 2/4/8 bursts pass. The model reports only command-order errors; it does not check tRCD/tRP/tRAS/tRFC.
3. **Command spacing**: `sim/sdram_checker.sv` counts clocks against the Micron 256Mb SDR -75 grade (tCK = 10 ns), one instance per rule.
4. **Timing-aware read capture**: `sim/sdram_timing_model.sv` + `sim/read_capture.sv`, phase sweep and negative tests (`sim/sweep.sh`); static phase 0/1/2 tests (`tb/tb_read_capture_phase.sv`).
5. **Gate-level function**: `sim/gate.sh` maps `sdr_phy` to sky130 HD and runs functional simulation. No SDF, no wire delay, no pads: not timing simulation, let alone signoff.
6. **Physical implementation**: `flow/` LibreLane; the sky130 control group runs 80/80 steps clean. The draft SDC is intentionally not wired in (see `docs/STA_PLAN.md` §5).
7. **Pads**: `generator/` produces topology templates for all four processes (`sch/pads/`); gf180mcuD / sky130 / IHP have devices bound and generated. There are ngspice simulations of the pre-driver + output stage / receiver slices and of ESD reverse leakage, tagged `design_assumption`. ics55 lacks a 3.3 V ESD diode SPICE card (`docs/ICS55_ESD_3V3.md`). Sizing is not signed off.
8. **Optional differential test**: `sim/micron_diff.sh` diffs against the Micron MT48LC16M16A2 behavioral model; the model is fetched locally, not distributed with the repo, and the test is skipped when it is absent.

CI (`.github/workflows/ci.yml`) runs the generator checks, artifact consistency, all RTL/model regressions, exit-code mutation tests (`sim/mutation.sh`, proving that a failing testbench really returns non-zero) and the optional Micron diff.

## Directory layout

```text
rtl/            synthesizable SystemVerilog: PHY, controller, BIST, read capture, turnaround, clock forwarding, pad adapter
tb/             testbenches (Icarus Verilog, -g2012)
sim/            behavioral/timing models, checkers, regression scripts, gate-level netlist shells
generator/      Python generators and evidence checks: pad topology, device extraction, PDK rules, timing, packaging
specs/          interface contract (interface.yaml), timing contract (timing_contract.yaml), device and pad specs
sch/pads/       generator output: pad topology templates and packaging-profile closure artifacts
backends/       per-PDK backend configs (sky130 / gf180mcu / ihp130 / ics55 / generic_sim)
flow/           LibreLane hardening flow (run.sh, config, draft SDC)
docs/           architecture and topic documents (Chinese)
third_party/    litedram (submodule, unmodified); reference/ (local evaluation models, not distributed)
results/        physical implementation outputs (gitignored)
```

## Quick start

Dependencies: Icarus Verilog, Yosys, Python 3 + PyYAML. The physical flow additionally needs a LibreLane environment (the script enters the `/opt/librelane` nix-shell automatically) and the corresponding PDK.

```sh
# Base regression: DFI behavior, pin-level model, controller closed loop, command-spacing checks
sh sim/run.sh

# Enhanced PHY modules, DQM read masking, BIST closed loop (x8 / x16)
sh sim/phy.sh

# Pad capability report + pad adapter contract tests
sh sim/pad.sh

# Timing-aware read-capture phase sweep + negative tests
sh sim/sweep.sh

# Exit-code mutation tests: injected errors must make the simulator exit non-zero
sh sim/mutation.sh

# Optional: Micron reference model diff (skipped if the model is absent; see docs/DRAM_MODEL_REFERENCES.md)
sh sim/micron_diff.sh

# sky130 HD functional gate level (no SDF)
sh sim/gate.sh

# Generator and evidence checks
python3 generator/check_pads.py
python3 generator/check_capabilities.py
python3 generator/check_timing.py

# LibreLane hardening: sky130 (default) / ihp130 / ics55 / gf180-as-7t3v3
sh flow/run.sh sky130
```

gf180 must use the 3.3 V AS standard-cell view (assemble it first under `./pdks/gf180mcuD`); the foundry 5 V cell library is not this PHY's spec.

## Documents

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — architecture decisions, DFI contract, hand-made I/O split, verification layers, phases and gaps
- [PHY_RTL_GAPS.md](docs/PHY_RTL_GAPS.md) — known RTL gaps
- [STA_PLAN.md](docs/STA_PLAN.md) / [TIMING_BUDGET.md](docs/TIMING_BUDGET.md) / [TIMING_SWEEP.md](docs/TIMING_SWEEP.md) — timing constraints and budget
- [PAD_GENERATOR.md](docs/PAD_GENERATOR.md) / [PAD_ADAPTER.md](docs/PAD_ADAPTER.md) — pad generator and adapter contract
- [ESD_STRESS_PLAN.md](docs/ESD_STRESS_PLAN.md) / [ICS55_ESD_3V3.md](docs/ICS55_ESD_3V3.md) — ESD plan and the ics55 3.3 V gap
- [DRAM_MODEL_REFERENCES.md](docs/DRAM_MODEL_REFERENCES.md) — sources and license boundaries of DRAM reference models
- [SI_PI_PACKAGE_PCB.md](docs/SI_PI_PACKAGE_PCB.md) / [PACKAGING_PROFILES.md](docs/PACKAGING_PROFILES.md) — package and board level

## License

Source code in this repository is **Apache-2.0** (see [LICENSE](LICENSE); source files carry SPDX headers). Third-party material has its own boundaries:

- `third_party/litedram` is a submodule under the BSD license (EnjoyDigital); this repository does not modify it.
- The Micron MT48LC16M16A2 behavioral model is "All rights reserved" and is **not distributed** with this repository; it is for local evaluation only (gitignored).
- The ICsprout 55 foundry SPICE models are vendor data, not covered by Apache-2.0, and are for teaching and research evaluation only; simulations using them are not signoff and cannot be treated as a redistributable PDK attachment.
- JEDEC standard text is not in this repository; default timing values come from secondary sources of public device datasheets, cited in the architecture document.
