# 公开 bonding diagram / pad pitch 数据检索

状态：**检索到大量公开的 padframe / wirebonding 资料；通用 pad pitch 仍无公开数值，但一个具体封装承诺已用其 golden mask GDS 实测闭合（见 `docs/PACKAGING_PROFILES.md`）。**
`PAD_PITCH` / `PAD_OPENING` 在通用 `pdk_rules` 中仍保持 `TBD`，profile 只做内存态 overlay。`drc_clean` 仍 `false`，能力报告仍 `NO_GO`。

## 1. 检索范围与许可

| 来源 | 类型 | 许可 |
|---|---|---|
| GF180MCU DRM 9.0 / 9.2 | foundry 设计手册 | PDK Apache-2.0 |
| `gf180mcu_fd_io/features.html` (2.0 Library Features) | IO 库几何 | PDK Apache-2.0 |
| wafer.space slot specs / `slots.json` | MPW 服务商 die/slot 规格 | 公开 |
| `wafer-space/gf180mcu-project-template` `librelane/slots/slot_1x1.yaml` | 实际 pad 坐标配置 | Apache-2.0 |
| `wafer-space/chip-on-board-wire-bonded-pcbs` | COB / wirebonding 布局 | Apache-2.0 |
| IEEE SSCS Chipathon 2025 Integration docs | 学术 padring 实例 | 公开 |
| `wafer-space/gf180mcu-precheck` | COB pad opening 检查 | Apache-2.0 |

本仓库只记录数值、URL、章节与逐字片段，不复制正文/图纸。web 来源不能离线复核，证据等级与 `verified`（本机 PDK 文件实时核对）分开。

## 2. 找到的公开数据（都是真实的）

### 2.1 IO cell 与 bond pad 几何（`features.html`）
- IO cell 宽 **75µm** × 高 **350µm**（高度含 bond pad），角 cell 355×355µm
- **bond pad opening 60×60µm**
- 设计网格 0.005µm；top metal 6kÅ / 9kÅ；3LM/4LM/5LM 选项；bond pad **non-CUP**（3LM 限制）
- `bi_t` 双向 pad 驱动强度 4/8/12/16mA（来自 Chipathon 文档）

### 2.2 DRM 9.2 / 9.0
- PAD.1 开窗 **40**（wedge/ball）、gold bump 4；PAD.2 开窗到开窗 **9**；PAD.20 pad metal 到 pad metal **5**；PAD.15 开窗到 seal ring 最小 **30**、PAD.16 最大 **200**
- 9.0 原文：**"Bond pad size and pitch are limited by assembly house"**；9.2 注释：这些是 "default numbers for DRC purpose only ... VARIABLE ... acceptable to their assembly house"

### 2.3 wafer.space slot 规格
- 1×1 die **3932×5122µm**，usable 3880×5070，seal ring ~26µm/边，core area 12.92mm²
- 默认 **56 IO + 18 power = 74 pads**；半槽 72；quarter 48 IO + 8 power = 56
- COB 选项**必须使用默认 pad ring**（pad 位置固定）；模板 README 明确"不要改变 pad 数量以保持 bondpad 位置"

### 2.4 实际 pad 坐标（`slot_1x1.yaml`）
- `DIE_AREA: [0, 0, 3932, 5122]`，`CORE_AREA: [442, 442, 3490, 4680]`
- PAD_SOUTH/NORTH 各 17、PAD_EAST/WEST 各 20，合计 **74**，按名称固定顺序排列
- 这是**有约束力的 pad 位置约定**（COB 兼容性），但 yaml 里是实例名列表，**没有坐标数字也没有 pitch 变量**

### 2.5 COB / wirebonding 布局（`chip-on-board-wire-bonded-pcbs`）
- 74-pad Tiny Tapeout 约定 padframe；PCB 14×16mm；70-pin 0.4mm-pitch mezzanine 连接器
- wirebond 规则：**不允许交叉线、线角 ≤45°、最大线长 <3mm、最小线长 1mm 或 2×die 厚度（取大）、bonding 区无阻焊**
- 提供 KiCad 符号 / PCB / pinout 表与 GDS↔KiCad 逐 pin 匹配脚本 —— **这就是最接近 "bonding diagram" 的公开资料**（图片 + pinout + KiCad 布局）
- Run 1 说明："pinouts / connector / footprint 是 **run-specific**，会随批次变化"

### 2.6 学术 padring 实例
- IEEE SSCS Chipathon 2025：可用设计区 2040×2040µm，**88 pins（每边 22）**，QFN-88 封装参考
- 明确"没有 3.3V IO pad，只能用 5V IO pad 跑 3.3V（影响速度）"

## 3. 关键结论：pad pitch **没有公开数值**

逐份核对后，**没有任何来源给出 center-to-center pad pitch（µm）**：

1. DRM 9.0 把 pitch **明确推给封装厂**（"limited by assembly house"），PAD.2=9 / PAD.20=5 都是**边到边**间距，不是中心距。
2. wafer.space 把 74 个 pad **钉在固定坐标**以兼容 COB，但公开文档只给实例名列表、die 尺寸和 pad 数量，**不给 pitch 数字**。真实 pitch 存在于它们的 GDS/PCB 里，需要拉取实际版图测量。
3. 可从公开数字**推导**平均值：1×1 die 3932µm 减 2×355µm 角、17 pads → ~189.5µm 间隔；5122µm 减角、20 pads → ~220.6µm。但这是**推导的平均间隔**，依赖角/填充 cell 假设，**不是 stated pitch**。后续从 `wafer-space/gf180mcu-precheck` 的 `mask_1x1.gds`（sha256 可复核）直接量到：东西边 20 pads、19 个间隔均为 **211µm**；南北边 17 pads、16 个间隔均为 **180µm**；开窗 **60×60µm**。这些值只写进 `wafer_space_gf180_1x1` profile（`assembly_measured`），通用 `pdk_rules` 仍不填。
4. 两个"开窗"数值并存且语义不同：DRM PAD.1=40 vs IO 库 60×60µm。没有封装厂确认能对账，**不填**。

因此本轮的净结论是：**公开 bonding diagram / padframe 资料确实存在且相当丰富（wafer.space 的 COB 仓库几乎是完整的一套），但"中心距 pad pitch"这个具体数值仍然只有封装厂/实际 GDS 才能给**——正好印证了 DRM 的说法，也符合本项目一贯不把推断值伪装成实测值的纪律。

## 4. 对本项目的影响

- `PAD_PITCH`、`PAD_OPENING` 在通用 `pdk_rules` 中继续 `TBD`；实测值只存在于 `wafer_space_gf180_1x1` profile 的 `overrides`（`assembly_measured`）。6 项 TBD 不变；4 项已填（2 `verified` + 2 `foundry_doc`）不变；未解输入仍 37；`drc_clean=false`、`NO_GO` 不变。
- 上一轮写的"具体可执行的下一步"（拉 golden GDS 量中心距）已在 `wafer_space_gf180_1x1` 上完成：量到 211µm / 180µm / 60µm 开窗，并跑出 profile closure。通用规则仍需另一个封装承诺才能闭合。

## 5. 不这样做

- 不把推导的 ~189.5/~220.6µm 或 40+9=49µm 说成 pad pitch。
- 不把 PAD.2/PAD.20 的边到边间距当成中心距。
- 不把 wafer.space 某一 run 的 COB 约定当成所有封装的通用 pitch（其文档自述 run-specific）。
- 不因为找到了 bonding diagram 类资料就改 `NO_GO` 或解锁设计参数。
- 不复制 wafer.space / DRM 的图纸、KiCad 文件或正文进仓库。
