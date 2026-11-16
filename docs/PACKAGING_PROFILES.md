# 可插拔 Packaging Profile 与第一组闭环

状态：**以 wafer.space GF180MCU 1×1 COB 封装承诺打通了第一组闭环；架构是 PDK 无关的 IP generator，profile 是可插拔 overlay。**
`drc_clean` 仍 `false`，能力报告仍全部 `NO_GO`。

## 1. 为什么不把封装值写进 `pdk_rules`

用户要求"按 wafer.space 的封装承诺打通第一组闭环，但不要把架构局限在 gf180mcu，仍优先考虑 IP generator"。据此：

- **`pdk_rules` 的 `PAD_PITCH` / `PAD_OPENING` 仍保持 `TBD`**。一个 MPW run 的封装承诺不是通用规则（wafer.space 自述 pinout/footprint 是 run-specific）。`check_packaging.py` 强制这一点。
- 引入 **packaging profile 层**：`specs/pads/packaging_profiles/*.yaml`。profile 提供装配相关的几何覆盖、设计假设与证据出处。
- 求解器 `solve_packaged.py` **不含任何 gf180/wafer.space 硬编码**：backend 从 `meta.applies_to_backend` 读，覆盖值从 `overrides` 读，证据等级从 `meta.evidence_class` 读。**新增 sky130 / ihp130 / ics55 或另一个封装 = 新增一个 yaml，零代码改动**。
- 覆盖是**内存态**的：不写回 `constraints.yaml`，输出落在独立目录 `layout/profiles/<profile_id>/`，不污染默认 symbolic 产物。

## 2. 第一组 profile 的可核实数据来源

之前的结论是"公开资料没有显式 pad pitch"。本轮进一步找到 **wafer.space precheck 的 golden mask GDS**（Apache-2.0），直接量出真实坐标：

| 项 | 值 | 来源 |
|---|---|---|
| golden mask | `mask_1x1.gds`，sha256 `77bbb647…8666` | `wafer-space/gf180mcu-precheck/assets/golden_masks/` |
| pad opening | **60×60µm**，共 74 个 | KLayout `pya` 读出（dbu=0.001） |
| 东西边 pitch | **211µm**（各 20 pads，19 个间隔全是 211.0） | 同上 |
| 南北边 pitch | **180µm**（各 17 pads，16 个间隔全是 180.0） | 同上 |
| `PAD_PITCH` 覆盖值 | 180µm（取保守的南北边） | profile `overrides` |
| `PAD_OPENING` 覆盖值 | 60µm | profile `overrides` |

证据等级 **`assembly_measured`**：数值来自出版方金标准 GDS 的直接测量，比 `foundry_doc`（读文字页）更强，且 sha256 可复核。原生坐标、pad 数、die 尺寸、COB wirebond 规则、IO cell 75µm 宽都记在 profile 的 `sources` / `geometry` 里。

注意 DRM 9.2 的 PAD.1=40 与 IO 库 60×60µm 不一致 —— golden mask 实测是 60，故以实测为准并保留两者差异的说明。

## 3. 第一组闭环结果

### 3.1 只用封装 profile（无设计夹具）
`python3 generator/solve_packaged.py --profile wafer_space_gf180_1x1`

- 41 输入中 33 未解，mode `symbolic`；11 条约束 = 8 unresolved + **1 satisfied** + 2 structural。
- 闭合的是 `pad_pitch_drc`：`PAD_PITCH=180µm`（assembly_measured）≥ `DRC_MIN_SPACING=0.23µm`（本机 PDK verified）——**两个操作数都是已核实真实值**。
- 其余约束的 LHS 依赖 31 个仍 TBD 的设计参数，诚实保持 unresolved。这正是"部分闭环"，没有假装修好。

### 3.2 加显式标注的合成设计夹具（完整链演示）
`--design-fixture wafer_space_gf180_1x1.fixture.yaml`（`meta.status: synthetic_fixture`，明确"非设计值、仅用于跑通方法学"）

- 41/41 输入解析，mode `dimensional`；11 条约束全部求值 = **7 satisfied / 2 violated / 2 structural**。
- 两条 violated 证明检测器有效，且物理合理：
  - `cell_width_fits_pitch`：CELL_WIDTH=2374µm ≫ pitch 180µm（fixture 的驱动管尺寸累加远超一个 pad 位）。
  - `rail_em`：RAIL_WIDTH=12µm < `IO_CURRENT/METAL_JMAX` = 0.0152/0.00067 = 22.7µm。
- **fixture 是 synthetic、明确标注、不进 `emit_pads.py`、不作签核**；它证明的是"整条 41→11 的链能算且能抓冲突"，不是给出了可流片尺寸。

## 4. 闭环的诚实边界

- 封装承诺只提供**装配几何**。器件尺寸（31 设计参数）、ESD HBM 目标、rail/EM 决策是独立 gate，**选了封装并不闭合它们**。`ESD_AREA_MIN` / `RAIL_WIDTH` 在 profile 里故意不提供。
- 每个约束在报告里标注了操作数的**证据来源**（`profile_override / verified / foundry_doc / design_assumption / TBD`），避免把合成值混作实测。
- `pdk_rules` 通用值不变：2 verified + 2 foundry_doc + 6 TBD。能力报告仍 `NO_GO`，`backends/gf180mcu.yaml` 的 `toe_on_ps/toe_off_ps` 仍 `null`、`schematic_drawn: false`。
- 未做 PEX/SPICE、IBIS/SI-PI、DRC/LVS、ESD 资格、PVT。

## 5. 可插拔性（IP generator 视角）

```text
specs/pads/
  topology.yaml                 一张共享 pad 拓扑（PDK 无关）
  constraints.yaml              通用复合约束（pdk_rules 保持 TBD 的规则/设计输入）
  device_backends.yaml          器件模型接线（3 套 PDK 实测）
  foundry_data.yaml            foundry DRM 证据
  packaging_profiles/           <-- 本轮新增：装配 overlay
    wafer_space_gf180_1x1.yaml            第一个 profile
    wafer_space_gf180_1x1.fixture.yaml   合成演示夹具
    <sky130_xxx.yaml / ihp130_xxx.yaml>  将来加文件即可，无代码改动
generator/
  solve_layout.py               通用复合约束求解（默认 symbolic）
  solve_packaged.py              PDK 无关的 profile overlay 求解 <-- 本轮新增
  check_packaging.py            profile/fixture/产物校验 <-- 本轮新增
  emit_pads.py / extract_*.py   既有生成器
```

新增封装或工艺的步骤：写一个 profile yaml（引用该封装的金标准 GDS/坐标 + 证据），其余生成器、校验器、求解器不用改。`applies_to_backend` 是列表，一个封装可服务多套 PDK；backend 名称不出现在求解逻辑里。

## 6. 复现与验证

```sh
python3 generator/solve_packaged.py --check-profiles
python3 generator/check_packaging.py
python3 generator/solve_packaged.py --profile wafer_space_gf180_1x1
python3 generator/solve_packaged.py --profile wafer_space_gf180_1x1 \
    --design-fixture specs/pads/packaging_profiles/wafer_space_gf180_1x1.fixture.yaml
sh sim/packaged.sh
```

产物：`reports/packaged_layout_wafer_space_gf180_1x1.md`、`sch/pads/gf180mcuD/layout/profiles/wafer_space_gf180_1x1/`（closure_constraints.json / placement.json / closure_report.md / constraint_graph.dot / GDS）。

## 7. 不这样做

- 不把一个 MPW run 的 pitch 写成通用 `pdk_rules` 值；不因选了封装就改 `NO_GO`。
- 不把 synthetic fixture 说成设计值或签核结果；不隐藏 2 条 violated。
- 不把推导的 ~189.5/220.6µm 平均间隔当成 pitch（实测是 180 / 211）。
- 不在求解器里硬编码 gf180 / wafer.space / 任何 PDK 名。
- 不复制 wafer.space 的 GDS/PCB/图纸进本仓库；只留 sha256、URL 与测量结果。
