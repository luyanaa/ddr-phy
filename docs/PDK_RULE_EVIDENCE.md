# gf180mcuD PDK 规则证据与 pdk_rules 填充

状态：**10 项 pdk_rules 里 4 项已填（2 由本机 PDK 文件 + 2 由 foundry DRM），6 项保持 TBD。见 `docs/FOUNDRY_PACKAGE_DATA.md`。**
填入的是 **DRC 规则限值**，不是"跑过 DRC 且 clean"：`drc_clean` 仍 `false`，能力报告仍全部 `NO_GO`。

## 1. 来源

本机 PDK 版本 `792ef67037d74c8c51811eab3ce23cf793491296`（ciel），ngspice-44.2 无关，本轮读的是规则文件：

| 文件 | 用途 |
|---|---|
| `libs.tech/klayout/tech/drc/rule_decks/metal.rb` | KLayout DRC：各金属层最小宽/距 |
| `libs.tech/magic/gf180mcuD.tech` | magic tech DRC（佐证，单位 0.01µm） |
| `libs.tech/klayout/tech/drc/rule_decks/esd.rb` | ESD implant 层 DRC 规则 |
| `libs.tech/klayout/tech/drc/rule_decks/guard_ring.rb` | seal/guard ring 规则 |
| `libs.ref/gf180mcu_fd_io/lef/*.lef` | IO cell 几何 |
| `libs.ref/gf180mcu_fd_io/mag/Bondpad_5LM.mag` | bondpad 几何（magic 内部单位） |

许可：上述规则文件头部均为 Apache-2.0（GlobalFoundries / SkyWater PDK Authors），与本项目兼容；本仓库**不复制**任何规则文件，只记录出处与读到的数值。

生成器 `generator/extract_pdk_rules.py` 会**实时**打开这些文件、核对每条 `source` 的行号与原文片段；路径或行内容漂移就会报错，不会静默沿用旧值。证据目录在 `specs/pads/pdk_rule_evidence.yaml`，报告在 `reports/pdk_rule_evidence.{json,md}`。

## 2. 逐条判定

| 规则 | 判定 | 决定 | 值 | 依据 |
|---|---|---|---|---|
| `DRC_MIN_SPACING` | verified | **填** | 0.23 µm | `metal.rb:72` `min_space: 0.23`（Metal1）；`gf180mcuD.tech:2963` M1.2a 230 佐证 |
| `DRC_MIN_WIDTH` | verified | **填** | 0.23 µm | `metal.rb:72` `min_width: 0.23`（Metal1）；`gf180mcuD.tech:2962` M1.1 230 佐证 |
| `ESD_AREA_MIN` | related_rule_only | 不填 | — | `esd.rb:75` ESD.5a 0.49µm² 是 **implant 层多边形**最小面积，不是 HBM 二极管面积 |
| `GUARD_RING_RULE_MIN` | foundry_doc | **填** | 2 um | DRM 14.3.2 IO.2/IO.4（见 FOUNDRY_PACKAGE_DATA.md） |
| `PAD_PITCH` | related_rule_only | 不填 | — | `bi_t.lef:9` 75µm 是**单个 IO cell 宽**，不是封装节距 |
| `PAD_OPENING` | related_rule_only | 不填 | — | `guard_ring.rb:109` GR.11 只说"开窗在 GUARD_RING_MK 上"不给尺寸 |
| `METAL_JMAX` | foundry_doc | **填** | 0.00067 A/um | DRM 14.2 Table 14.3（见 FOUNDRY_PACKAGE_DATA.md） |
| `IO_CURRENT` | design_input | 不填 | — | SSTL-2 Class I 7.6mA 是设计规格 |
| `DQ_BIT_SKEW_MAX` | design_input | 不填 | — | 来自 P0-1 时序预算 / 板级 SI |
| `RAIL_WIDTH` | design_input | 不填 | — | EM/IR 设计决策，依赖仍 TBD 的 METAL_JMAX / IO_CURRENT |

### 为什么本机 PDK 只填 2 项（另 2 项由 foundry DRM 填）

关键是**语义一致**，不是"找到一个数就填"：

1. 0.23µm 是 Metal1 最小宽/距，取所有金属层里最小的值作通用下界（M2–M5 为 0.28µm、MetalTop 宽 0.44/距 0.46µm）。它是**层相关**的，已在 `reason` 标注。
2. `ESD_AREA_MIN` 最危险：ESD.5a 的 0.49µm² 是 DRC 对 implant 多边形的下限，而约束 `esd_up_area` 比的是 **ESD 二极管面积**（`ESD_AREA_UP`）。填 0.49 会误示"极小二极管就能过 HBM"，属另一类造假，坚决不填。
3. `GUARD_RING_RULE_MIN` 同理：GR.2 的 10µm 是芯片 seal ring 到核心的距离，与 latch-up 的阱/衬底接触间距是两套物理。
4. 3 项 design_input 本来就不是 PDK 规则，填任何 PDK 数值都是类别错误。

## 3. 连锁影响

填 2 项后 `solve_layout.py` 的未解输入从 41 降到 **37**（31 设计参数 + 6 个 TBD 规则）；11 条复合约束状态不变（9 unresolved + 2 structural），因为 `CELL_WIDTH` / `RAIL_WIDTH_FROM_EM` 等派生量仍依赖未解的设计参数。`drc_clean` 仍 `false`，GDS 仍是 `TOPOLOGY_ONLY` 符号草图。

三个校验器按 status 分类校验 provenance（verified / foundry_doc / TBD）：

- `check_layout.py`：verified 项必须有 `value/status/verified_from` 且与证据目录一致；其余必须 TBD/null；未解计数按实际 null 动态计算。
- `check_device_extraction.py`：同样的 verified/TBD 二分校验。
- `extract_pdk_rules.py --check`：实时核对 source 行与候选文件存在性。

## 4. 能力判定不变

`reports/capability_report.md` 仍全部 `NO_GO`，`backends/gf180mcu.yaml` 的 `toe_on_ps/toe_off_ps` 仍 `null`、`schematic_drawn: false`；`specs/pads/topology.yaml` 的 31 个设计参数仍全为 `null`。读到 DRC 规则限值 ≠ pad 已设计、已画原理图、已通过 DRC/LVS。

gf180mcu DDR1 仍是 `DEFERRED_LONG_TERM`（P4+，远期计划）。

## 5. 剩余 6 项要闭合还差什么

| 规则 | 需要的输入 |
|---|---|
| `PAD_PITCH` / `PAD_OPENING` | 封装/assembly 规则、bondpad 开窗尺寸（需与封装厂确认） |
| `ESD_AREA_MIN` | ESD 目标（HBM/MM 等级）+ 二极管单位面积能力表征 |
| `GUARD_RING_RULE_MIN` | latch-up 规则（tap-to-diffusion 间距，通常在 foundry ESD/latch-up 手册） |
| `METAL_JMAX` / `RAIL_WIDTH` | PDK 金属 EM 电流密度表（开源 PDK 常缺，需 NDA 或保守设计假设并标注） |
| `IO_CURRENT` / `DQ_BIT_SKEW_MAX` | 设计规格与时序预算（不是 PDK 数据） |

## 6. 不这样做

- 不把 DRC 规则限值说成"已通过 DRC"，不因此改 `NO_GO` 判定。
- 不把 implant 层 DRC 面积当成 ESD 二极管面积，不把 seal-ring 距离当成 latch-up 间距。
- 不填任何猜测的 EM 电流密度、封装节距或 ESD 目标。
- 不把 PDK 规则文件复制进仓库；只留出处与实时核对。
- 不因为填了 2 项就把 31 个设计参数或 `drc_clean` 解锁。
