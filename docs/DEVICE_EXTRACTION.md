# 闭环 ngspice 器件参数提取器

状态：**三套 PDK（gf180mcuD / ihp-sg13g2 / sky130）全部实测；无 mock 值、无签核声明。**
`pdk_rules` 的 10 项仍全部 `TBD`，能力报告仍全部 `NO_GO`。

## 1. 为什么重写而不是照搬粘贴的脚本

上一轮核对发现粘贴的两份脚本在本机跑不起来，且"实测结果"来自硬编码：

| 问题 | 本机实测结论 |
|---|---|
| `ngspice_sstl2_verifier.py` 的 `print(f"[{pdk.name.upper()]...")` | **SyntaxError**（`unmatched ']'`），脚本根本不能运行；所谓 TT/SS/FF 眼高 890.4/745.2/962.8 mV 全部来自 `_mock_corner_results` 常量 |
| 眼宽 / 建立 / 保持裕量 | `0.72*UI` / `0.35*UI` / `0.33*UI` 常量，眼高还有 `max(250.0, ...)` 下限钳位，不是测量 |
| `run_deck()` 用 `TemporaryDirectory()` 但 `.lib` 是相对路径 | 实测 A 组直接失败（找不到模型文件）；gf180 还需 `PDK_ROOT`，IHP 需 OSDI 预加载 |
| `M... nfet_03v3` | gf180 的 `nfet_03v3` 是 `.subckt`（`sm141064.ngspice:46922`），必须用 `X` 前缀；`M` 报找不到模型 |
| `DEFAULT_BSIM4_CARD` 自述 "GF180MCU-like" 演示卡 | `k'_eff=160/105 µA/V²`、`Vth_SS=0.73/0.78` 均无来源；算术对但输入是编的 |
| 全局 `~/.spiceinit`（IHP 的 OSDI 配置）污染所有 PDK | 本机 `~/.spiceinit` 会让 gf180/sky130 报 `cap_cmomf.osdi` 不存在；必须在工作目录放本地 `.spiceinit`，或给 sky130 传 `-n` |

因此本提取器：**不解析 `.model` 文本、不设 mock 回退、每个数值绑定一个哈希过的 ngspice deck、跑不通就如实 BLOCKED 并附真实错误**。

## 2. 架构

```text
specs/pads/device_backends.yaml   每 PDK 只写"接线"：实例前缀、尺寸后缀、
                                 finger 参数、库文件、角名、OSDI、环境变量
        |
        v  generator/extract_devices.py
ngspice -b（工作目录放本地 .spiceinit；绝对路径 .lib）
  - .op  线性区 Id / R_on        （TT 27C / SS 125C / FF -40C）
  - .dc  饱和区 Vth(恒流) / gm/Id / Vgs@40uA
  - .ac  100MHz Cgg / Cgd
  - 闭环多指校准：SS 角复测完整 finger 数直到 Id >= 7.6 mA
        |
        +--> reports/device_extraction.json / .md
        +--> specs/pads/constraints.yaml 的 device_measurements 段
        |
        v  generator/check_device_extraction.py
```

复现：`python3 generator/extract_devices.py`，校验：`python3 generator/check_device_extraction.py`。

**PDK 适配要点（本机实测）**：

| PDK | 模型 | 实例 | 尺寸 | finger 语义 |
|---|---|---|---|---|
| gf180mcuD | BSIM4 分档 `.subckt` | `X` | `w=5u l=0.28u m=N`（`u` 后缀） | `w` 是**单指宽**，`m` 才是乘数 |
| ihp-sg13g2 | PSP 103.6 / OSDI | `X` | `w=<W>u l=0.45u ng=N m=1` | `w` 是**总宽**，`ng` 只切分；放大必须加 `w` |
| sky130 | BSIM4 分档 | `X` | `W=5 L=0.5 nf=1 m=N`（**无 `u`**，因 `.option scale=1.0u`；`m` 乘数） | `W` 是总宽且受 `wmax=100µm` 限制；`nf` 只切分；放大靠 `m` |

`w`/`ng` 语义是实测定的：IHP `w=5u` 时 `ng` 1→8，Id 0.846→0.788 mA（几乎不变）；`w=40u ng=8` 才到 6.77 mA。第一版把两者写反，导致校准 finger 数指数爆炸到 1.2 亿——已修。

## 3. 实测结果（ngspice-44.2，2026-11-15）

| PDK | 器件 | 恒流 Vth | Vgs@40µA | R_on 单位值 | Cgg/µm | Class I 校准 |
|---|---|---|---|---|---|---|
| gf180mcuD | NMOS | 0.66 V | 0.86 V | 2456 Ω·µm | 1.881 fF | M=16 → 8.37 mA |
| gf180mcuD | PMOS | **0.82 V** | 1.00 V | 7053 Ω·µm | 1.976 fF | M=40 → 7.72 mA |
| ihp-sg13g2 | NMOS | 0.62 V | 0.86 V | 2246 Ω·µm | 2.573 fF | M=14 → 7.94 mA |
| ihp-sg13g2 | PMOS | 0.66 V | 0.90 V | 7223 Ω·µm | 2.229 fF | M=42 → 7.89 mA |
| sky130 | NMOS | 0.78 V | 1.04 V | 3537 Ω·µm | 2.157 fF | M=24 → 8.27 mA |
| sky130 | PMOS | **1.02 V** | 1.24 V | 12037 Ω·µm | 1.743 fF | M=66 → 7.74 mA |

TT/SS/FF 三档 Id 满足 SS ≤ TT ≤ FF（gf180 NMOS：1.046 / 1.547 / 2.117；sky130 NMOS：0.689 / 1.058 / 1.486 mA），校验器会检查这个顺序。

### sky130 闭合过程（本轮完成）

最初报 `BLOCKED`，原因是 **`discover()` 用字典序挑了残缺的 ciel 版本**：本机有两个版本，
`8afc...` 只有 `libs.tech`、缺 `libs.ref/sky130_fd_pr/spice/`；`792e...` 才有全部 675 个 primitive spice 模型。
`sorted(glob)[-1]` 恰好选中了 `8afc...`（字典序更大）。改为 `root_must_contain` 校验后选中 `792e...`，include 链立即通了。

第二个坑是 **BSIM4 bin 的 `wmax = 1.0e-4 m`（100µm）**。sky130 子电路里 `w` 是**总宽**、`nf` 只切分，
而第一版把 sky130 当成 `W` 随 finger 线性放大的 `total_scaled`：`W=110µm, nf=22` 时 ngspice 报
`could not find a valid modelname`。实测确认正确的放大方式：

| 组合 | Id (TT, mA) | 结论 |
|---|---|---|
| `m`=4 / 8 / 16（W=5, nf=1） | 2.12 / 4.23 / 8.47 | **线性放大，正确** |
| `nf`=1 / 8 / 16 / 22（W=5） | 0.529 / 0.408 / 0.194 / bin 越界 | `nf` 只切分 W，反而减小电流 |
| `W=90, nf=1` | 9.48 | 在 `wmax` 内合法 |

故 sky130 改用 `per_finger_fixed` + `m` 乘数 + 固定 `W=5 nf=1`（与 gf180 同构）。
另需 `cwd` = `<PDK>/libs.tech/ngspice`（相对 include 链只在此解析）与 `-n`（跳过全局 `~/.spiceinit`）。

### 与粘贴材料假设的实质差异

1. **gf180 PMOS Vth**：实测恒流值 0.82 V，粘贴材料假设 0.68 V。ICMR 代理判据（VDDQ_min=2.3、VREF=1.25、headroom≥0.12）下 gf180 的 PMOS 尾电流管裕量只有 0.05 V → 自动切到 `NMOS_ONLY_DIFF_PAIR`；而粘贴材料称 gf180 互补轨到轨差分对成立。IHP 实测裕量 0.15 V → `COMPLEMENTARY_RAIL_TO_RAIL`。
   **但这只是代理判据**（用实测 Vgs@40µA 估的，不是完整堆叠尾电流源仿真），报告里明确标注 `headroom proxy`，不能据此给拓扑签核结论。它的价值是暴露"假设的 Vth 与真实 PDK 差 0.14 V 就足以翻转结论"。
2. **Class I 尺寸**：实测闭环校准得到 gf180 Wn≈80µm / Wp≈200µm（M=16/40），比粘贴材料的 40µm/100µm 大一倍 —— 因为校准在 SS/125°C 最坏角按实测电流迭代，而非用 typ 的 k' 解析式。
3. **VREF 共模**：恒流 Vth 与 BSIM `VTH0` 不是同一个定义（前者含短沟道/迁移率退化），跨材料比较 Vth 数值时要先对齐定义。

## 4. 为什么 `pdk_rules` 仍是 10 个 TBD

用户选项里提到"把实测参数填进 `constraints.yaml` 的 `pdk_rules`"。**没有这么做**，理由要写清：

`pdk_rules` 是 **版图/可靠性规则输入** —— `PAD_PITCH`、`PAD_OPENING`、`DRC_MIN_SPACING/WIDTH`、`ESD_AREA_MIN`、`METAL_JMAX`、`GUARD_RING_RULE_MIN`、`DQ_BIT_SKEW_MAX`、`RAIL_WIDTH`。单管 DC/AC 探测测的是 **器件特性**（Vth、R_on、gm/Id、Cgg/Cgd），**测不出** DRC 间距、ESD 目标、金属电流密度、焊盘节距。把器件电流当成 DRC 规则填进去，是另一类造假。

因此生成器只新增 `device_measurements` 段（实测值 + `source: ngspice`），并附 `rule_fill_map` 逐条说明每个 `pdk_rules` 项该由什么输入填：

- `IO_CURRENT`：可由 triode Id 辅助，但目标值是设计规格，仍 TBD
- `DQ_BIT_SKEW_MAX`：需时序预算
- `RAIL_WIDTH` / `METAL_JMAX`：需 PDK 金属 EM 规则
- `ESD_AREA_MIN` / `GUARD_RING_RULE_MIN`：需 ESD/latch-up deck
- `PAD_PITCH` / `PAD_OPENING` / `DRC_MIN_*`：需 DRC deck 与封装约束

`check_device_extraction.py` 会强制这 10 项保持 `TBD`/`null`，防止将来误填。

## 5. 本项目约束的一致性

- `specs/pads/topology.yaml` 的 31 个设计参数**仍全为 `null`** —— 本提取器测的是器件，不是选定尺寸；`emit_pads.py` 的守卫不变。
- `reports/capability_report.md` **仍全部 `NO_GO`**，`backends/gf180mcu.yaml` 的 `toe_on_ps/toe_off_ps` 仍 `null`、`schematic_drawn: false`。器件表征不等于 pad 已设计/已签核。
- gf180mcu DDR1 仍是 `DEFERRED_LONG_TERM`（P4+，远期计划）。本提取器是 P0 的器件表征能力建设，不代表 SSTL-2 收发器已实现。
- `check_layout.py` 的 41 未解输入、11 条复合约束、0 个 DRC 声明保持不变。
- 没有引入任何外部模型源码；PDK 库通过绝对路径 include，模型本身留在 ciel。

## 6. 尚未做的

1. 读 gf180mcuD 的 DRC/LVS、ESD、latch-up、金属 EM 规则填 `pdk_rules`。
2. ~~安装完整 sky130 primitive 模型~~ 已闭合：`792e...` 版本含完整模型；`root_must_contain` 保证不再误选残缺版本，`check_device_extraction.py` 现在要求 3 套全部 MEASURED。
3. 用实测 R_on / Cgg / gm/Id 反推 31 个设计参数，跑 `char_tb.spice` 的测量清单。
4. 完整堆叠尾电流源仿真验证 ICMR 拓扑（替代代理判据）。
5. PVT min/max 配对、PEX/SPICE、IBIS、SI/PI、DRC/LVS、pad ring 集成。

## 7. 不这样做

- 不用 mock / LUT / 演示模型卡冒充实测，不因为跑不通就补一个"合理"的数。
- 不把 `M` 前缀用在 `.subckt` 器件上，不把 `u` 后缀用在 sky130 的 `scale=1.0u` 上。
- 不把恒流 Vth 与 BSIM `VTH0` 混为一谈，不把 ICMR 代理判据说成拓扑结论。
- 不把器件测量填进 `pdk_rules`，不把"提取器跑通"说成 `NO_GO` 解除。
- 不把 BLOCKED 说成"已验证"或"不支持"；本轮已用真实 PDK 版本闭合 sky130，并保留 bin 限制这个真发现。
