# Foundry / 封装厂数据检索与填充

状态：**检索到 GF180MCU 官方设计手册（DRM）的 EM、bond pad、latch-up、ESD 数据；其中 2 项语义一致、已按 `foundry_doc` 等级填入，6 项仍 TBD。**
`drc_clean` 仍 `false`，能力报告仍全部 `NO_GO`。

## 1. 来源与许可

| 项 | 值 |
|---|---|
| 来源 | GlobalFoundries GF180MCU PDK Design Rule Manual，`gf180mcu-pdk.readthedocs.io` |
| 文档状态 | **Experimental Preview / work in progress**（站点首页自述） |
| 许可 | PDK 本体 Apache-2.0（Copyright 2022 GlobalFoundries PDK Authors）；本仓库只记录数值+出处+逐字片段，不复制正文 |
| 检索日期 | 2026-11-16 |
| 证据等级 | `foundry_doc`（web 来源，不能像本机 PDK 文件那样离线复核） |

检索到的章节：

| 章节 | 内容 |
|---|---|
| DRM 14.2 Table 14.3/14.4 | 金属/通孔最大线电流密度（mA/um、mA/contact），T0.1 > 100K hours @ 85°C |
| DRM 9.0 / 9.2 | Bond pad 总则与 PAD.1–PAD.21 几何 |
| DRM 14.3.2 | I/O latch-up IO.0–IO.4 规则 |
| DRM 14.4.2 / 14.5.2 | 3.3V LV ESD 二极管几何与 TLP 表征（It2、Vt2） |
| DRM 14.4 | ESD 总则（明确警告 TLP→HBM 失配） |

完整数值、逐字片段、URL 与 caveats 在 `specs/pads/foundry_data.yaml`，机器可读报告在 `reports/foundry_data.{json,md}`。生成器 `extract_foundry_data.py` 校验每条 `fill` 项必须有数值、URL、章节、逐字片段和 caveats。

## 2. 逐条判定（8 个原 TBD 项）

| 规则 | 语义 | 决定 | 值 | 依据 |
|---|---|---|---|---|
| `METAL_JMAX` | exact | **填** | 0.00067 A/um（0.67 mA/um） | 14.2 Table 14.3，M1–TM-1 单向 125°C |
| `GUARD_RING_RULE_MIN` | exact | **填** | 2 um | 14.3.2 IO.2/IO.4 最小保护环宽 |
| `PAD_OPENING` | exact | 不填 | 40（仅记录） | 9.2 PAD.1，但明确 VARIABLE / 封装厂定 |
| `PAD_PITCH` | none | 不填 | 无 | 9.0 明确"pitch 由封装厂限定"，未给中心距 |
| `ESD_AREA_MIN` | derived | 不填 | It2 ~27.5 mA/um（仅记录） | 14.5.2；需 HBM 目标才能换算成面积 |
| `IO_CURRENT` | none | 不填 | 设计规格 | SSTL-2 Class I 7.6mA |
| `DQ_BIT_SKEW_MAX` | none | 不填 | 设计规格 | P0-1 时序预算 |
| `RAIL_WIDTH` | derived | 不填 | 依赖 IO_CURRENT | `RAIL_WIDTH_FROM_EM = IO_CURRENT / METAL_JMAX` 现在可算，但 IO_CURRENT 仍 TBD |

### 为什么只填 2 项

1. **`METAL_JMAX`**：14.2 表给的是"每绘制宽度最大电流密度"，单位 A/um 与参数完全一致。选最保守列（M1–TopMetal-1、单向、125°C = 0.67 mA/um）。注意这是**层/温度/方向相关**的：MetalTop 11kÅ 单向 125°C 是 1.5 mA/um、30kÅ 是 5.37 mA/um，双向更高。若电源轨走 MetalTop 需重新选列，已在 caveats 记录。
2. **`GUARD_RING_RULE_MIN`**：之前判 `related_rule_only` 是因为本机 `guard_ring.rb` 的 GR.* 是 seal-ring 到 die 边的距离；现在 14.3.2 的 IO.2/IO.4 才是真正的 **I/O latch-up 保护环宽度**规则（2um，Comment 列标 Rule），语义对齐。措辞是"minimum recommended"，已标注。
3. **`PAD_OPENING` 不填**：40um 是 DRC 默认值，9.2 注释原文说"default numbers for DRC purpose only ... VARIABLE ... acceptable to their assembly house"，且 gold bump 是 4 不是 40。把它冻成约束会假装已经和封装厂确认过。
4. **`PAD_PITCH` 不填**：9.0 明确"Bond pad size and pitch are limited by assembly house"，**全手册没有中心距数值**。PAD.2=9 是开窗边到边间距、PAD.20=5 是 pad metal 间距，都不是 pitch。推 40+9=49um 属于未标注的推断，不做。
5. **`ESD_AREA_MIN` 不填**：It2 是 mA/**um**（单位宽度的 TLP 二次击穿电流），不是面积。换算成二极管面积需要 HBM/MM 目标等级（如 2kV→峰值电流），DRM 未给；14.4 还明确警告 TLP 与 HBM 存在失配（dV/dt、HBM 衰减期器件关断）。It2、DL=0.36um、DW=40um 已记录为将来换算的输入。

## 3. 关键诚实边界（必须保留）

- **文档是 Experimental Preview**：这些是 DRC 默认值，不是已签核的 foundry 承诺。
- **封装厂数据仍然缺**：pad size/pitch 由 assembly house 限定，需要 bond diagram、封装 pad pitch、CUP 与否。本轮"寻找 foundry/封装厂数据"的净结果是——**foundry DRM 找到了，但真正的封装厂特定数据没有**；PAD_PITCH/PAD_OPENING 仍 TBD 正是这个原因。
- **后续专项检索**（`docs/BONDING_DIAGRAM_SEARCH.md`）：公开 bonding diagram / padframe 资料确实存在（wafer.space COB 仓库、模板 slot_1x1.yaml、DRM 9.2、Chipathon padring），但**没有任何来源给出 center-to-center pad pitch 数值**；推导的 ~190/220um 是平均间隔不是 pitch，不填。
- **web 来源不可离线复核**：与 `verified`（本机 `metal.rb:72` 实时核对）不同，`foundry_doc` 是较弱的证据等级，已用不同 status 区分。
- **ESD 目标仍缺**：HBM kV 是系统需求，TLP→HBM 相关性未验证。

## 4. 连锁影响

- `pdk_rules`：10 项 = 2 `verified` + 2 `foundry_doc` + 6 `TBD`。
- 求解器未解输入 41→**37**（31 设计参数 + 6 TBD 规则）；11 条复合约束状态不变（9 unresolved + 2 structural）；`mode=symbolic`、`drc_clean=false` 不变。
- 三个校验器升级为按 status 分类校验 provenance：`verified` 要 `verified_from`、`foundry_doc` 要 `foundry_from`、`TBD` 必须 value=null；未知 status 报错。
- `pdk_rule_evidence.yaml` 里 METAL_JMAX/GUARD_RING_RULE_MIN 改成 `verdict: foundry_doc, decision: defer_local`，指向 foundry_data.yaml，避免两个证据目录矛盾。
- 能力报告仍全部 `NO_GO`；`backends/gf180mcu.yaml` 的 `toe_on_ps/toe_off_ps` 仍 `null`；`topology.yaml` 的 31 个设计参数仍全 `null`。

## 5. 剩下 6 项要闭合还差什么

| 规则 | 需要的输入 |
|---|---|
| `PAD_PITCH` / `PAD_OPENING` | **封装厂 / assembly house**：bond diagram、封装 pad pitch、wire-bond 类型（wedge/ball/gold bump）、是否 CUP |
| `ESD_AREA_MIN` | 系统 ESD 目标（HBM kV）+ It2→面积的换算 + TLP/HBM 相关性验证 |
| `IO_CURRENT` | 设计规格决策 |
| `DQ_BIT_SKEW_MAX` | 系统时序预算 / 板级 SI |
| `RAIL_WIDTH` | `IO_CURRENT` 定下后由 EM 规则算出 |

## 6. 不这样做

- 不把 Experimental Preview 的 DRC 默认值说成 foundry 签核承诺或封装厂确认。
- 不把 It2（mA/um）当成 ESD 面积，不把 PAD.2 边到边间距当成 pitch。
- 不因为填了 4 项就改 `NO_GO` 或解锁 31 个设计参数。
- 不把 web 来源伪装成 `verified`（本机实时核对）。
- 不复制 DRM 正文进仓库；只留数值、URL、章节、逐字片段。
