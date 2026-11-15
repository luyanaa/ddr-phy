# Pad 原理图与 VREF 接收器生成器

状态：**拓扑模板，未表征，NO_GO。** 本轮按"尽量不手工设计、用可重用生成器"的要求，先落地生成器与 gf180mcuD 的首套产物；器件尺寸、指条数、驱动电流、串联电阻、ESD 面积、保护环间距全部仍是参数（`null`），`docs/ARCHITECTURE.md` §12 的开放问题没有被绕过。

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
| `specs/pads/devices/{sky130,ihp130,ics55}.yaml` | 名字抄自 ARCHITECTURE.md §5.1，`status: TBD`、`verified: false`，未核对本地 PDK |
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

## 4. 产物

| backend | device map | 产物 |
|---|---|---|
| gf180mcuD | 已绑定（实测） | `sdr_bidir_pad.spice/.sch`、`vref_receiver.spice/.sch`、`pad_topology.dot`、`char_tb.spice`、`required_params.json`、`manifest.json`、`README.md` |
| sky130 / ihp130 / ics55 | `TBD`（未核对） | 只有 manifest / README / params / DOT / char_tb + `DEVICE_MAP_TBD.md`；**不发 SPICE**，避免编造未核实的器件名 |

SPICE 网表用 `@@DEV_*@@` 绑器件、`@@P_*@@` 留参数名（如 `w=W_N_OUT`、`nf=NF_DEVICE`），条件块 `@if LEVEL_SHIFTER@` 由 `core_v != vddio_v` 决定。gf180 输出里电平搬移块被正确移除。

**验证**：`generator/check_pads.py` 通过（31 参数未解、4 backend、0 签核声明、无 `@@` 残留、无硬编码尺寸）；xschem `-x -n -s` 无 X 头模式能把两张 `.sch` 网表出来（SDR 10 条、VREF 8 条器件/二极管行）；`dot -Tsvg` 能渲染拓扑图。

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

1. **填 31 个参数**：驱动管宽/指条、预驱动级数、串联电阻、ESD 面积、保护环间距 —— 都要负载仿真，不能从库 GPIO 的毫安档推回来（§11/§12）。
2. **展开 `PAD_OE_CTRL` 与 `PDRV_STAGES`**：现在是命名占位子电路与单级代表，不是可综合网表。
3. **原理图复核**：二极管极性、体端接法、三端电阻第三端、guard ring 规则。
4. **绑定另外三套 device map**：核对各自本地 PDK 的器件卡与许可，再重跑生成器。
5. **表征链**：`char_tb.spice` 只是测量清单（`tOE_on/off`、slew、输入门限、上电 Hi-Z、ESD、VREF 共模/失调、SSO），不是可跑 TB；之后才是 PVT/min-max SPICE、PEX、IBIS、SI/PI、DRC/LVS。
6. **能力报告不变**：`reports/capability_report.md` 仍是全部 `NO_GO`，`backends/gf180mcu.yaml` 的 `toe_on_ps/off_ps` 仍是 `null`，`schematic_drawn` 仍是 `false` —— 拓扑模板不等于"原理图已画完、可签核"。

## 7. 不这样做

- 不把现成 GPIO 当本设计的 pad；不用 5 V / 6 V 器件接 3.3 V SDRAM。
- 不填任何猜测的宽度、电流、阻值、面积或 `nf=1` 之类的默认值（指条数本身就是 §12 的开放问题，已改成 `NF_DEVICE` 参数）。
- 不把核心标准单元当 pad 驱动，不把未核实的器件名写进 SPICE。
- 不把 xschem 能网表说成电气仿真已跑，不把 DOT 图说成版图。
- 不把生成 gf180 VREF 接收器说成"gf180 支持 DDR1"。
- 不因为写了生成器就改 `NO_GO` 判定；改判定要先改能力证据并重跑 `check_capabilities.py`。
