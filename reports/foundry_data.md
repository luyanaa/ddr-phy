# Foundry / assembly-house data for the deferred pdk_rules

Located 2026-11-16. Source: GlobalFoundries GF180MCU PDK Design Rule Manual (readthedocs.io) (Experimental Preview / work in progress).

**These are DRM design-rule DEFAULTS, not assembly-house commitments,
and not proof that any DRC ran.** drc_clean stays false, capability stays NO_GO.

| rule | match | decision | value | section |
|---|---|---|---|---|
| METAL_JMAX | exact | fill | 0.67 mA/um | 14.2 Electro-migration, Table 14.3 |
| GUARD_RING_RULE_MIN | exact | fill | 2 um | 14.3.2 I/O Latch-up Related Rules, IO.2 / IO.4 |
| PAD_OPENING | exact | defer | - | 9.2 Bond Pad Guidelines, PAD.1 |
| PAD_PITCH | none | defer | - | 9.0 Bond Pad |
| ESD_AREA_MIN | derived | defer | - | 14.5.2 ESD Performance from 3.3V LV N+/PWELL diode; 14.4.2 Design Guidelines |
| IO_CURRENT | none | defer | - | - |
| DQ_BIT_SKEW_MAX | none | defer | - | - |
| RAIL_WIDTH | derived | defer | - | - |

## Filled (semantic match exact)

- **METAL_JMAX = 0.67 mA/um** (14.2 Electro-migration, Table 14.3). Table 14.3, Metal 1 - Top Metal-1, Unidirectional, 125 deg C (most conservative column). Value = 0.67 mA/um = 6.7e-4 A/um.
  - source: https://gf180mcu-pdk.readthedocs.io/en/latest/physical_verification/design_manual/drm_14_2.html
  - caveat: Per DRAWN WIDTH; layer- and temperature-dependent. Other columns: MetalTop 11kA uni 125C = 1.5 mA/um, 30kA = 5.37 mA/um; bi-directional is higher.
  - caveat: Reliability basis: T0.1 > 100K hours at 85 deg C. Choosing 125 deg C is conservative for a 3.3V SDR pad.
  - caveat: A VDDIO rail is unidirectional; DQ would use bi-directional. Selection must be revisited if the rail uses MetalTop.
- **GUARD_RING_RULE_MIN = 2 um** (14.3.2 I/O Latch-up Related Rules, IO.2 / IO.4). DRM 14.3.2 IO.2 / IO.4 'Minimum recommended ... guard ring width' = 2um for LV and MV (Comment column: Rule).
  - source: https://gf180mcu-pdk.readthedocs.io/en/latest/physical_verification/design_manual/drm_14_3_2.html
  - caveat: This is the I/O latch-up guard-ring WIDTH rule that the parameter names - unlike guard_ring.rb GR.* (seal-ring-to-die-edge), which is different physics.
  - caveat: Wording is 'minimum recommended' though the table Comment says Rule.
  - caveat: Adjacent rules (not this parameter): IO.1/IO.3 max guard-ring-to-diffusion space 15um; max tap distances 2um / 5um.

## Why the other 6 remain TBD

- **PAD_OPENING**: Assembly-house confirmation required; do not freeze a DRC default as a design constraint.
  - source: https://gf180mcu-pdk.readthedocs.io/en/latest/physical_verification/design_manual/drm_09_2.html (9.2 Bond Pad Guidelines, PAD.1)
  - assembly: gf180mcu_fd_io/features.html: bond pad opening 60x60um; IO cell width 75um x height 350um (inclusive of bond pad); design grid 0.005um
  - assembly: wafer.space/chip-on-board-wire-bonded-pcbs (Apache-2.0): 74-pad TT-convention padframe, 14x16mm PCB, 70-pin 0.4mm-pitch mezzanine; wirebond rules: no crossing wires, angle <=45deg, max wire length <3mm, min 1mm or 2x die thickness
  - assembly: wafer.space/gf180mcu-project-template slot_1x1.yaml: DIE_AREA [0,0,3932,5122], CORE_AREA [442,442,3490,4680]; 17/17/20/20 pads on S/N/E/W = 74 total, pinned to fixed coordinates for COB
- **PAD_PITCH**: No assembly-house / packaging data (bond diagram, package pad pitch). Public sources give pad COUNTS and die size but no center-to-center pitch.
  - source: https://gf180mcu-pdk.readthedocs.io/en/latest/physical_verification/design_manual/drm_09.html (9.0 Bond Pad)
  - assembly: wafer.space slot specs / slots.json: 1x1 die 3932x5122um, seal ring ~26um per side, 56 IO + 18 power = 74 pads; quarter slot 1936x2531um with 48 IO
  - assembly: gf180mcu_fd_io/features.html: IO cell width 75um (pitch would be >= 75um + spacing), corner cell 355x355um
  - assembly: IEEE SSCS Chipathon 2025: padring 2040x2040um usable, 88 pins (22 per side), QFN-88 reference
  - assembly: DRM 9.2 PAD.2 pad-opening-to-pad-opening = 9um, PAD.20 pad-metal-to-pad-metal = 5um; both are EDGE-TO-EDGE spacings, NOT center-to-center pitch
  - derived (NOT filled): From 1x1 die 3932um minus 2x355um corners, 17 pads -> average 189.5um spacing; from 5122um minus corners, 20 pads -> 220.6um. These are DERIVED averages, NOT a stated pitch, and depend on corner/filler assumptions. Do NOT fill.
- **ESD_AREA_MIN**: ESD target level (HBM kV) is a system requirement, not foundry data; TLP-to-HBM correlation unverified.
  - source: https://gf180mcu-pdk.readthedocs.io/en/latest/physical_verification/design_manual/drm_14_5_2.html (14.5.2 ESD Performance from 3.3V LV N+/PWELL diode; 14.4.2 Design Guidelines)
- **IO_CURRENT**: Design decision.
- **DQ_BIT_SKEW_MAX**: System timing budget.
- **RAIL_WIDTH**: IO_CURRENT (design input).

## Assembly / bonding diagram search (2026-11-16)

**Q: public bonding diagram and pad pitch data?**

- found: GF180MCU DRM 9.0/9.2, gf180mcu_fd_io features, wafer.space slot specs + slots.json, wafer.space/gf180mcu-project-template slot_1x1.yaml, wafer.space/chip-on-board-wire-bonded-pcbs (Apache-2.0), IEEE SSCS Chipathon 2025 padring
- explicit pad pitch value: None
- status: NO explicit center-to-center pitch found in any public source
- reason: DRM 9.0 explicitly says pad size and pitch are limited by the assembly house; only IO cell width (75um), bond pad opening (60x60um and PAD.1=40um), pad counts and die dimensions are published. wafer.space pins 74 pads to fixed coordinates in slot_1x1.yaml but does not state a pitch number.


## Honesty boundaries

- Docs site says work in progress / Experimental Preview.
- DRM 9.2: bond-pad numbers are DRC defaults, VARIABLE, must be confirmed with the assembly house.
- DRM 9.0: pad size and pitch are limited by the assembly house; no center-to-center pitch is given.
- DRM 14.4: TLP-to-HBM miscorrelation is acknowledged; no HBM/MM target level is specified.
- Web sources cannot be re-opened offline, unlike the live-checked local PDK files.
