# Pad 原理图与 VREF 接收器生成器

状态：**拓扑模板 + 三套已绑定 PDK 的第一版可跑表征切片 + GF180 PVT 第一轮；未表征，NO_GO。** 共享拓扑已扩到 gf180mcuD / sky130 / IHP SG13G2 三套已绑定 device map，并生成 SPICE/xschem 拓扑；ics55 因缺 3.3 V ESD 二极管 SPICE 卡保持未绑定（自绘 GGNMOS 只在 `docs/ICS55_ESD_3V3.md` 做研究）。gf180mcuD / sky130 / ihp130 各有一条明确标注 `design_assumption` 的 sizing fixture 和 ngspice OE+预驱动+输出级/接收器切片（§4.1），外加 ESD 反向泄漏测量，但它们不是签核尺寸。器件尺寸、指条数、驱动电流、串联电阻、ESD 面积、保护环间距在通用拓扑里仍是参数（`null`）。

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

**验证**：`generator/check_pads.py` 通过（31 参数未解、4 backend 中 3 套已绑定、0 签核声明、无 `@@` 残留、无硬编码尺寸、无 `UNBOUND_` 占位、钳位方向正确）；`sh sim/char_pad.sh` 跑出 gf180mcuD / sky130 / ihp130 三份 `reports/pad_char_*.{json,md}`（§4.1，全部 `design_assumption`）；`check_char_pad.py` 校验报告的 `control_domains`（OUT=core，OE_N/PU_OK/PAD=io）以及生成的 `char_tran.spice` 中 VOE/VPU 高电平为 VDDIO、VOUT 高电平为 core VDD；sky130 与 IHP 的生成网表也用临时参数跑过 ngspice `.op` 语法冒烟（见 §3.1）。xschem 自动网表本轮未重跑（本机 `xschem -x -n -s` 在写输出文件时超时），所以不把“xschem 能网表”当作本轮证据；`.sch` 仍只是生成产物。

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
| `tr_pad` | **0.129 ns** | **0.272 ns** | **0.316 ns** | 0.33V → 2.9V |
| `tf_pad` | **0.151 ns** | **1.436 ns** | **0.942 ns** | 2.9V → 0.33V |
| `vth_pad` | **1.526 V** | **1.514 V** | **1.466 V** | 接收器 IN 跨 1.65V 时的 PAD 电压 |
| `ihiz_max` | **0.146 nA** | **13.5 pA** | **57.0 pA** | PU_OK=0，输出关断，外部源扫 PAD 0→3.3V（不含 ESD） |
| `iesd_max` | **0.149 nA** | **13.7 pA** | **60.3 pA** | 单独的 ESD 反向泄漏 deck（含输出关断漏电）；不是 ESD 资格 |
| `t_in` | **6.026 ns** | **6.030 ns** | **6.033 ns** | PAD 1.65V → IN 1.65V；接收器 + 1 GΩ bleed |
| `voh_2ma` | **3.30 V** | **3.30 V** | **3.30 V** | 2 mA 源电流（设计假设负载） |
| `vol_2ma` | **2.9 nV** | **0.23 nV** | **1.15 nV** | 2 mA 灌电流（模型值，接近 0） |

**解释边界**：这些数字只属于各自的 fixture 和该轻载。`t_oe_on/off` 含真实的 IO 域 OE 逻辑、预驱动和 OUT 的 core→IO 电平搬移；OE_N/PU_OK 仍是 3.3V IO 域激励，全芯片级控制搬移/缓冲未做。`vth_pad` 不是 VDDIO/2；`ihiz_max` 不含 ESD，`iesd_max` 只是反向泄漏，不是 ESD 应力/资格。不能用于签核、PVT、IBIS 或板级 SI。`reports/capability_report.md` 仍全部 `NO_GO`。

### 4.2 GF180 PVT 第一轮（P1-1）

`emit_char_pad.py` 现在支持 `--corner tt|ss|ff`、`--temp`、`--vdd/--vddio`、`--load-kohm/--load-pf`、`--tag`。GF180 已跑：

```text
tt/27C、ss/125C、ff/-40C、tt/27C/VDDIO=2.97V、tt/27C/VDDIO=3.63V
```

| 条件 | tOE_on | tOE_off | tr | tf | vth | ihiz | iesd | t_in |
|---|---|---|---|---|---|---|---|---|
| tt/27/3.3 | 0.423 ns | 3.12 ns | 0.129 ns | 0.151 ns | 1.526 V | 0.146 nA | 0.149 nA | 6.026 ns |
| ss/125/3.3 | 0.592 ns | 3.26 ns | 0.165 ns | 0.200 ns | 1.540 V | 0.286 nA | 0.290 nA | 6.032 ns |
| ff/-40/3.3 | 0.320 ns | 3.03 ns | 0.105 ns | 0.125 ns | 1.529 V | 0.154 nA | 0.157 nA | 6.020 ns |
| tt/27/2.97 | 0.608 ns | 2.92 ns | 0.291 ns | 0.198 ns | 1.356 V | 0.123 nA | 0.126 nA | 6.028 ns |
| tt/27/3.63 | 0.375 ns | 3.30 ns | 0.097 ns | 0.131 ns | 1.700 V | 0.183 nA | 0.187 nA | 6.024 ns |

复现：`sh sim/char_pvt.sh`。报告：`reports/pad_char_gf180mcuD_{tt_27,ss_125,ff_-40,tt_27_v2.97,tt_27_v3.63}.md`。`voh_2ma` 等于当时的 VDDIO；`vol_2ma` 在 2 mA 下接近 0。**这是设计假设下的第一轮 PVT，不是 min/max 配对、PEX 或签核。**

## 5. VREF 接收器

通用生成器拓扑：PAD 与板上 VREF 进差分对（两个输入都在 VDDIO 域，故只用 IO 器件）、尾电流源、PMOS 镜像负载、单端输出缓冲、再电平搬移回核心。VREF pad 只有 ESD 二极管加金属，没有输出管、没有 DAC/ADC。通用模板的器件尺寸、共模范围、失调、滞后仍未定。

### IHP SG13G2 DDR1 单 DQ

[`ihp130_sstl2_dq`](../sch/pads/ihp130/sstl2_dq.spice) 独立于 SDR pad 生成器。使用 SG13G2 厚氧器件在 2.5 V 域做差分接收、预驱动和 TX，薄氧缓冲只在 1.2 V 核心域。TX 的数据与 OE 分别电平搬移，`PU_OK` 撤销时关闭上、下拉输出管。RX 接收外部 VREF，经核心电源上拉、HV NMOS 下拉的电平搬移器后再缓冲；读低时有静态核心电流。TX 有片上串联电阻；PAD 两端二极管用于名义电容及泄漏建模，不是经资格认证的 ESD 网络。

- SPICE 引脚顺序：`OUT OE IN PAD VREF PU_OK VDD VSS VDDIO VSSIO`。`OUT`/`OE` 是核心输入（OE 高有效），`IN` 是核心输出，电源地同参考。
- `PU_OK` 是**外部 I/O 域**电源监控输出。两轨达标前保持低，任一轨掉电前撤销；无效电源期间不使用 `IN`。不支持 VDDIO 关闭时外部仍驱动 PAD，高侧二极管可反灌。宏内无电源监控器、VREF 发生器或 VREF pad。
- 以 [Micron MT46V32M8 数据表](https://www.micron-electronic.com/pdf-ba/mt46v32m8tg-75-it-g.pdf) 表 12–14 为电平边界：VDDIO 2.30–2.70 V，DC 接收刺激为 VREF±150 mV，TX 到达 VREF±310 mV 才算有效。DC 分别取 VREF 为 VDDIO 的 49%、50%、51%；瞬态取 50%，终端为 50 Ω 到独立 VTT 电源并联 5 pF 外部负载，VTT 相对 VREF 偏移 0、±40 mV。TX 数据输入边沿 0.3 ns，含一对间隔 5 ns 的翻转；RX 输入在 VREF±310 mV 间过渡 0.8 ns，核心负载 30 fF。
- 本地分配为 RX/TX 均 ≤1.50 ns（RX 到 0.2/0.8 VDD），OE 使能、OE/`PU_OK` 释放均 ≤2.50 ns（释放到 VTT±50 mV）；不是 DRAM 的 setup/hold 或 tHZ。DC 检查两种 TX 数据的关断泄漏，上电瞬态检查核心先上、I/O 先上两种顺序；高、低驱动请求均在 `PU_OK=0` 时被阻断，VREF/PAD 随 VDDIO 爬升。脚本将高阻漏电限为 ±5 µA、爬升 PAD 电流（含位移电流）限为 ±0.5 mA。

复现（ngspice 44.2、PyYAML、Ciel SG13G2 `89d42ee6d2fd9b50b86a1aada6fee6673c3e6008`，需有 PSP/R3/mosvar OSDI）：

```sh
(
    set -e
    for mv in -40 0 40; do
        python3 generator/char_ihp130_sstl2.py --vtt-offset-mv "$mv" \
            --output "/tmp/ihp130-sstl2-${mv}.json"
    done
)
```

脚本复用 `generator/emit_char_pad.py` 的 SG13G2 模型装载和测量解析；`--pdk-root` 固定模型目录，`--case ss_low` 聚焦 SS/125 °C/低压点。JSON 含每点 SI 测量值和越界项，`signoff` 始终为 `false`。

7 个指定 PVT 点（核心 1.08–1.32 V，温度 −40 至 125 °C）× 3 个 VTT 偏移均通过。不是全因子或失配表征。

| 指标 | 21 组中的最坏值 |
| --- | ---: |
| RX / TX 延迟 | 1.409 / 1.476 ns |
| OE 使能 / OE 释放 / `PU_OK` 释放 | 1.652 / 1.891 / 1.654 ns |
| `VOH−VREF` / `VREF−VOL`（最小） | 406.7 / 420.5 mV |
| RX 确定性翻转点偏移 | −9 至 −3 mV（DC 步长 2 mV，不含失配） |
| 正常关闭 / 上电平台高阻漏电（绝对值） | 26.9 / 53.8 nA |
| 上电 PAD 爬升电流（绝对值） | 91.3 µA |
| RX I/O 偏置 / 读低时核心电流 | 0.132–0.251 / 0.092–0.161 mA |
| 单 pad TX I/O 电流峰值（含负载和内部切换） | 34.2 mA |

最坏 TX 为 SS/125 °C、核心 1.08 V、VDDIO 2.30 V、VTT=VREF+40 mV 的下降沿，距 1.50 ns 只剩 24 ps；不能当作布线后余量。

#### 尺寸网格搜索（生成器后端证据，2026-11-26）

`generator/tune_ddr1.py --backend specs/ddr1/ihp130-sstl2.yaml` 对 `XRDRIVER` rppd 总宽 w ∈ {8, 12} µm × `XRBIAS` rhigh 长度 l ∈ {13, 10} µm 跑 2×2 网格。开发用例为 tt/VTT+0 mV 与 SS/125 °C/低压/VTT+40 mV，硬边界来自表征器 JSON 的 failures；目标是开发最坏 RX/TX 传播延迟最小，偏置/TX 峰值电流为平局裁决。获胜组合再单独跑 holdout FF/−40 °C/高压/VTT−40 mV——未参与选型。

证据 `results/ihp130/ddr1-tune-20261126.json`（SHA256 钉住了适配器、spec、基线 netlist）：4/4 trials 可行，`signoff=false` 不变。**推荐 `XRDRIVER w=12u, XRBIAS l=13u`（trial-03）**，holdout 通过且裕量显著（FF/−40 °C 下 RX 0.77 ns、TX 0.63 ns，约为 SS 开发点的一半）。开发点最坏值随 w 增大：TX fall 从 1.476 ns（w=8u）降到 1.448 ns（w=12u），代价是 TX I/O 峰值 22.0→23.2 mA；RX rise/fall 不受 TX 宽度影响。l=10u 降低 RX fall 延迟（1.410→1.339 ns）但增大偏置，且 trial-03 与 trial-04 的最大传播同为 TX-fall 1.448 ns——平局按偏置电流裁决，l=13u 胜出。这是原理图级、4 点离散网格、3 个 PVT 见证点，不是失配/全因子签核；布线后 PEX 网表的复测见上节。


### IHP SG13G2 单 DQ 版图与 PEX

当前证据为[单 DQ 布线改版](../results/ihp130/sstl2-dq-route-eco/)。[版图生成器](../generator/ihp130_dq_layout.py)加宽输出级与电源/回流通路、并联过孔，并缩短接收端 `SENSE`、`MIRROR`、`DEC_B`、`RX_LEVEL` 的连线。[原理图](../sch/pads/ihp130/sstl2_dq.spice)与[器件几何生成器](../generator/ihp130_dq_devices.py)不变，`XRDRIVER` 仍为 W/L = 8/0.60 µm。宏内 `VSS`/`VSSIO` 共用实际的 `VSSIO` 端口，正电源保持分开；`PAD` 是金属端口，未做封装焊盘开口。

KLayout 0.30.12 在未修改的 SG13G2 `drc/ihp-sg13g2.drc` 主规则表下报告 **0 条宏级 DRC 标记**；`lvs/sg13g2.lvs` 匹配全部 9 个端口和 54 个逻辑器件，未启用虚连接或忽略端口，LVS 参考网表与归档基线逐字节相同。宏宽保持 106.06 µm，高度由 199.98 µm 增至 204.46 µm。Magic 8.3.685 从相同掩模几何提取分布 R、对衬底 C 和耦合 C，PEX 视图只增加探针标记。Magic 不提取这两种转向二极管的结模型；仿真在 LVS 和电阻网络均确认的局部端点接入 PDK 原模型，保留原始 RC 网表。

表征沿用 **50 Ω 到独立 VTT、5 pF 负载**和原判据：RX/TX ≤1.50 ns，OE 启停 ≤2.50 ns（关闭测到 VTT±50 mV），输出阈值为 VREF±310 mV。以下当前结果取自 [TT JSON](../results/ihp130/sstl2-dq-route-eco/pex_tt.json) 和 [SS JSON](../results/ihp130/sstl2-dq-route-eco/pex_ss_low.json)。

| 版图后指标 | TT / 27 °C，1.20 V 核心 / 2.50 V I/O，VTT=VREF | SS / 125 °C，1.08 V 核心 / 2.30 V I/O，VTT=VREF+40 mV |
| --- | ---: | ---: |
| RX 上升 / 下降延迟 | 1.252447 / 1.356030 ns | 1.614825 / 1.967438 ns |
| TX 上升 / 下降延迟 | 1.256686 / 1.278138 ns | 1.865439 / 2.200611 ns |
| TX VOH / VOL | 1.685563 / 0.7961452 V | 1.528865 / 0.8188691 V |
| VOH 下限 / VOL 上限 | 1.560 / 0.940 V | 1.460 / 0.840 V |
| OE 启用 / 关闭（各自最慢） | 1.500939 / 1.787250 ns | 2.462138 / 2.332184 ns |
| 上电平台高阻漏电（绝对值最大） | 50.826 nA | 61.922 nA |
| 该表征点结果 | PASS | FAIL：仅 RX/TX 延迟超限 |

[旧版图基线](../results/ihp130/sstl2-dq.pNCnxrLD/)保留：旧 TT / SS 的 RX 分别为 1.471263/1.600795 ns 和 1.909221/2.340219 ns，VOH/VOL 分别为 1.534511/0.9549794 V 和 1.422252/0.9347695 V；两角 TX 均未跨过接收阈值。改版后两角电平和 OE 都达标，没有新增超限项。[SS 带载直流数据](../results/ihp130/sstl2-dq-route-eco/tx_dc_points.log)确认 `XRDRIVER` 的 PAD 侧接线电阻从 39.385 Ω 降至 13.431 Ω；器件本身约 29.893 Ω。剩余阻塞是 SS 下 TX 预驱动延迟与 RX 比较器判决速度；目前不能按 1.50 ns 预算复制为 x8。

[ESD 连线提取](../results/ihp130/sstl2-dq-route-eco/metal_metrics.log)仅计算导体网络的等效电阻，不含二极管结、共享电源钳位或封装。正向放电路径（PAD → 上转向二极管 → VDDIO）从 59.149 Ω 降至 50.956 Ω；负向放电路径（VSSIO → 下转向二极管 → PAD）从 32.258 Ω 降至 28.891 Ω。PDK `libs.ref/sg13g2_io/spice/sg13g2_io.spice` 的 `sg13g2_IOPadIOVdd`（配套 `sg13g2_IOPadIOVss`）是供评审的候选，不是本宏已接入的钳位。随附 I/O 库角为 3.0/3.3/3.6 V，不证明 DDR1 的 2.3–2.7 V 兼容性；`diodevdd_2kv` / `diodevss_2kv` 的名称也不证明本设计通过 2 kV HBM。还需确定封装和 pad ring、接通共享钳位，并验证目标电压内的钳位行为、TLP/HBM/CDM、闩锁及芯片级密度/天线。单宏 DRC/LVS 不覆盖这些项目，也不改变后端 `NO_GO`；`flow/run.sh ihp130` 仍只跑标准单元流程。

复现：从仓库根目录运行；归档环境为下列 SG13G2 版本、KLayout 0.30.12、Magic 8.3.685（`xvfb-run`）、Python/PyYAML 和带 OSDI 的 ngspice 44.2。每次新建输出目录，不覆盖归档；SS 命令因延迟超限写出 JSON 后返回 1。

```sh
export IHP_PDK="$HOME/.ciel/ciel/ihp-sg13/versions/89d42ee6d2fd9b50b86a1aada6fee6673c3e6008/ihp-sg13g2"
export KLAYOUT=/nix/store/1whjbzm6gw6l4h0sjxdv92lyw7lq1ar8-klayout-0.30.12/bin/klayout
out="$(mktemp -d)/dq"
sh sim/ihp130_dq_layout.sh "$out"
python3 generator/char_ihp130_sstl2.py --pdk-root "$IHP_PDK" \
    --cell-netlist "$out/sstl2_dq_pex.spice" --case tt --output "$out/pex_tt.json"
python3 generator/char_ihp130_sstl2.py --pdk-root "$IHP_PDK" \
    --cell-netlist "$out/sstl2_dq_pex.spice" --case ss_low --vtt-offset-mv 40 \
    --output "$out/pex_ss_low.json"
```

如工具安装路径不同，调整 `KLAYOUT` 与 `IHP_PDK`；表征与版图须使用同一 PDK。归档包括掩模 GDS、DRC/LVS 报告、Magic 原始 RC、可仿真 PEX 网表、测量 JSON 与 [`SHA256SUMS`](../results/ihp130/sstl2-dq-route-eco/SHA256SUMS)。

### gf180mcu DDR1：远期计划（按用户要求修改约束）

用户要求把 gf180mcuD DDR1 从"硬排除"改成"远期计划"。已改：

- specs/pads/devices/gf180mcuD.yaml 的 ddr1.status = DEFERRED_LONG_TERM，target_phase = P4+；
- docs/ARCHITECTURE.md 第 1 节表格改为"远期计划，本期不做 DDR1"，第 6 节 gf180 DDR1 决策格改为"远期"；
- generator/emit_pads.py 的排除特例换成通用 deferred 提示；generator/check_pads.py 现在要求 DEFERRED_LONG_TERM 且禁止 SUPPORTED。

注意 ARCHITECTURE.md 第 1 节原本就写"本期不做"，第 6 节的"不做"与它并不一致；改成"远期"只是把两者统一，不代表电气可行性变了。

仍然是 NO_GO：DDR1 需要 2.5 V SSTL_2 / VREF，gf180 只有 3.3 V（及 5/6 V）IO 器件，没有 2.5 V IO 模型；ck90 / 相位源（G6）也未解决。生成的 VREF 接收器仍是拓扑研究，不是受支持配置。远期要落地必须关掉 blockers 里三条，而不是改一个状态字符串。


### 跨四工艺 DDR1 SSTL-2 生成器链（2026-11-26 新增）

在 IHP 单 lane 之上重构为**共享引擎 + 每工艺薄 profile**：`generator/char_ddr1_sstl2.py` 是工艺中立的表征引擎（DC/瞬态/功耗三 bench、JEDEC SSTL-2 检查、PVT 角遍历），每工艺一个 `char_ddr1_<pdk>.py` 薄 profile 只声明子电路名、角映射、器件 yaml、电阻/额外模型行与许可。`generator/tune_ddr1.py --backend specs/ddr1/<pdk>-sstl2.yaml` 对所有 lane 统一跑离散尺寸网格（开发点选型 + 留持点验证）。lane 契约见 `generator/LANE_CONTRACT.md`。

架构事实：engine 的 bench 完全工艺中立；ihp130 作为参考 lane 重构后逐值复现原表征（tt RX 0.904/0.992 ns、TX 0.885/0.907 ns），证明共享引擎无损耗。

#### 一个跨 PDK 的仿真器陷阱及其绕过

sky130 与 gf180mcu 的 IO MOS 是 BSIM4 binned 模型。ngspice 44.2 strict paramchk 在实例用**大 nf** 时拒绝 foundry bin：`Fatal: u0 at current temperature = -0.005 is not positive`。已在两 PDK 隔离为 **nf 数值本身**触发（与几何 bin 无关）。**绕过：大器件一律用平行 multiplier（gf180 `m`、sky130 `mult`）而非大 nf**——multiplier 不参与 bin/u0 提取。IHP 不受影响（PSP103 osdi 紧凑模型，无 BSIM4 binning）。此规则已写入 LANE_CONTRACT。这是历史 ngspice 路径的限制；不能把该诊断外推到保留 BINUNIT 和几何系数的 Xyce PM3 模型。

#### 四 lane 现状（实测，非推断）

| lane | 许可 | 器件 | 仿真状态 | signoff |
| --- | --- | --- | --- | --- |
| ihp130 | Apache-2.0 | 厚氧 2.5 V 域 RX/TX，薄氧 1.2 V 核心 | **完整 PASS**（7 PVT × 3 VTT，见 §5） | false |
| gf180mcu | Apache-2.0 | 此版用 3.3 V 器件；无原生 2.5 V IO | 当前 TX 跨域保护与先断后通方案：TT、SS 开发点及独立 FF 留持点 PASS；资格判定仍 **NO_GO** | false |
| sky130 | Apache-2.0 | g5v0d10v5 5 V 栅（欠压 2.5 V） | Xyce：7/7 PVT witness + tune/留持点 PASS | false |
| ics55 | foundry evaluation-only | **唯一原生 2.5 V IO + 2.5 V 二极管** | **全 7 PVT 角 PASS + dev_multi_corner tune PASS**（见下） | false |

**历史：gf180mcu DDR1 第一次 TX 修复（电平转换锁存器）**：[旧版调参归档](../results/gf180mcu/ddr1-tune-20261126.json)中的四个试验均未找到可行解；四者的 PMOS/NMOS 尺寸完全相同，只遍历串联电阻 `XRDRIVER` 的宽度（8/12 µm）和 RX 偏置电阻 `XRBIAS` 的长度（13/10 µm），不是功率管宽度网格。在 SS/125 °C、VTT +40 mV 下，原电路使能时 `OUT=0` 导致上下管均关断，VOL = 1.190 V = VTT；`OUT=1` 则同时命令上下管导通，VOH 仅 1.239–1.242 V，TX 上升和下降均未越过有效阈值。首次修复为 OUT/OE 增加 core→IO 电平转换锁存器，由 `PU_OK` 门控使能，再产生互补驱动；P/N 功率管仍为 `5 µm × 40` / `4 µm × 18`，串联电阻也保持不变。相同电源、功率管尺寸和串联电阻下修复后可正常驱动，说明旧失败不能仅归因于 VDDIO 或功率管尺寸。

[修复后调参归档](../results/gf180mcu/ddr1-tx-repair-tune.json)退出码为 0：仅运行默认 `XRDRIVER w=8 µm` / `XRBIAS l=13 µm` 一组，TT（VTT 偏移 0 mV）和 SS/125 °C（+40 mV）开发点、FF/−40 °C（−40 mV）留持点均 PASS。[独立 SS −40 mV 检查](../results/gf180mcu/ddr1-tx-repair-ss-minus40.json)也 PASS。均使用 50 Ω / 5 pF 负载和原判据，不代表完整网格或全 PVT 覆盖。

| SS/125 °C 的 VTT 偏移 | TX 上升 / 下降 (ns) | VOH / VOL (V) |
| --- | --- | --- |
| +40 mV | 0.969290 / 1.211162 | 1.575729 / 0.784017 |
| −40 mV | 1.089111 / 1.080349 | 1.521392 / 0.728447 |

第一次修复的两组 SS 检查中最小 TX 传播裕量为 288.838 ps（+40 mV 的下降沿，限值 1.5 ns）。当时调参 JSON 记录的网表 SHA-256 `1d1f5271a240352911de4517b328d6d43f86d3f95e44a5cf8ce9f115fb68ee10` 对应运行时的注释版本；之后仅更新了一条注释，SPICE 语句不变。

**历史：第一次修复的交叠与跨域电压**：

[SS +40 mV 栅极报告](../results/gf180mcu/ddr1-tx-repair-gates.json)记录六个带终端负载的 DC 状态，并验证 OE 为低或 `PU_OK` 为低时两管均关断，与 OUT 无关。沿用原有 300 ps 激励，数据下降沿两管同时高于模型阈值约 66 ps；这不是直通电流测量。[`ff_high` 跨域器件报告](../results/gf180mcu/ddr1-tx-repair-crossing.json)显示最坏瞬态 `|VGS| = |VGB|` 为 3.6627 V，`|VGD|` 达 3.6624 V。[GF180 DRM §14.1.4.2](https://gf180mcu-pdk.readthedocs.io/en/latest/physical_verification/design_manual/drm_14_1.html) 的 3.63 V 是 **DC** 限值，不是瞬态可靠性判据；越轨及 TDDB 仍是待评估风险。此证据不含 PEX 或 ESD 资格验证，也不能替代 foundry 对 2.5 V 工作点的支持；`signoff=false`、`NO_GO` 不变。

**当前 gf180mcu DDR1：跨域保护与先断后通（BBM）**。OUT、OE 各通过高阻多晶硅分压器（上/下臂 L=2.5/15 µm，W=1.2 µm），再由两级 I/O 供电的 03v3 反相器恢复互补电平；原始核心输入不再直接驱动 MOS 栅极。导通请求须同时满足原始 `DATA`、延迟 `DATA` 和 `EN`；`P1` 的 CMOS NOR 直接用 `DATA_L` 提前关断 PMOS，不等 `DATA_H` 恢复。`PU_OK` 仍可优先禁止输出，不等待数据延迟。最终功率管、串联电阻、RX、共享测试平台和判据均未改变。

- [常规及快速反转波形](../results/gf180mcu/ddr1-tx-guard-waveforms.json)与[热快角波形](../results/gf180mcu/ddr1-tx-guard-ff-hot.json)：在 SS/+40 mV、冷 FF/−40 mV、热 FF/标称 VTT 的常规激励和 SS/冷 FF 的快速反转中，均未观测到上下管同时具有正 BSIM4 过驱动。保存步长不超过 5 ps；快速反转覆盖 300 ps 的上升及下降斜率、0/200/500 ps 保持时间。按采样区间保守估计，最小先断后通间隔为 SS 130 ps、冷 FF 25 ps、热 FF 20 ps（热 FF 插值 27.926 ps）。这不是零直通电流的证明。
- 同为冷 FF、VTT −40 mV，最大栅极到端子电压绝对值从 3.662700 V 降至 3.063428 V；热 FF 标称 VTT 为 3.077161 V。[冷 FF 两种电源爬升顺序](../results/gf180mcu/ddr1-tx-guard-power.json)的最大栅极到端子电压绝对值为 3.051471 V；强制 PAD 的最大爬升电流绝对值 110.347 µA，最大平台电流绝对值 8.218 nA，原判据均通过。3.63 V 仅作 DC 筛查比较，不是瞬态应力或寿命资格判定。
- [当前默认单试验调参](../results/gf180mcu/ddr1-tx-guard-tune.json)的 TT/0 mV、SS/+40 mV 开发点和独立 FF/−40 mV 留持点均 PASS；SS/+40 mV 的 TX 上升/下降延迟为 1.340551/1.328074 ns。[独立 SS −40 mV](../results/gf180mcu/ddr1-tx-guard-ss-minus40.json)为 1.462911/1.194222 ns，两组 SS 相对 1.5 ns 限值的最小裕量为 37.089 ps。常规 SS/冷 FF、快速反转及爬升波形在删去未用的内部引脚前测得，电路等效；热 FF 及当前调参使用已部署的精确 SHA-256 `ac311309f7318ce8f99006777b2e05c8430a2fec202eabf4a7cd11f361cd115e`。
- 高电平 OUT 或 OE 的静态分压电流每引脚为 SS 0.452 mA、冷 FF 0.801 mA、热 FF 0.818 mA；上述探针使用理想输入源，未验证上游驱动、电源或 PEX，也不构成可靠性或 ESD 资格认证。`signoff=false`、`NO_GO` 不变。

复现当前版（输出写入新路径）：仅运行默认尺寸的一次试验及独立 SS −40 mV 检查，不代表完整 PVT 或尺寸网格。

```sh
python3 generator/tune_ddr1.py --backend specs/ddr1/gf180mcu-sstl2.yaml --max-trials 1 --output /tmp/gf180-ddr1-tune.json
python3 generator/char_ddr1_gf180mcu.py --case ss_low --vtt-offset-mv -40 --output /tmp/gf180-ddr1-ss-minus40.json
```

**ics55 的工具边界与 corner 接入**：foundry hspice 嵌套 .lib wrapper 无法被 ngspice 解析（内层重复 `.INC` 子电路→重定义 fatal），唯一可行路径是**扁平 include + 逐角提取非零 wrapper 偏移生成 `cornerparams_<corner>.inc`**。生成器 `generator/gen_ics55_corners.py`（已入 repo，reproducible——regenerate 与部署版逐字节一致）从 `model_wrapper1/2_hsp.lib` 的 tt/ss/ff/fnsp/snfp mos 段与 res/dio 段提取 `.PARAM` delta，在 corner_ratio=1 求值、agauss 失配项强制 0，参数集取原 tt 骨架与全部 wrapper delta 的**并集**（骨架漏了 `drsh_re_hrpo_3t`/`ddw_re_hrpo_3t`/`dtoxp_pm2p5_lp`，其中 drsh 跨角 ±270 Ω/sq 对高阻电阻影响最大）。`char_ddr1_ics55.py` 的 `extra_model_lines` 按 mos_corner 注入对应文件，include 顺序无关（ngspice 在扁平化时统一求值，已验证）。单管验证 ss/ff 偏移方向正确（ff Id +14%、ss −14%）。fnsp/snfp 无专属 res/dio 段，按最近似配 res_ss/dio_ss（已在生成器 docstring 注明）。`.option scale=0.9` 实测仅 +0.5% Id（BSIM4 bin 有效几何由 xl/xw offset 主导），可忽略。`re_ppo_sab_3t`（non-salicided）有 foundry bug——`weff` 引用未定义的 `dw`；改用 `re_ppo_3t`（salicided，dw 定义完整）→ 进一步换高阻 `re_hrpo_3t`。1.2 V 核心器件 nsvt/psvt 的 BSIM4 bin 插值（`evalbin_core`）在 ngspice 下解析失败，故 RX 内部缓冲用全 IO 域 witness。证据一律 `license=evaluation-only`、`signoff=false`，永不用于 tapeout signoff。

#### sky130：Xyce witness 与 YAML 导出

`generator/emit_ddr1_pad.py` 读现有 `specs/ddr1/<pdk>-sstl2.yaml`，用 adapter 绑定基准尺寸和器件 YAML，输出 `sstl2_dq.spice`、`parameters.json`、`corners/<case>.inc`。IHP/ics55 仍用 ngspice，并导出 `.spiceinit`；`characterization.profile` 可指向独立模型 profile，不改变 `characterization.script` 的 tune 入口。新生成目录必须不存在。Xyce bundle 的 `sstl2_dq.spice` 已展开；在目标仿真 deck 中 include 它和所选 corner 文件，不要将已展开文件当作 `--cell-netlist` 的原始尺寸网表。

```sh
work=$(mktemp -d)
python3 generator/emit_ddr1_pad.py --backend specs/ddr1/sky130-sstl2.yaml --out-dir "$work/bundle"
python3 generator/char_ddr1_sky130.py --output "$work/pvt.json"
python3 generator/tune_ddr1.py --backend specs/ddr1/sky130-sstl2.yaml --max-trials 1 --output "$work/tune.json"
python3 generator/char_ddr1_sky130.py --case ss_low --vtt-offset-mv -40 --output "$work/ss-low-minus40.json"
```

在 `PATH` 提供 `Xyce`，或用环境变量 `XYCE` 指定可执行文件。实测 Xyce 7.10.0-opensource，Ciel snapshot `8afc8346a57fe1ab7934ba5a6056ea8b43078e71`。五套宽区间 `__<corner>.pm3.spice` 按单指宽 `W/NF` 和 L 选 bin；M 实例用米制总宽并保留 NF 和 multiplier。保留 `BINUNIT=2` 及同一行花括号后的全部几何项。只恢复 `BINUNIT` 的诊断试验从 DCOP 失败变为跑满 10 ns（0.206229 s）；这不是完整电气表征。Xyce 用 `.options device temp=…`，不会把被忽略的 `.TEMP` 当成有效温度；−40/125 °C 的实际单管工作点见 [温度校准](../results/sky130/ddr1-xyce-temperature.json)。

选定的联合尺寸由[变更前级联阶段测量](../results/sky130/ddr1-xyce-ss-margin-stages.json)定位瓶颈（OUT→DATA_H/L 为 0.529/0.608 ns）：XPA/XPB 总宽从 7 µm（nf=2）增至 14 µm（nf=4），保持每指 3.5 µm、L=0.5 µm；XPPRE 缩至 wn/wp=14/30 µm（nf=5），XNG 缩至 30/75 µm（nf=10），XDET 设为 wn=3.6。Rseries、最终输出晶体管、XRDRIVER W=40 µm 和 XRBIAS L=6 µm 均未改变。在真实 125 °C、VDD=1.62 V、VDDIO=2.30 V 的 canonical `ss_low` 标称 VTT 下，TX rise/fall 从 1.495937/1.474335 ns 改善为 1.361372/1.332090 ns，RX fall 从 1.339242 ns 改善为 1.238543 ns；按不变的 1.5 ns 传播上限，最坏边沿余量从 4.063 ps 增至 138.628 ps。峰值 |TX I/O| 为 14.740→14.907 mA。旧的[原始七角 PVT 报告](../results/sky130/ddr1-xyce-pvt.json)仅作为变更前基线；当前候选的[7/7 标称 PVT](../results/sky130/ddr1-xyce-ss-margin-pvt.json)通过，[单默认尺寸 tune](../results/sky130/ddr1-xyce-ss-margin-tune.json)通过 `ss_low` +40 mV 与 `ff_high` −40 mV 留持点，而[ss_low −40 mV 验证](../results/sky130/ddr1-xyce-ss-margin-vtt-minus40.json)也通过。`--max-trials 1` 用于核验 canonical 默认尺寸，不表示重新搜索完整尺寸网格；−40 mV 是已测 ss_low VTT 角中的最坏点，TX rise=1.388511 ns，余量 111.489 ps。

边界：2.5 V 是 5 V 栅器件的非 characterized witness；BSIM4 4.5 由 Xyce 走 4.8.2。高阻 poly 用含实际头部宽度的 30 °C 标称线性近似，`res` 字段仅为 case 标签；二极管为无周边/高注入项的 level-1 近似。结果不含 PEX、版图或 ESD 资格认证，`signoff=false`，不改变能力表 `NO_GO`。

**ics55 全 7 PVT 角 PASS + dev_multi_corner tune PASS（2026-11-26）**：`tune_ddr1.py` 端到端 `pass`，development 跨 **tt / ss_low / ff_high 三 PVT extreme**（不再 tt-only）、holdout（tt+40 mV）`passed`，推荐 trial-04（xrdriver_w 12 / xrbias_l 10），证据 `results/ics55/ddr1-tune-20261126.json`（SHA256 钉住）；winner knobs 下全 7 角 witness `results/ics55/ddr1-corner-witness-20261126.json` 逐角 PASS，物理梯度单调（ff 最快 → tt → 混合角 → ss 最慢）。**tt**：rx_rise 0.86 ns / rx_fall 0.81 ns、tx_rise 0.75 / tx_fall 0.87 ns、tx_high 1.885 V、tx_low 0.617 V。**最严苛 ss_low**（1.08 V core / 2.3 V IO / 125 °C / ss）：rx 1.34/1.36 ns、tx 1.16/1.42 ns 全达标（限 1.5 ns），VOH 1.644 V。**ff_high**（−40 °C/高压）最快 rx 0.58/0.56 ns、VOH 2.145 V。跨角 tx_high 1.64–2.15 V、tx_low 0.55–0.77 V 全在 SSTL-2 窗内，漏电/上电馈通 nA–亚µA 级各角干净。**关键工程突破——ss 角速度极限靠电平搬移器/RX 重设计而非 knobs 解决**：原 tt-only 设计接 corner 后，ss_low tx_fall 卡 1.8 ns 且**所有现有 knobs 无效**——xrdriver_w 8→24 µm tx_fall 饱和 1.7 ns、driver MOS 1×→3× 平坦（瓶颈不在输出级），级间分解证实 65% 延迟在 cross-coupled latch 搬移器翻转（NMOS 下拉 w5 vs PMOS latch w1 竞争）+ 1.08 V 低压核心逻辑链。重设计（证据驱动）：搬移器 NMOS 下拉 5→12 µm + 其 core_inv wn2/wp4→wn5/wp12（对标 ihp130 的 8:1 下拉比）、RX 输出缓冲 core_inv 加 wn6/wp12、XRDOWN 电平转换电阻 l10→5 µm。注意单纯加大 PMOS latch 会锁死（实测 VOH 崩 0.74 V）、单纯加大 RX buffer 反而拖慢 rx_level（须配 XRDOWN 减小）——均为实测反例。重设计后 tt 也加快（rx 0.99→0.86 ns），无角退化。**两个隐蔽缺陷修复链**(corner 接入前已完成，仍适用）：(1) **电阻选型**——偏置/下拉最初误用 salicided `re_ppo_3t`（~10 Ω/sq）致 RX_LEVEL 上拉过强卡死；换高阻 `re_hrpo_3t`（~962 Ω/sq）后正常。(2) **ESD 二极管面积缺失**——`DESDHI/DESDLO` 原缺 `area`/`pj`，ngspice 回退模型卡占位 `pj=240 µm`，cjsw 结电容在上电 ramp 耦合充电经 pad 放电致 −18 µA transient 馈通；补 `area=20 µm²`+自洽 pj 后 hiz −18→−0.167 µA、ramp ±0.26 mA，三证（稳态消失/静态 −0.15 nA/删管降 450×）锁定容性根源。**诚实边界**：20 µm² 是 pre-layout witness 假设非 foundry HBM/CDM 签核；ics55 无公开 ESD 设计规则；核心器件 evalbin 不可用故 RX/TX 缓冲是全 IO 域 witness（可能高估核心域延迟，实际用真核心器件或更快）。证据一律 `license=evaluation-only`、`signoff=false`，永不用于 tapeout signoff。

## 6. 什么还没做 / 下一步

1. **填 31 个参数**：gf180mcuD / sky130 / ihp130 各有一份 `design_assumption` fixture 和可跑切片（§4.1），但都不是签核尺寸；ics55 仍未绑定。驱动管宽/指条、ESD 面积、保护环间距仍要负载/ESD 仿真。
2. **`PAD_OE_CTRL` 与 `PDRV_STAGES`**：OE 逻辑已生成为晶体管级 IO 门（INV/NAND/NOR + 可选 core→IO level shifter），预驱动展开成 2 级非反相链；尺寸共用预驱动占位参数，尚未优化；OE_N/PU_OK 仍假定 IO 域。
3. **原理图复核**：二极管极性、体端接法、三端电阻第三端、guard ring 规则。
4. **绑定 device map**：gf180mcuD / sky130 / IHP 已绑定并生成拓扑；ics55 还差 3.3 V ESD 二极管 SPICE 卡，不能用 2.5 V 卡替代。
5. **SDR 模板表征链**：三套 PDK 的预驱动+输出级/接收器切片和 ESD 反向泄漏已可跑（§4.1）；`char_tb.spice` 仍是完整测量清单，ESD 应力/资格、VREF 共模/失调、SSO、PVT/min-max SPICE、PEX、IBIS、SI/PI、DRC/LVS 都还没做。ESD 的 TLP/HBM/latch-up 计划见 `docs/ESD_STRESS_PLAN.md`。
6. **参数语义**：`L_R_SERIES` 现在是片上电阻长度；目标阻值属于板级 SI，不在 pad 参数里。把目标阻值换算成长度仍需要每套 PDK 的 sheet resistance。DDR1 的 Xyce 导出器在发射器件时执行微米到米换算；此处待解决的是 SDR 模板的参数守卫。
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
