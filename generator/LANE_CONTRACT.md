# Cross-process DDR1 SSTL-2 lane contract (v1)

Every process lane produces EXACTLY these four artifacts under /grid/ddr-phy:

1. `sch/pads/<pdk>/sstl2_dq.spice` — the cell netlist. Subckt `<pdk>_sstl2_dq` with
   EXACT port order `OUT OE IN PAD VREF PU_OK VDD VSS VDDIO VSSIO` (10 pins).
   Topology mirrors the proven IHP reference `sch/pads/ihp130/sstl2_dq.spice`:
   - RX: resistor-fed NMOS diff pair (PAD vs VREF), PMOS current-mirror load,
     XRBIAS bias resistor + tail, NAND-qualified by PU_OK, resistive pull-down
     level translation to core domain, two core inverters to IN.
   - TX: data + OE independently level-shifted core->IO (unless core_v==io_v),
     PU_OK-qualified NAND gating, multi-stage inverter predriver, large IO output
     devices, series termination resistor, ESD diodes to VDDIO/VSSIO.
   The internal node `xrx.rx_level` MUST exist (the core-facing RX level node) —
   the bench measures `v(xrx.rx_level)`.
   The XRDRIVER series-resistor line and XRBIAS bias-resistor line MUST be single
   physical lines matching the adapter's exact-match prefix/suffix (the search
   rewrites geometry by exact one-line replacement).

2. `generator/char_ddr1_<pdk>.py` — thin profile. Copy `generator/char_ddr1_ihp130.py`
   shape: a PROFILE dict passed to `char_ddr1_sstl2.characterize(PROFILE)`. Set
   name/subckt/default_cell/device_yaml/cases/res_model_line/spiceinit/license/
   required_root_files/dc_solver. CASES map case_name -> (mos_corner_key,
   res_corner_key, temp_C, core_v, io_v). The mos/res corner keys must match the
   device yaml `char.corners` mapping used by emit_char_pad.model_lines.
   signoff stays False; evidence is witness-point only.

3. `generator/ddr1_<pdk>_backend.py` — adapter implementing contract v1
   (CONTRACT_VERSION=1; validate_config, source_path, characterizer_path,
   render_netlist, characterization_command). Copy `generator/ddr1_ihp130_backend.py`
   EXACTLY except: adapter path string, DEVICE_MAPPINGS prefixes/suffixes matching
   YOUR netlist's XRDRIVER/XRBIAS lines. The render uses exact one-line replacement:
   prefix + default_token + suffix must match exactly ONE line in the source netlist.

4. `specs/ddr1/<pdk>-sstl2.yaml` — backend YAML. Copy `specs/ddr1/ihp130-sstl2.yaml`
   shape: schema_version 1, name, adapter path, characterization.script=
   generator/char_ddr1_<pdk>.py, characterization.source_netlist=
   sch/pads/<pdk>/sstl2_dq.spice, search{sampler grid,max_trials,knobs,development,
   holdout}. Knobs xrdriver_w_um + xrbias_l_um; defaults MUST equal the netlist's
   baseline geometry; values a small discrete set. development=2 cases; holdout=1
   case whose vtt_offset_mv is NOT in development.

VERIFY before finishing (run each):
  python3 generator/tune_ddr1.py --backend specs/ddr1/<pdk>-sstl2.yaml \
      --output /tmp/<pdk>-baseline.json --max-trials 1
  Exit 0 (or electrical result) = baseline netlist compiles, the selected simulator runs, all
  measurements present. Report the exact PASS/FAIL line and any hard-limit failures.
  It is acceptable for a baseline to be electrically INFEASIBLE (that is what the
  grid search is for) but it must NOT be a simulator_error (missing model, bad
  subckt, missing measurement). Iterate device names/sizes until it simulates.

Keep bench stimulus and hard limits in the shared engine. Select the simulator in the device YAML; do not fork the benches or change an existing lane’s simulator implicitly.
NEVER claim signoff. If a measurement is unattainable, report it, do not fudge.

## BSIM4 大 finger 数的 ngspice 陷阱（跨 PDK,2026-11-26 实测）

sky130 与 gf180mcu 的 IO MOS 都是 BSIM4 binned 模型。ngspice 44.2 的 strict
paramchk 在实例使用**大 nf** 时拒绝 foundry bin:报
`Fatal: u0 at current temperature = -0.005 is not positive`。已在两 PDK 上隔离:
同一 w/l,nf 小则正常,nf 大则 fatal,与几何 binning 无关——nf 数值本身触发。

**规则:BSIM4-binned PDK 的大器件一律用平行 multiplier 而非大 nf。**
- gf180mcu:实例参数 `m`(如 `nf=1 m=40`)。
- sky130:实例参数 `mult`(如 `nf=1 mult=40`)。
 multiplier 不参与 bin/u0 提取,绕开该 fatal。已实测 nf=1 + 大 multiplier 在两
 PDK 均正常解析。

IHP SG13G2 不受影响:它用 PSP103(osdi 紧凑模型),无 BSIM4 binning,这正是
ihp130 从未遇到此问题的原因。

## YAML bundle generation and simulator selection

`python3 generator/emit_ddr1_pad.py --backend specs/ddr1/<pdk>-sstl2.yaml --out-dir <new-dir>` materializes the default-sized `sstl2_dq.spice`, `parameters.json`, and case-specific `corners/*.inc`. Optional `characterization.profile` selects the model `PROFILE` if the lane's existing characterization script does not export one (IHP). The existing tune script is unchanged.

`ddr1.simulator` in the device YAML defaults to `ngspice`. With `xyce`, `ddr1.xyce.pm3` takes `{device}` and `{corner}` and passive constants describe the witness approximations. The input pad has the same pins and uses subckt/device instances, numeric micrometre geometries or `{formal}` references. The compiler preserves the pad boundary, prefixes nested internal nodes, preserves `BINUNIT` and all BSIM4 geometry terms, and selects bins on `W/NF`. Xyce ambient temperature is set with `.options device temp=…`; unrecognized directives are not accepted. Existing ngspice lanes still use `.temp` and native model includes. Sky130 0.5 µm lengths are verified in the Xyce witness, not the old ngspice path. `signoff=false`.

## 高阻 vs salicided poly 电阻选型（ics55 实测，2026-11-26）

偏置/上拉/下拉到核心轨的"大电阻"必须用**高阻 poly**，不能图省事用 salicided
低阻。ics55 实测：salicided `re_ppo_3t` 方块电阻 ~10 Ω/sq，w1.2 × l10 µm 实测
仅 85.7 Ω；用它做 RX_LEVEL 上拉时 MDOWN 拉不动，接收器输出恒高卡在逻辑阈值
之上，症状是 `.meas ... when v(rx)=vdd/2` out-of-interval 且**中间节点全部正常**
（差分对/NAND 都对）——极易误判为增益问题。换高阻 `re_hrpo_3t`（~962 Ω/sq，同
尺寸 8.2 kΩ）后接收器立即正常。

**规则：核对电阻方块电阻数量级，而非只看 w/l 几何。** salicided 低阻适合源端接
（XRDRIVER 宽短几何），高阻 poly 适合偏置/上拉/下拉。ics55 的 `re_hrpo` mismatch
表达式引用 `sigma_mis_r`，须在 cornerparams.inc 补 `sigma_mis_r=0` 才能解析。
判据：实测一次电阻值（`.op` 加 1 V 测电流），与 IHP `rhigh` 同几何的阻值对照，
差两个数量级即选型错误。

## 二极管实例必须显式给 area/pj（ics55 实测，2026-11-26）

ngspice 的 `.model d` 二极管若实例省略 `area`/`pj`，回退到模型卡占位默认值——
ics55 `dio_2p5` 的占位 `pj=240 µm`（配 area 3.6 µm²，周长/面积比物理失真）。这个
过大的 `cjsw` 结电容在上电 ramp 期间耦合进 pad、之后放电，造成 hiz 测量的
transient 馈通（ics55 实测 8 ns 处 −18 µA，限 ±5 µA）并抬高 ramp 电流。

**症状极隐蔽**：稳态（22 ns）馈通消失、`.op` 静态 pad 电流仅 pA 级、driver 栅压
探针显示正确关断——一切"看起来正常"，只有 transient 窗口有大电流。三证锁定：
稳态干净 + 静态干净 + 删二极管后馈通降数百倍。

**规则：每个二极管实例显式写 `area`/`pj`，且周长/面积比物理自洽**（正方形
pj≈4√area）。pre-layout witness 用名义最小面积并在注释标注非 HBM/CDM 签核；
面积是真实 tradeoff——越小钳位越弱但馈通越低。修复后 ics55 hiz 从 −18 µA 降至
−0.167 µA、ramp 从 ±1.6 mA 降至 ±0.26 mA，hiz/ramp 两类失败同解（共享同一
容性根源）。
