# GF180 pad core layout: DRC / LVS / PEX

**Status: pad core only. Full DRC 0 violations, LVS match, Magic RC-PEX.
NOT signoff; OE logic, pre-driver, guard ring, pad ring, ESD stress,
latch-up, antenna and SPEF are not done.**

## 1. Artifacts

| file | use |
|---|---|
| `generator/gf180_pad_layout.py` | KLayout `pya` + GF180 API-PCell generator |
| `sch/pads/gf180mcuD/pcell/gf180_pad_core.gds` | layout |
| `sch/pads/gf180mcuD/pcell/gf180_pad_core.spice` | matching schematic for LVS |
| `sch/pads/gf180mcuD/pcell/gf180_pad_core_manifest.json` | layers / status |
| `sim/gf180_pad_layout.sh` | generate + DRC + LVS + Magic PEX |
| `reports/gf180_pad_core_pex.spice` | raw Magic flat RC-PEX |
| `reports/gf180_pad_core_pex_sim.spice` | node-sanitized PEX for ngspice |

Cell: `gf180_pad_core`, bbox `(-62, -65) .. (45, 51.63) µm`
(107 x 116.63 µm). Pad opening 60 x 60 µm, five-metal stack 64 x 64 µm.

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

## 2. Full DRC

KLayout 0.30.7 (LibreLane shell), `variant=gf180mcuD`, `run_mode=flat`:

```text
DRC RESULT: SUCCESS (0 violations)
COMP ratio: 26.20 %
Poly2 ratio: 14.55 %
```

`sh sim/gf180_pad_layout.sh` regenerates and checks it. The system KLayout
0.30.0 deck is not used: it fails the `dnwell` connectivity path. The pad
core has no DNWELL; the `diode_nd2ps` is built as an N+/LVPWELL diode with
manual `diode_mk` (the API cell only draws those layers in its deep-nwell
branch, and DNWELL breaks the 0.30.0 DRC deck).

Dummy COMP / Poly2 fill is required because the density rules are
die-level; the fill is on `22/4` and `30/4` and is excluded from LVS.

## 3. LVS

`gf180mcu.lvs`, `check_ports=false`, `combine=true`, `run_mode=flat`:

```text
INFO : Congratulations! Netlists match.
```

The extracted netlist (`reports/gf180_pad_core_extracted.spice`) contains the
output devices, the series resistor, all three ESD diodes and the receiver.
The 40 output fingers are combined to the schematic W=200/80 µm devices.

## 4. PEX

Magic 8.3 with the GF180 Magic tech, flat extraction, full R-C
(`extract do resistance`, `ext2spice extresist on`):

| item | value |
|---|---|
| metal resistors | **2871** |
| capacitors | **6** |
| MOS/resistor devices | **83** |
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

ngspice `.op` on the PEX with `.options rshunt=1e12` converges:

```text
PAD   = 1.65 V
VDDIO = 3.30 V
VSSIO = 0 V
GP    = 3.30 V
GN    = 0 V
IN    = 0 V
```

`rshunt=1e12` is required: Magic's flat extraction leaves a few internal
networks without a DC path (e.g. `VSSIO.n2`), so the bare netlist produces
a singular matrix. This is a PEX-extractor artifact, not a layout short.

## 5. Not done

- OE logic (`PAD_OE_CTRL`) and pre-driver: GP/GN are external pins in this
  slice. A full pad macro needs OE_N / PU_OK / OUT and the 24 logic devices
  laid out.
- Guard ring / pad ring, sealring, ESD stress (HBM/TLP), latch-up, antenna.
- Distributed capacitance / SPEF, full PVT, EM/IR, package/PCB.
- Signoff. `reports/capability_report.md` stays `NO_GO`.
