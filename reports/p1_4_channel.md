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

## 6. ESD clamp: implemented, but the peak is capacitive

The clamp was enlarged and duplicated in the layout: the PAD->VDDIO and
VSSIO->PAD diodes are now 8 x 8 um (64 um2 each) and a second VSSIO->PAD
diode was added, so the PAD-referenced clamp has 128 um2 of junction area.
Full DRC is 0 violations and LVS matches with the updated schematic
(DUP/DDN/DDN2 = 64p, DCLAMP = 100p).

Measured effect on the 1 A / 10 ns stress: **51.2 V -> 51.7 V, i.e. none.**
That confirms the earlier diagnosis: the peak is the pad capacitance being
charged (1 A / 0.17 pF = 5.9e12 V/s), and junction area does not change a
capacitive peak. Only an active clamp that turns on inside the 10 ns edge
helps. SPICE sizing for that path:

| clamp | peak |
|---|---|
| none | 51.2 V |
| ggNMOS 20 um | 34.3 V |
| ggNMOS 100 um | 29.8 V |
| gate-coupled NMOS 100 um, 10k / 5 pF | **11.0 V** |

The ggNMOS layout integration was attempted four times (Metal2 straight
run, Metal3 drain route, source re-routed left and below) and each time
either shorted PAD to VSSIO or left the clamp source as an isolated
`VSSIO$1` net; those attempts were reverted rather than committed broken.
A 5 pF MOM coupling capacitor does not fit the pad cell.

So: **the clamp cell exists and is DRC/LVS clean, but it does not reduce
the ESD peak.** The exit condition stays NO_GO.

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
