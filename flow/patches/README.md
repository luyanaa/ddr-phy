# LibreLane CTS patch

`librelane-3.0.17-cts.patch` is against
`librelane/scripts/openroad/cts.tcl` from LibreLane 3.0.17
(`python3.13-librelane-3.0.17`).  It does two things:

1. adds `-no_insertion_delay` to `clock_tree_synthesis`, removing the
   64-level latency-balance chain on `ck90`;
2. splits the two 16-load `sg13g2_buf_16` CTS roots (`clkbuf_0_dqs_capture`,
   `clkbuf_0_sys_clk`) into 2 x `sg13g2_buf_8`, because the SG13G2 liberty
   declares `default_max_fanout : 8` and SDC `set_max_fanout` cannot relax it.

Apply and run:

```sh
rm -rf /tmp/librelane_patched
cp -a /nix/store/abmh7jj4bkf725p7rrrr98r9ax077v6d-python3.13-librelane-3.0.17/lib/python3.13/site-packages/librelane /tmp/librelane_patched/librelane
chmod -R u+w /tmp/librelane_patched
patch -p1 -d /tmp/librelane_patched < flow/patches/librelane-3.0.17-cts.patch
PATH=/nix/var/nix/profiles/default/bin:$PATH \
  PYTHONPATH=/tmp/librelane_patched TOP=ddr1_top sh flow/run.sh ihp130
```

The Nix store copy is read-only; `PYTHONPATH` shadows the installed package.
