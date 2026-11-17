# GF180 pad macro layout: DRC / LVS / PEX

**Status: full pad macro (pad stack + output stage + series R + ESD +
receiver + OE logic + pre-driver). Full DRC 0 violations, LVS match,
Magic RC-PEX, ngspice `.op`. NOT signoff: guard ring, pad ring, ESD
stress, latch-up, antenna, SPEF, full PVT and STA are still open.**

## 1. Artifacts

| file | use |
|---|---|
| `generator/gf180_pad_layout.py` | KLayout `pya` + GF180 API-PCell generator |
| `sch/pads/gf180mcuD/pcell/gf180_pad_core.gds` | layout |
| `sch/pads/gf180mcuD/pcell/gf180_pad_core.spice` | matching schematic for LVS |
| `sch/pads/gf180mcuD/pcell/gf180_pad_core_manifest.json` | layers / status |
| `sim/gf180_pad_layout.sh` | generate + DRC + LVS + Magic PEX + ngspice |
| `reports/gf180_pad_core_pex.spice` | raw Magic flat RC-PEX |
| `reports/gf180_pad_core_pex_sim.spice` | node-sanitized PEX for ngspice |

Cell: `gf180_pad_core`, bbox `(-66.5, -65) .. (45, 73.25) µm`
(111.5 x 138.25 µm). Pad opening 60 x 60 µm, five-metal stack 64 x 64 µm.
Top-level ports: `OUT OE_N PU_OK PAD IN VDDIO VSSIO` (schematic);
`GP GN` are internal pre-driver outputs.

Devices:

| block | device | size |
|---|---|---|
| output PMOS | `pfet_03v3` | W=200 µm (40 x 5 µm fingers), L=0.28 µm |
| output NMOS | `nfet_03v3` | W=80 µm (40 x 2 µm fingers), L=0.28 µm |
| series R | `ppolyf_u` | 22 µm wide / 1.4 µm long, extracted **22.27 ohm** |
| ESD up | `diode_pd2nw_03v3` | 20 µm², 18 µm perimeter |
| ESD down | `diode_nd2ps_03v3` | 20 µm², 18 µm perimeter |
| ESD clamp | `diode_pd2nw_03v3` | 100 µm², 40 µm perimeter |
| receiver NMOS | `nfet_03v3` | W=2 µm, L=0.28 µm |
| receiver PMOS | `pfet_03v3` | W=4 µm, L=0.28 µm |
| OE logic | 1 nand2 + 2 nor2 + 2 inv | W_N=1 µm, W_P=2 µm, L=0.28 µm |
| pre-driver | 5 inv | W_N=1 µm, W_P=2 µm, L=0.28 µm |

Logic chain: `OUTB_I = !OUT`, `OENB = !OE_N`,
`EN_N = !(PU_OK & OENB)`, `NGPB = !(EN_N | OUTB_I)`,
`N_GN = !(EN_N | OUT)`, then the GP/GN pre-driver inverters. 26 logic
MOSFETs in total; 30 MOSFETs, 3 diodes and 1 resistor in the schematic,
34 extracted devices.

## 2. Full DRC

KLayout 0.30.7 (LibreLane shell), `variant=gf180mcuD`, `run_mode=flat`:

```text
DRC RESULT: SUCCESS (0 violations)
COMP ratio: 25.59 %
Poly2 ratio: 16.70 %
Metal1 ratio: 30.60 %
Metal2 ratio: 30.63 %
Metal3 ratio: 30.63 %
Metal4 ratio: 30.61 %
Metal5 ratio: 30.53 %
MetalTop ratio: 30.53 %
```

`sh sim/gf180_pad_layout.sh` regenerates and checks it. The system KLayout
0.30.0 deck is not used: it fails the `dnwell` connectivity path. The pad
core has no DNWELL; the `diode_nd2ps` is built as an N+/LVPWELL diode with
manual `diode_mk` (the API cell only draws those layers in its deep-nwell
branch, and DNWELL breaks the 0.30.0 DRC deck).

The OE-logic row makes the cell taller, which dilutes the pad stack's metal
plates below the die-level density rules. `dummy_density_fill()` therefore
adds COMP/Poly2/M3/M4/M5 dummy tiles on the dedicated dummy layers
(`22/4`, `30/4`, `42/4`, `46/4`, `81/4`) with the PDK dummy clearances
(DCF.2b 1.9 µm, DCF.4 3.5 µm, DM.2b 0.98 µm, DM.3 2 µm). Those layers are
excluded from LVS.

## 3. LVS

`gf180mcu.lvs`, `check_ports=false`, `combine=true`, `run_mode=flat`:

```text
INFO : Congratulations! Netlists match.
```

The extracted netlist (`reports/gf180_pad_core_extracted.spice`) contains
34 devices: the output devices, the series resistor, all three ESD diodes,
the receiver and the 26 OE-logic/pre-driver MOSFETs. The 40 output fingers
are combined to the schematic W=200/80 µm devices.

Internal logic nets are deliberately not labelled: a `Metal2_label` on an
internal net promotes it to a top-level port in the PEX netlist, which
breaks the PEX testbench interface.

## 4. PEX

Magic 8.3 with the GF180 Magic tech, flat extraction, full R-C
(`extract do resistance`, `ext2spice extresist on`):

| item | value |
|---|---|
| metal resistors | **3096** |
| capacitors | **11** |
| MOS/resistor devices | **109** |
| ESD diodes | **3** |
| PAD capacitance | **0.173 pF** |
| series R | **22.27 ohm** |

The raw netlist is `reports/gf180_pad_core_pex.spice`. The simulation-ready
copy `reports/gf180_pad_core_pex_sim.spice` replaces `.`/`/`/`#` in node
names and replaces the single `ppolyf_u` instance with the extracted
22.272727 ohm resistor. The replacement is explicit because the PDK
`ppolyf_u` subcircuit is not usable stand-alone (it needs global resistor
parameters; the same limitation is already recorded in
`docs/PAD_GENERATOR.md`).

ngspice `.op` on the PEX with `.options rshunt=1e12` converges
(`OE_N=3.3 V`, `PU_OK=0`, `OUT=0`, `PAD=1.65 V`):

```text
PAD   = 1.650 V
VDDIO = 3.300 V
VSSIO = 0 V
OUT   = 0.000 V
OE_N  = 3.300 V
PU_OK = 0.000 V
GP    = 3.299991 V     (output PMOS off)
GN    = 0.005306 V     (output NMOS off)
IN    = 0.4585 V       (receiver output)
```

`GP`/`GN` are driven by the on-cell pre-driver, so the testbench leaves
them on 1G loads instead of ideal sources; `IN` is the receiver output and
gets the same treatment. `rshunt=1e12` is required: Magic's flat extraction
leaves a few internal networks without a DC path, so the bare netlist
produces a singular matrix. This is a PEX-extractor artifact, not a layout
short.

## 5. Not done

- Guard ring / pad ring, sealring, ESD stress (HBM/TLP), latch-up, antenna.
- Distributed capacitance / SPEF, full PVT, EM/IR, package/PCB.
- STA of the OE path (P1-3) and the package/PCB channel (P1-4).
- Signoff. `reports/capability_report.md` stays `NO_GO`.
