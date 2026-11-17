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

## 4. Limitation found in the P1-2 PEX netlist

The Magic flat PEX writes device geometry in layout units (`w=1000 l=56
ad=52n`) while the PDK ngspice models are subcircuits expecting SI units.
The extracted output stage therefore does not drive in transient: with the
gates forced low the pad stays at the rail it is leaking to, and only the
receiver (a comparator) behaves. The PEX remains valid for DRC/LVS and the
`.op` check (which drives PAD externally), but it is not used for the
channel transient. Fixing the PEX units is an open item.

## 5. Not done

- Vendor IBIS (`[Package]` RLC, V/I, V/T) and DRAM input models.
- PCB geometry -> openEMS/gerber2ems -> Touchstone S-parameters.
- IBIS-to-SPICE driver representation; ngspice cannot consume arbitrary
  Touchstone data directly (see `docs/SI_PI_PACKAGE_PCB.md` section 4).
- Eye diagram / mask, crosstalk, SSN, PDN.
- Multi-corner: the channel is passive; only the driver's edge varies, and
  that is covered by the pad PVT numbers.

`reports/capability_report.md` stays `NO_GO`.
