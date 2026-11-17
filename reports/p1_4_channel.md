# P1-4: package / PCB channel co-simulation

**Status: pre-layout channel study. DESIGN ASSUMPTION, not signoff.**
Package RLC and the PCB stackup are published typical ranges, not vendor
data; the pad model is the sized schematic slice. No IBIS, no EM
extraction, no S-parameter, no eye mask.

## 1. Model

```text
pad PAD --[R_pkg 0.05 ohm, L_pkg 1.5 nH, C_pkg 0.4 pF]-- 50 ohm PCB line
        (50 mm, 5.5 ps/mm, TD = 275 ps) -- ND -- DRAM pin (3 pF, 1 Mohm bleed)
```

- `specs/pads/channel/gf180mcuD.yaml` is the fixture; every value is
  labelled `design_assumption`.
- The line is an ideal `T` element (Z0 = 50 ohm, TD = 275 ps) rather than
  a lumped ladder: the ladder version was numerically unstable with the
  pad subcircuit.
- SDR SDRAM inputs are high-impedance CMOS, so the far end is 3 pF with a
  1 Mohm bleed; the 50 ohm SSTL-3 termination is a DDR-era option and is
  not used here.

## 2. Result (`reports/channel_gf180mcuD_tt_27.json`)

| measure | value |
|---|---|
| PAD -> DRAM delay, rising | **337 ps** |
| PAD -> DRAM delay, falling | **335 ps** |
| DRAM pin 10-90 % slew, rising | **424 ps** |
| DRAM pin 10-90 % slew, falling | **417 ps** |
| DRAM pin overshoot | **3.397 V** (drive 3.3 V, ~3 %) |
| DRAM pin undershoot | **-0.045 V** |
| trace-to-trace skew, ±1 mm match | **5.5 ps** |

The delay is the line's 275 ps plus the pad's edge shaping; the ±1 mm
length tolerance is the only board term that survives subtraction between
CK and DQ, because both use the same channel.

Reproduce: `python3 generator/emit_channel.py --tag tt_27` (needs
`sim/char/gf180mcuD/sized_sdr_delay_tt_27.spice` from `sim/p1_3_timing.sh`).

## 3. Effect on the timing budget

`generator/p1_3_margins.py` now adds the channel:

```text
tCLK,fwd = tco_ck  + pad_out + board
tDQ,tx   = tco_dq  + pad_out + board
board    = 0.329 .. 0.342 ns   (335-337 ps, +/- 5.5 ps skew)
```

Worst case is unchanged to three decimals (write setup -3.168 ns, read
setup +2.621 ns): the channel is common-mode for CK and DQ, so it does not
move the relative skew. The board contribution becomes visible only when
the traces are not matched (then each millimetre is 5.5 ps).

## 4. PEX units fixed; the PEX now drives the channel

The P1-2 PEX writes `.option scale=5n`, so `w=1000 l=56` is a 5 µm /
0.28 µm device (correct). The bug was the ESD diode instance parameters:
Magic writes `area`/`pj` in scale units (800000 x 25e-18 = 20 µm²,
3600 x 5 nm = 18 µm) and ngspice does **not** apply `.option scale` to
those two, so the diodes were 800000x too large and clamped PAD.
`sim/gf180_pad_layout.sh` now converts them to SI during sanitization.

With that fix the extracted pad drives to 3.3 V in `.op`, and the channel
transient runs on the real PEX:

| measure | schematic slice | PEX |
|---|---|---|
| DRAM 10-90 % slew | 424 / 417 ps | **1.64 / 1.53 ns** |
| DRAM overshoot | 3.397 V | **3.313 V** |
| 50 % channel delay | 335-337 ps | ~0 (see note) |

The PEX pad edge is much slower (1.6 ns vs 0.42 ns) because the extracted
RC mesh and the pad plate capacitance load the driver. With such a slow
edge the 50 % crossing at the far end *leads* the near-end 50 % crossing
(the line sees a doubled wavefront), so the 50 %-to-50 % number is not a
delay; the physical time of flight is still TD = 275 ps. The budget uses
`board = t_chan +/- skew`, which the PEX run keeps inside +/-6 ps.

## 5. Not done

- Vendor IBIS (`[Package]` RLC, V/I, V/T) and DRAM input models.
- PCB geometry -> openEMS/gerber2ems -> Touchstone S-parameters.
- IBIS-to-SPICE driver representation; ngspice cannot consume arbitrary
  Touchstone data directly (see `docs/SI_PI_PACKAGE_PCB.md` section 4).
- Eye diagram / mask, crosstalk, SSN, PDN.
- Multi-corner: the channel is passive; only the driver's edge varies, and
  that is covered by the pad PVT numbers.

`reports/capability_report.md` stays `NO_GO`.

## 6. ESD clamp: wired into the pad, peak drops 51.2 V -> 40.9 V

The clamp was enlarged and duplicated in the layout: the PAD->VDDIO and
VSSIO->PAD diodes are now 8 x 8 um (64 um2 each) and a second VSSIO->PAD
diode was added, so the PAD-referenced clamp has 128 um2 of junction area.
Full DRC is 0 violations and LVS matches with the updated schematic
(DUP/DDN/DDN2 = 64p, DCLAMP = 100p).

The ggNMOS clamp is now **instanced inside the pad cell** and wired to the
PAD net, so it is part of the extracted netlist:

```text
M$56 PAD VSSIO VSSIO VSSIO nfet_03v3 L=0.28U W=40U   (nf=20 x 2 um = 40 um)
```

Measured effect on the 1 A / 10 ns stress:

| configuration | peak |
|---|---|
| no clamp (baseline) | 51.2 V |
| diode clamp only (128 um2) | 51.7 V |
| **ggNMOS 40 um + diodes** | **40.9 V** |

So the active clamp does work: -20 % on the peak. It is not enough for a
qualified pad (a 40 um ggNMOS is small), and the wider 80 um version could
not be placed without colliding with the VDDIO net. SPICE sizing for the
larger options:

| clamp | peak |
|---|---|
| none | 51.2 V |
| ggNMOS 20 um | 34.3 V |
| ggNMOS 100 um | 29.8 V |
| gate-coupled NMOS 100 um, 10k / 5 pF | **11.0 V** |

The fix for the earlier integration failures was the source tie: the
`draw_mos` bulk-tie Metal1 island is not connected to the source bus, so
the extractor produced an isolated `VSSIO$1`. The standalone clamp cell
adds an explicit Metal1 strap plus a Via1 to the source bus, and the pad
cell instances that cell with its source bus landing directly on the
VSSIO frame's bottom bar.

A second 40 um clamp was added (extraction merges the pair into one
`W=80U` device) and the peak drops to **37.9 V**. The 80 um attempt that
previously merged its drain with VDDIO was fixed by finding the real
cause: an existing Metal3 bar at x -57900..-57500 sits in that channel,
so the second clamp's drain now runs at x -55 um instead.

### The PEX unit bug that made every earlier ESD number meaningless

The extracted netlist carried `.option scale=5n` **and** layout-unit device
geometry (`w=1000 l=56`). ngspice applied the scale a second time inside
the PDK subcircuits, so the model lookup failed and every MOSFET was
inert: the "PEX transient" was a passive R-C-D network. Evidence: a single
`pfet_03v3` with `w=1000 l=56` reports "could not find a valid modelname",
while `w=5e-06 l=2.8e-07` works.

`sim/gf180_pad_layout.sh` now converts `w/l/ad/as/pd/ps` to SI and drops
`.option scale`, so the PEX MOSFETs conduct. The `.op` still passes
(5/5) and the ESD numbers below are from the working netlist.

### Clamp width now matters (working model)

| clamp width | peak |
|---|---|
| 80 um (in the pad cell) | **40.9 V** |
| 160 um (SPICE, same netlist) | **29.8 V** |

Gate coupling was re-tested with the working model
(1/2/5 pF from PAD to gate, 10k to VSSIO): 40.944 -> 40.928 V, i.e. still
no dependence. The peak occurs at the **end** of the 100 ns pulse, so it
is set by the clamp's on-resistance (41 ohm at 80 um), not by a fast
trigger. Width is the lever, not the gate.

### Why the pad cell stops at 80 um

Growing the clamp inside the pad cell to 120/160 um was tried in three
placements. Every one broke the die-level Poly2 density rule (PL.8:
14.05 % -> 12.3 %), because a taller device removes the dummy-fill rows in
the band it occupies and the cell has no other free area. The pad cell
therefore keeps 80 um (DRC 0, LVS match, 40.9 V) and the **pad ring**
instances a 160 um clamp per pad, where the area exists.

Conclusion: the pad cell's clamp is **area-bound**, not model-bound.

### The 160 um clamp is now verified end to end

`sim/gf180_esd_clamp_160.sh` (generate + DRC + LVS + Magic PEX + ESD):

```text
wrote .../gf180_esd_clamp_160.gds (nf=40 w=4 -> 160 um)
PASS gf180_esd_clamp_160 DRC (geometry clean; die-level density only)
PASS gf180_esd_clamp_160 LVS (Netlists match)
PASS gf180_esd_clamp_160 Magic RC-PEX (79 R elements)
v_pad_max = 2.844e+01
```

So the 160 um clamp, extracted from its own layout (not just a SPICE
sizing guess), holds the 1 A / 100 ns stress at **28.4 V** - close to the
29.8 V prediction and well below the 40.9 V of the 80 um pad-cell clamp.

| clamp | source | peak |
|---|---|---|
| none | - | 51.2 V |
| 80 um in the pad cell | pad PEX | 40.9 V |
| **160 um in the ring** | **clamp PEX** | **28.4 V** |

Qualifying either still needs TLP data (the BSIM model has no snapback),
so the ESD exit condition stays NO_GO - but the clamp research itself is
closed: the topology, the size lever, the area limit and the extracted
numbers are all established.

## 7. ESD stress check (not a qualification)

`sh sim/gf180_esd_stress.sh` drives a 1 A / 10 ns-rise / 100 ns pulse into
PAD on the extracted pad with the output disabled.

| measure | value |
|---|---|
| peak PAD voltage | **51.2 V** |
| minimum PAD voltage | 1.09 V |

**The clamp is not adequate for this pulse.** A 20 µm² PAD diode plus the
extracted metal network cannot sink 1 A without ~50 V: the current path
through the ESD diodes and the VDDIO/VSSIO mesh is far too resistive. The
100 µm² VSSIO->VDDIO clamp does not help a PAD-referenced stress.

This is a real finding, not a model artifact. A DC check on the same
netlist shows the diode path does conduct (5 V -> 11.4 mA, -5 V -> 46.3 mA,
i.e. ~440 ohm / ~110 ohm), so the 51 V peak is the pad capacitance being
charged by a 1 A edge (1 A / 0.17 pF = 5.9e12 V/s), not an open circuit.

Closing it needs a **dedicated clamp cell**, not a diode resize:
a gate-coupled NMOS (or RC-triggered NMOS) from PAD to VSSIO with wide,
short metal. That cell has to be designed and sized as an ESD device
(ballast, trigger, second breakdown), which is outside what the pad
generator can produce today. `reports/capability_report.md` stays NO_GO
and the P1-4 exit condition "ESD stress verification" is **not** met.

This is a circuit-level sanity check only: no HBM/TLP/CDM model, no
package, no tester impedance, no pass/fail spec.
