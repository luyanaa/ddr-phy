# GF180MCU pad PCell / layout 第一版

状态：**PAD-ONLY TEST STRUCTURE；metal/via/geom DRC 子集 0 violations；LVS/PEX 未做；不是完整双向 pad macro，也不是签核。**

## 1. 产物

- `generator/gf180_pad_pcell.py`：KLayout `pya` 参数化脚本，dbu=0.001。
- `sch/pads/gf180mcuD/pcell/gf180_pad_pcell.gds`：60×60µm pad opening、64×64µm 五层金属、Via1–Via5、`GUARD_RING_MK` 80×80µm 占位、`PR_bndry`。
- `sch/pads/gf180mcuD/pcell/gf180_pad_pcell_manifest.json`：参数、层号、明确 `signoff:false`。
- `sim/gf180_pad_pcell.sh`：生成 + 跑 metal/via/geom 三个 DRC deck。
- `reports/gf180_pad_pcell_drc_{metal,via,geom}.{log,lyrdb}`：DRC 证据。

## 2. DRC 结果

`klayout -b -r gf180mcu.drc ... -rd decks=<deck> -rd run_mode=flat -rd threads=1`：

| deck | 结果 |
|---|---|
| metal | **SUCCESS (0 violations)** |
| via | **SUCCESS (0 violations)** |
| geom | **SUCCESS (0 violations)** |

复现：`sh sim/gf180_pad_pcell.sh` → `GF180_PAD_PCELL_DONE`。

**full DRC**：用 LibreLane 的 KLayout 0.30.7 可以跑完整 deck；pad-only cell 报 `DCF.1b`（COMP 密度）、`PL.8`（Poly2 密度）、`GR.1`（GUARD_RING_MK 没有 guard ring comp）3 项，都是密度/guard-ring 缺口，不是 0。系统 KLayout 0.30.0 的 deck 在 `dnwell` connectivity 路径报错，旧日志 `reports/gf180_pad_pcell_drc_full.log` 保留了这个失败。

## 3. 还没有

- ESD 二极管、驱动/接收 MOS、三端电阻、Guard ring 的 Comp/Nwell/Pplus/Nplus 环、完整 pad ring。
- 原理图/网表与 layout 的 LVS；PEX/SPEF；天线/Latch-up/ESD 资格。
- 最终尺寸/PCell 参数化到 `specs/pads/topology.yaml` 的 31 个参数；当前 pad-only 尺寸是固定的 60/64/80µm。

## 4. 下一步

1. 把 `sch/pads/gf180mcuD/sdr_bidir_pad.spice` 的器件槽映射到 Comp/Poly2/Nwell/Pplus/Nplus/Contact 层，先做 ESD 二极管 + 输出 MOS 的 layout。
2. 用 `gf180mcu.drc` 的完整 deck（需要先补 connectivity/device decks）跑 full DRC。
3. 从 layout 提取 netlist，和 `sdr_bidir_pad.spice` 做 LVS；再跑 PEX/SPEF。
4. 过 full DRC/LVS/PEX 后才谈 pad ring 和 x8 I/O ring。

## 5. 不这样做

- 不把 metal/via/geom 子集 DRC 说成 full DRC clean。
- 不把这个 pad-only GDS 说成完整 pad macro 或可流片版图。
- 不因为 metal/via/geom 通过就改 `reports/capability_report.md` 的 `NO_GO`。

## 6. Pad macro 第一版（P1-2 布局/LVS/PEX）

在 pad-only cell 之上加了真实器件和 OE 控制逻辑：

- 输出级：PMOS W=200 µm（40×5 µm fingers）、NMOS W=80 µm（40×2 µm fingers），`nfet_03v3`/`pfet_03v3`，L=0.28 µm。
- 串联电阻：`ppolyf_u`，22 µm 宽 / 1.4 µm 长，布局提取 **22.27 ohm**。
- ESD：PAD→VDDIO `diode_pd2nw_03v3` 20 µm²；VSSIO→PAD `diode_nd2ps_03v3` 20 µm²；VSSIO→VDDIO `diode_pd2nw_03v3` 100 µm²。
- 接收器：`nfet_03v3` W=2 µm + `pfet_03v3` W=4 µm，输入 PAD、输出 IN。
- OE 逻辑与预驱动：1 个 nand2、2 个 nor2、7 个 inv，共 26 个 MOSFET，W_N=1 µm / W_P=2 µm / L=0.28 µm，IO 域 3.3 V，手工摆放的 `draw_nfet`/`draw_pfet` 实例（不是 OSU 标准单元）。
  - `OUTB_I = !OUT`、`OENB = !OE_N`、`EN_N = !(PU_OK & OENB)`、`NGPB = !(EN_N | OUTB_I)`、`N_GN = !(EN_N | OUT)`，再经 5 级反相器产生 GP/GN。
  - 逻辑行在输出级上方；内部网走 Metal3 专用轨道（0.8 µm 间距），GP/GN 经 Metal4 下引到输出级栅极。
- 器件周围的 dummy COMP/Poly2/M3/M4/M5 fill，用于过 die-level 密度规则（DCF.2b 1.9 µm、DCF.4 3.5 µm、DM.2b 0.98 µm、DM.3 2 µm 间隙）。

产物：

- `generator/gf180_pad_layout.py`、`sch/pads/gf180mcuD/pcell/gf180_pad_core.gds`
- `sch/pads/gf180mcuD/pcell/gf180_pad_core.spice`
- `sim/gf180_pad_layout.sh`
- `reports/gf180_pad_core.md`、`reports/gf180_pad_core_pex.spice`、`reports/gf180_pad_core_pex_sim.spice`

结果（cell `gf180_pad_core`，bbox 111.5 × 138.25 µm）：

| gate | 结果 |
|---|---|
| full DRC（KLayout 0.30.7，flat） | **SUCCESS (0 violations)**；COMP 25.59%，Poly2 16.70%，M1 30.60%，M2 30.63%，M3 30.63%，M4 30.61%，M5 30.53% |
| LVS（`gf180mcu.lvs`，`combine=true`） | **Netlists match**（34 个抽取器件：30 MOS + 3 diode + 1 R） |
| Magic RC-PEX（flat，`extract do resistance`） | **3096 R、11 C、109 X、3 D**；PAD cap **0.173 pF**；series R **22.27 ohm** |
| ngspice `.op` on PEX | **通过**（需 `.options rshunt=1e12`；PAD 1.65 V、VDDIO 3.3 V、VSSIO 0 V、GP 3.30 V、GN 5.3 mV、IN 0.4585 V） |

复现：`DISPLAY=:0 sh sim/gf180_pad_layout.sh` → `GF180_PAD_LAYOUT_DONE`。

**仍然不是签核版**：guard ring、pad ring、ESD 应力/latch-up/天线、SPEF/分布式电容、完整 PVT、OE 路径 STA（P1-3）、封装/PCB（P1-4）都还没有。PEX 的 `ppolyf_u` 实例在仿真文件里换成提取出的 22.2727 ohm 理想电阻（PDK 的 `ppolyf_u` 单独使用缺全局电阻参数，和 `docs/PAD_GENERATOR.md` §4.1 的限制相同）。内部逻辑网刻意不打 label：`Metal2_label` 会把内部网提升为顶层端口，破坏 PEX testbench 的接口。`reports/capability_report.md` 仍是 `NO_GO`。

## 7. 下一步

1. P1-3：CK 输出与端到端 SDC（min/max setup/hold、OE 使能/关断裕量）。
2. P1-4：封装/PCB 通道（IBIS/RLC 或 S-parameter 联合仿真）。
3. guard ring / pad ring、ESD 应力与 latch-up、SPEF、完整 PVT。
