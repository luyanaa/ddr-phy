# ics55

Device map is not yet bound (status: TBD). No SPICE or xschem
schematic is emitted for this backend, because that would require
inventing device names. Verify the PDK device cards first.

**Blocker:** 3.3 V ESD diode SPICE card missing: LVS has dio_3p3_pp_nw_lp, foundry SPICE has only 1.2 V/2.5 V diodes. The SDR pad cannot be bound without inventing a model; dio_2p5_* must not be relabelled as 3.3 V. A custom GGNMOS/GGPMOS clamp using nmod3p3_lp/pmod3p3_lp is a STUDY_ONLY option (docs/ICS55_ESD_3V3.md), not a characterized ESD cell.
