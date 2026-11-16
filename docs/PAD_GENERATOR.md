# Pad 原理图与 VREF 接收器生成器

状态：**拓扑模板 + 三套已绑定 PDK 的第一版可跑表征切片；未表征，NO_GO。** 共享拓扑已扩到 gf180mcuD / sky130 / IHP SG13G2 三套已绑定 device map，并生成 SPICE/xschem 拓扑；ics55 因缺 3.3 V ESD 二极管 SPICE 卡保持未绑定（自绘 GGNMOS 只在 `docs/ICS55_ESD_3V3.md` 做研究）。gf180mcuD / sky130 / ihp130 各有一条明确标注 `design_assumption` 的 sizing fixture 和 ngspice OE+预驱动+输出级/接收器切片（§4.1），外加 ESD 反向泄漏测量，但它们不是签核尺寸。器件尺寸、指条数、驱动电流、串联电阻、ESD 面积、保护环间距在通用拓扑里仍是参数（`null`）。

## 1. 为什么是生成器

一张共享拓扑 + N 份器件映射 -> N 套产物，而不是给四套工艺各画一张图：

```text
specs/pads/topology.yaml          (一张原理图，10 个器件槽 / 31 个参数)
specs/pads/devices/*.yaml        (每 PDK 只换器件名、符号、电源与许可)
specs/pads/templates/*.tpl       (SPICE / xschem / char_tb 模板)
        |
        v  python3 generator/emit_pads.py
sch/pads/<backend>/              (SPICE 网表、xschem 原理图、DOT 图、清单)
        |
        v  python3 generator/check_pads.py
reports/pad_generator_report.md
```

改器件名或拓扑只改 YAML / 模板再重跑，产物带 `GENERATED - DO NOT EDIT` 头。脚本在参数有具体值、残留 `@@` 占位符、或出现签核声明时会拒绝/报错。

## 2. 输入

| 文件 | 内容 |
|---|---|
| `specs/pads/topology.yaml` | 共享信号链、端口、电源轨、10 个器件槽、31 个全为 `null` 的参数、表征清单 |
| `specs/pads/devices/gf180mcuD.yaml` | **本机实测**的器件映射（见 §3） |
| `specs/pads/devices/{sky130,ihp130}.yaml` | 已绑定：器件名、模型 include、许可与实例语法均按本机 PDK 核对（见 §3.1）；整份 map 仍标 `NO_GO`，尺寸未选 |
| `specs/pads/devices/ics55.yaml` | 未绑定：`nmod3p3_lp` / `pmod3p3_lp` / `nm1p2_svt_lp` / `pm1p2_svt_lp` 与 `re_ppo_sab_3t` 已核对，但 3.3 V ESD 二极管 SPICE 卡缺失（LVS 有 `dio_3p3_pp_nw_lp`，foundry SPICE 只有 1.2 V / 2.5 V）→ 不生成 SPICE；自绘 GGNMOS 只做设计研究，见 `docs/ICS55_ESD_3V3.md` |
| `specs/pads/templates/*.tpl` | 4 个模板：SDR 双向 pad SPICE、VREF 接收器 SPICE、xschem `.sch`、表征 TB 骨架 |

拓扑与 `docs/ARCHITECTURE.md` §5 的散文图一致：电平搬移（仅 VDD≠VDDIO）-> 厚氧预驱动 -> 三态输出（PMOS 到 VDDIO / NMOS 到 VSSIO）-> 串联电阻 -> PAD；PAD 上挂主 ESD 二极管与电源钳位；接收侧 SDR 用厚氧 CMOS 反相器/施密特，DDR1 用 PAD 对 VREF 的差分对再变单端；上电 Hi-Z 直到两套电源都在。

## 3. gf180mcuD 的落地依据（本机实测，2026-11-15）

PDK 根：`~/.ciel/ciel/gf180mcu/versions/*/gf180mcuD`

| 事实 | 来源 |
|---|---|
| `.subckt nfet_03v3 / pfet_03v3 d g s b w=.. l=.. nf=.. m=..` | `libs.tech/ngspice/sm141064.ngspice` |
| `.subckt ppolyf_u 1 2 3 r_length=l r_width=w`；`.subckt nplus_u/pplus_u/npolyf_u` 等电阻 | 同上 |
| `.model diode_nd2ps_03v3 d` / `.model diode_pd2nw_03v3 d` | 同上 |
| `nfet_03v3.sym` / `pfet_03v3.sym` / `diode_nd2ps_03v3.sym` / `diode_pd2nw_03v3.sym` / `ppolyf_u.sym` | `libs.tech/xschem/symbols` |
| **Apache-2.0** 许可（GlobalFoundries PDK Authors 头） | `libs.tech/ngspice/design.ngspice` |
| 现成 `gf180mcu_fd_io` / `gf180mcu_ef_io` GPIO 是 4.5–5.5 V 结构参考，不是本设计 pad | `libs.ref/gf180mcu_fd_io/spice`、ARCHITECTURE.md §5 |

因此 gf180mcuD 映射：core 3.3 V = VDDIO 3.3 V -> **不做电平搬移**（§5.1 明确"名义电压相同，不做搬移，预驱动仍要"）；驱动/接收用 `nfet_03v3`/`pfet_03v3`；二极管用两张 3.3 V 卡；串联电阻留 `ppolyf_u` 占位。**禁止**：`nfet_06v0`/`pfet_06v0`（6 V）、5 V GPIO、以及任何核心标准单元当 pad 驱动。

## 3.1 另外两套已绑定 map 与本机证据（2026-11-16）

| backend | 槽位与器件 | 本机来源 |
|---|---|---|
| sky130 | IO `sky130_fd_pr__nfet_g5v0d10v5` / `pfet_g5v0d10v5`；core `nfet_01v8` / `pfet_01v8`；二极管 `diode_pd2nw_11v0` / `diode_pw2nd_11v0`；电阻 `res_high_po` | `libs.ref/sky130_fd_pr/spice/*.pm3.spice`、`*.model.spice`；`libs.tech/ngspice/sky130.lib.spice`；Apache-2.0 |
| ihp130 | IO `sg13_hv_nmos` / `sg13_hv_pmos`；core `sg13_lv_nmos` / `sg13_lv_pmos`；ESD `diodevdd_2kv` / `diodevss_2kv`；电阻 `rppd` | `libs.tech/ngspice/models/sg13g2_moshv_mod.lib`、`sg13g2_moslv_mod.lib`、`sg13g2_esd.lib`、`resistors_mod.lib`；corner libs；Apache-2.0 |
| ics55 | IO `nmod3p3_lp` / `pmod3p3_lp`；core `nm1p2_svt_lp` / `pm1p2_svt_lp`；电阻 `re_ppo_sab_3t`；**3.3 V 二极管缺失** | `libs.tech/spice/foundry/ngspice/model_wrapper1_hsp.lib`、`res/resistor.ckt`、`dio/dio_io25.mdl`；vendor 评估许可 |

跨 PDK 的实例语法不再硬编码在共享模板里，而是放在各 map 的 `spice` 段：`nf`（gf180/sky130/ics55）vs `ng`（IHP）、`m`（gf180/sky130/IHP）vs `mr`（ics55）、`r_length/r_width`（gf180）vs `w/l`（其余）、2 端 `.model` 二极管（gf180/sky130/ics55）vs 3 端 ESD 子电路（IHP）。共享拓扑只保留节点与器件槽。

本轮同时修正了一个真实拓扑缺陷：电源钳位二极管的阳极/阴极原来写成 `D_CLAMP VDDIO VSSIO`，在正常供电下正偏。现在统一为阳极 `VSSIO`、阴极 `VDDIO`；IHP 的 3 端 ESD 单元对应 `X_CLAMP VDDIO VSSIO VSSIO <cell>`。`check_pads.py` 会拒绝 `D_CLAMP VDDIO VSSIO`。

**语法冒烟**（不是表征）：把 31 个参数换成明确标注的临时值后，sky130 与 IHP 的 `sdr_bidir_pad.spice` 和 `vref_receiver.spice` 都能被 ngspice 读入并跑完 `.op`；没有 unknown-subckt / unknown-parameter 错误。模型自身的 `IKR too small`、PSP 噪声参数 `<NAN>` 警告仍会出现，且这些临时值不是设计尺寸，不能用于任何电气结论。ics55 因二极管卡缺失未生成网表。

单位仍需注意：拓扑参数以米为单位；sky130 的子电路在 `.option scale=1u` 下按微米解释，填值时要做 ×1e6；IHP/ics55/gf180 按米解释（可带 `u` 后缀）。模板头部的 `SIZE UNITS` 行记录这一点。

## 4. 产物

| backend | device map | 产物 |
|---|---|---|
| gf180mcuD | 已绑定（实测） | `sdr_bidir_pad.spice/.sch`、`vref_receiver.spice/.sch`、`pad_topology.dot`、`char_tb.spice`、`required_params.json`、`manifest.json`、`README.md` |
| sky130 | 已绑定（实测） | 同上 |
| ihp130 | 已绑定（实测） | 同上；ESD 用固定几何 2 kV 单元，`ESD_AREA_*` 参数不适用 |
| ics55 | 未绑定（3.3 V ESD 二极管卡缺失） | manifest / README / params / DOT / char_tb + `DEVICE_MAP_TBD.md`；**不发 SPICE**，不把 `dio_2p5_*` 改名成 3.3 V |

SPICE 网表用 `@@DEV_*@@` 绑器件、`@@P_*@@` 留参数名（如 `w=W_N_OUT`、`nf=NF_DEVICE`），条件块 `@if LEVEL_SHIFTER@` 由 `core_v != vddio_v` 决定。模板里的实例行由 map 的 `spice` 段生成，生成后不留 `@@` 占位符。

**验证**：`generator/check_pads.py` 通过（31 参数未解、4 backend 中 3 套已绑定、0 签核声明、无 `@@` 残留、无硬编码尺寸、无 `UNBOUND_` 占位、钳位方向正确）；`sh sim/char_pad.sh` 跑出 gf180mcuD / sky130 / ihp130 三份 `reports/pad_char_*.{json,md}`（§4.1，全部 `design_assumption`）；sky130 与 IHP 的生成网表也用临时参数跑过 ngspice `.op` 语法冒烟（见 §3.1）。xschem 自动网表本轮未重跑（本机 `xschem -x -n -s` 在写输出文件时超时），所以不把“xschem 能网表”当作本轮证据；`.sch` 仍只是生成产物。

## 4.1 第一版可跑表征切片（三套 PDK，DESIGN ASSUMPTION）

`sim/char_pad.sh` 默认依次跑 gf180mcuD / sky130 / ihp130；也可以传一个或多个 backend。每条读取 `specs/pads/sizing/<backend>.first_pass.yaml`（`meta.status: design_assumption`），把通用拓扑渲染成带 `.param` 的网表，跑 ngspice 并写 `reports/pad_char_<backend>.{json,md}`。

这一片的边界：

- **只测 OE 逻辑 + 预驱动 + 输出级 + 理想 22Ω 串联电阻 + PAD + 接收器输入门限**。
- OE 控制是真正的晶体管级 IO 门；sky130/IHP 的 OUT 走一个 core→IO 电平搬移。OE_N/PU_OK 仍按 IO 域 3.3V 驱动，全芯片级控制电平搬移/缓冲未做。
- **不包含**封装/PCB RLC、PVT、SDF/PEX、ESD 应力/资格；ESD 只在单独的 DC deck 里做反向泄漏。
- 负载是 1kΩ 到 VDDIO/2 + 1pF，轻载占位；不是板级模型。
- 尺寸来自各 PDK 的实测 Class-I 器件校准；gf180 用全局 `M_DEVICE=40` + 2µm/5µm per-finger，sky130 用 `M_DEVICE=4` + 30µm/82.5µm，IHP 用 `ng=14/42` + 70µm/210µm。这些是 fixture 的写法，不是最优尺寸。

| 测量 | gf180mcuD | sky130 | ihp130 | 条件 |
|---|---|---|---|---|
| `t_oe_on` | **0.423 ns** | **0.975 ns** | **0.973 ns** | OE 标志到 PAD 2.9V（含 OE 逻辑/预驱动/level shifter） |
| `t_oe_off` | **3.12 ns** | **5.28 ns** | **4.33 ns** | OE 标志到 PAD 1.8V（1k 负载释放，含 OE/预驱动） |
| `tr_pad` | **0.129 ns** | **0.240 ns** | **0.319 ns** | 0.33V → 2.9V |
| `tf_pad` | **0.151 ns** | **1.436 ns** | **0.942 ns** | 2.9V → 0.33V |
| `vth_pad` | **1.526 V** | **1.514 V** | **1.466 V** | 接收器 IN 跨 1.65V 时的 PAD 电压 |
| `ihiz_max` | **0.146 nA** | **13.5 pA** | **57.0 pA** | PU_OK=0，输出关断，外部源扫 PAD 0→3.3V（不含 ESD） |
| `iesd_max` | **0.149 nA** | **13.7 pA** | **60.3 pA** | 单独的 ESD 反向泄漏 deck（含输出关断漏电）；不是 ESD 资格 |

**解释边界**：这些数字只属于各自的 fixture 和该轻载。`t_oe_on/off` 含真实的 IO 域 OE 逻辑、预驱动和 OUT 的 core→IO 电平搬移；OE_N/PU_OK 仍是 3.3V IO 域激励，全芯片级控制搬移/缓冲未做。`vth_pad` 不是 VDDIO/2；`ihiz_max` 不含 ESD，`iesd_max` 只是反向泄漏，不是 ESD 应力/资格。不能用于签核、PVT、IBIS 或板级 SI。`reports/capability_report.md` 仍全部 `NO_GO`。

## 5. VREF 接收器

拓扑：PAD 与板上 VREF 进差分对（两个输入都在 VDDIO 域，故只用 IO 器件）、尾电流源、PMOS 镜像负载、单端输出缓冲、再电平搬移回核心。VREF pad 只有 ESD 二极管加金属，没有输出管、没有 DAC/ADC。未定：`W_VREF_N/P`、`I_TAIL`、`W_TAIL`、`W_LOAD`、共模范围、失调、滞后。

### gf180mcu DDR1：远期计划（按用户要求修改约束）

用户要求把 gf180mcuD DDR1 从"硬排除"改成"远期计划"。已改：

- specs/pads/devices/gf180mcuD.yaml 的 ddr1.status = DEFERRED_LONG_TERM，target_phase = P4+；
- docs/ARCHITECTURE.md 第 1 节表格改为"远期计划，本期不做 DDR1"，第 6 节 gf180 DDR1 决策格改为"远期"；
- generator/emit_pads.py 的排除特例换成通用 deferred 提示；generator/check_pads.py 现在要求 DEFERRED_LONG_TERM 且禁止 SUPPORTED。

注意 ARCHITECTURE.md 第 1 节原本就写"本期不做"，第 6 节的"不做"与它并不一致；改成"远期"只是把两者统一，不代表电气可行性变了。

仍然是 NO_GO：DDR1 需要 2.5 V SSTL_2 / VREF，gf180 只有 3.3 V（及 5/6 V）IO 器件，没有 2.5 V IO 模型；ck90 / 相位源（G6）也未解决。生成的 VREF 接收器仍是拓扑研究，不是受支持配置。远期要落地必须关掉 blockers 里三条，而不是改一个状态字符串。

## 6. 什么还没做 / 下一步

1. **填 31 个参数**：gf180mcuD / sky130 / ihp130 各有一份 `design_assumption` fixture 和可跑切片（§4.1），但都不是签核尺寸；ics55 仍未绑定。驱动管宽/指条、ESD 面积、保护环间距仍要负载/ESD 仿真。
2. **`PAD_OE_CTRL` 与 `PDRV_STAGES`**：OE 逻辑已生成为晶体管级 IO 门（INV/NAND/NOR + 可选 core→IO level shifter），预驱动展开成 2 级非反相链；尺寸共用预驱动占位参数，尚未优化；OE_N/PU_OK 仍假定 IO 域。
3. **原理图复核**：二极管极性、体端接法、三端电阻第三端、guard ring 规则。
4. **绑定 device map**：gf180mcuD / sky130 / IHP 已绑定并生成拓扑；ics55 还差 3.3 V ESD 二极管 SPICE 卡，不能用 2.5 V 卡替代。
5. **表征链**：三套 PDK 的预驱动+输出级/接收器切片和 ESD 反向泄漏已可跑（§4.1）；`char_tb.spice` 仍是完整测量清单，ESD 应力/资格、VREF 共模/失调、SSO、PVT/min-max SPICE、PEX、IBIS、SI/PI、DRC/LVS 都还没做。ESD 的 TLP/HBM/latch-up 计划见 `docs/ESD_STRESS_PLAN.md`。
6. **参数语义**：`L_R_SERIES` 现在是片上电阻长度；目标阻值属于板级 SI，不在 pad 参数里。把目标阻值换算成长度仍需要每套 PDK 的 sheet resistance。sky130 的微米/米换算也仍只在注释里，没有代码守卫。
7. **能力报告不变**：`reports/capability_report.md` 仍是全部 `NO_GO`，`backends/gf180mcu.yaml` 的 `toe_on_ps/off_ps` 仍是 `null`，`schematic_drawn` 仍是 `false` —— 拓扑模板不等于"原理图已画完、可签核"。

## 7. 不这样做

- 不把现成 GPIO 当本设计的 pad；不用 5 V / 6 V 器件接 3.3 V SDRAM。
- 不填任何猜测的宽度、电流、阻值、面积或 `nf=1` 之类的默认值（指条数本身就是 §12 的开放问题，已改成 `NF_DEVICE` 参数）。
- 不把核心标准单元当 pad 驱动，不把未核实的器件名写进 SPICE。
- 不把 ics55 的 `dio_2p5_*` 改名成 3.3 V，也不因为三套已绑定就把 ics55 说成已支持。
- 不把“ngspice 能跑 `.op` 的临时值”说成电气表征、尺寸选择或 PVT 结论。
- 不把 xschem 能网表说成电气仿真已跑，不把 DOT 图说成版图。
- 不把生成 gf180 VREF 接收器说成"gf180 支持 DDR1"。
- 不因为写了生成器就改 `NO_GO` 判定；改判定要先改能力证据并重跑 `check_capabilities.py`。
