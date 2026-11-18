# GF180 3.3 V standard-cell view and harden

**Status: GO.** Both `sdr_phy` and `sdram_phy_top` complete the constrained
LibreLane flow on GF180 3.3 V cells with every setup/hold corner positive.

## 1. The 3.3 V library

`/grid/gf180mcu` carries four 3.3 V libraries; the audit
(`/grid/gf180mcu/STDCELL_AUDIT_2026-10-28.md`) rates them:

| library | cells | note |
|---|---|---|
| **gf180mcu_as_sc_mcu7t3v3** | **107** | complete set, Liberty/LEF/GDS/SPICE; used here |
| gf180mcu_osu_sc_gp9t3v3 | 44 | LEF missing power pins |
| gf180mcu_osu_sc_gp12t3v3 | 35 | 8-10 functional cells absent from NLDM |
| gf180mcu_ocd_sc_rt12t3v3 | 26 | rad-hard ELT; no Liberty |

The Avalon 7-track library is the only one with the full set, so it is what
`flow/run.sh gf180-as-7t3v3` uses.

View wiring (LibreLane needs a PDK root it can `--manual-pdk` against):

```sh
mkdir -p pdks/gf180mcuD
ln -s <gf180mcuD>/libs.ref  pdks/gf180mcuD/libs.ref
ln -s <gf180mcuD>/libs.tech pdks/gf180mcuD/libs.tech
```

The CIEL `gf180mcuD` already contains `gf180mcu_as_sc_mcu7t3v3` with the same
three corners (tt 3.30 / ss 3.00 125C / ff 3.60 -40C).

## 2. Results

### sdr_phy (digital core)

| item | value |
|---|---|
| instances | 1086 |
| die area | 25 579 um2 |
| worst setup | **+0.999 ns** |
| worst hold | **+0.150 ns** |

### sdram_phy_top (clock_forward + read_capture_ctrl/cdc + dq_turnaround + phy_io_adapter)

| corner | setup | hold |
|---|---|---|
| max_ss_125C_3v00 | **+1.265** | +0.591 |
| max_tt_025C_3v30 | +1.602 | +0.293 |
| max_ff_n40C_3v60 | +1.670 | +0.106 |
| min_ss_125C_3v00 | +1.276 | +0.582 |
| min_tt_025C_3v30 | +1.605 | +0.286 |
| min_ff_n40C_3v60 | +1.673 | +0.100 |
| nom_ss_125C_3v00 | +1.274 | +0.586 |
| nom_tt_025C_3v30 | +1.604 | +0.289 |
| nom_ff_n40C_3v60 | +1.672 | +0.103 |

instances 2244, die 48 078 um2. GDS and SDF under
`flow/runs/gf180-as-7t3v3-sdram_phy_top/final/`.

Reproduce:

```sh
sh sim/gf180_pnr.sh          # sdr_phy
sh sim/gf180_pnr.sh top      # sdram_phy_top
```

## 3. What had to change

- **`flow/config.sdram_phy_top.json`**: the top has no `ck` port (the core's
  `ck` is deliberately unconnected; the forwarded clock is `pad_ck`), and it
  packs command/address into `pad_cmd` and data into the bidirectional
  `pad_dq`. `generator/emit_sdc.py` now emits a matching
  `flow/sdram_phy_top.sdc` with those port sets.
- **`flow/run.sh`**: `TOP=<name>` selects `flow/config.<name>.json` and uses a
  distinct run tag, so the core and top hardens no longer overwrite each
  other.
- **`sim/pad_cell_sta_stub.sv`** is in the top's file list: the simulation pad
  model uses fork/join_none and cannot be synthesised; the stub is a
  zero-delay boundary so the pad macro stays outside the netlist.

## 4. Not covered

- **The pad macro is not in these netlists.** `pad_cell_sta_stub` is a
  zero-delay model, so pad delays enter only through the SDC coefficients.
  Integrating the real `gf180_pad_core` GDS into the harden is a separate
  step.
- DRC/LVS on the GF180 harden: the flow ran its own checks, but the pad-ring
  level verification is still the hierarchical script.
- SDF gate-level simulation on GF180 (only the sky130 one exists).
- `t_uncertainty` is still the 0.600 ns conservative bound.
