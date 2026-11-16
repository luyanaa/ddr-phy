# GF180 pad PCell first pass

**Status: pad-only test structure. metal/via/geom DRC subsets pass; full DRC/LVS/PEX not done.**

- GDS: `sch/pads/gf180mcuD/pcell/gf180_pad_pcell.gds`
- manifest: `sch/pads/gf180mcuD/pcell/gf180_pad_pcell_manifest.json`
- generator: `generator/gf180_pad_pcell.py`
- rerun: `sh sim/gf180_pad_pcell.sh` -> `GF180_PAD_PCELL_DONE`

| deck | result |
|---|---|
| metal | SUCCESS (0 violations) |
| via | SUCCESS (0 violations) |
| geom | SUCCESS (0 violations) |

Full DRC was not obtained: the pad-only cell lacks device/connectivity decks; `dnwell`/`ldnmos`/`antenna` paths fail in the KLayout 0.30 deck. LVS/PEX/ESD/latch-up not run. This is not a signoff layout.
