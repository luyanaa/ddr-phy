# 复合约束布局求解器

状态：**求解器框架已建立并跑通；产物是符号化拓扑草图，不是可流片版图。**
31 个设计参数全为 `null`；10 个 PDK 规则输入已填 4 项（2 `verified` + 2 `foundry_doc`）、6 项仍 `TBD`，未解输入 37/41。`drc_clean` 恒为 `false`。

## 1. 用户要求与做法

要求："按尺寸参数生成复合约束的版图"。做法是把"复合"落在**约束依赖图**上，而不是把一堆独立规则并列：一个尺寸参数会同时驱动多个约束类。

```text
topology.yaml (31 设计参数) ─┐
constraints.yaml (10 PDK 规则) ─┼─> 派生量图 (11 个) ─> 复合约束 (11 条 / 7 类)
生成的 SPICE 网表 ────────────┘         │
                                        v
                      layout_constraints.json + placement.json
                                        │
                      constraint_graph.dot + draw_layout.py (KLayout pya)
                                        v
                      sdr_bidir_pad_topology.gds  (TOPOLOGY_ONLY)
```

复现：`python3 generator/solve_layout.py`，校验：`python3 generator/check_layout.py`。

## 2. 复合约束模型

`specs/pads/constraints.yaml` 定义三类输入：

- **设计参数**：来自 `topology.yaml`，31 个全为 `null`（宽/长/指条/级数/电阻/ESD 面积/保护环/尾电流等）。
- **PDK 规则**：10 个，其中 4 个已按证据等级填入（`DRC_MIN_WIDTH` / `DRC_MIN_SPACING` = 0.23µm 为 `verified`，`METAL_JMAX` / `GUARD_RING_RULE_MIN` 为 `foundry_doc`），6 个仍 `null` 且 `status: TBD` —— 焊盘节距、开口、ESD 面积下限、IO 电流、DQ 位间偏斜预算、电源轨宽。**没有编造任何一条 DRC 数值**；填入的是规则限值，不是"DRC 已跑过"。
- **派生量**：11 个，闭白名单运算（`sum/product/scale/sqrt/div/max/min`），**不对文件数据做 eval**。例如 `W_N_TOTAL = W_N_OUT * NF_N_OUT * M_DEVICE`，`CELL_WIDTH = DRIVER_WIDTH + 2*GUARD_RING_SPACING + 2*RAIL_WIDTH`，`RAIL_WIDTH_FROM_EM = IO_CURRENT / METAL_JMAX`。

7 类约束共用这些派生量，所以改一个 `W_N_OUT` 会同时牵动 geometry、drc、matching；改 `GUARD_RING_SPACING` 会同时牵动 geometry 与 latch_up；改 `RAIL_WIDTH` 会同时牵动 geometry 与 power_em。`constraint_graph.dot` 画的就是这张图。

约束状态有四种：`satisfied` / `violated` / `unresolved` / `structural`。默认输入下得到 9 条 `unresolved` + 2 条 `structural`（所有 DQ lane 同构、IO 电源分离），**没有任何 satisfied 声明**，因为一个数值都还没定。

## 3. 求解器

`generator/solve_layout.py`：

1. 读拓扑参数、PDK 规则、器件映射与生成的 SPICE 网表。
2. 按依赖顺序求值 11 个派生量；任一依赖为 `null` 就把该量标 `unresolved` 并**向下传播**。
3. 对 11 条约束求值，并回溯每条约束的上游输入集合（`upstream`）。
4. 判定模式：有未解参数 -> `symbolic`；全部填齐 -> `dimensional`。
5. 从 SPICE 网表解析器件/二极管实例，生成 `placement.json`（实例、网、电源轨、保护环、符号化框）。
6. 生成 `draw_layout.py`（KLayout `pya` 批脚本）并实际调用 `klayout -b -r` 写出 GDS。

两种模式都**拒绝 `drc_clean`**：symbolic 是拓扑草图；dimensional 即使尺寸填齐，PDK DRC/ESD/EM 规则仍是 TBD，也不能签核。

## 4. 产物（`sch/pads/gf180mcuD/layout/`）

| 文件 | 内容 |
|---|---|
| `layout_constraints.json` | 派生量、11 条复合约束状态、上游输入、未解清单 |
| `placement.json` | 11 个实例、11 张网、电源轨、保护环、符号化框；`drc_clean: false` |
| `constraint_graph.dot` | 复合依赖图（`dot -Tsvg` 可渲染） |
| `layout_plan.md` | 人类可读的约束表与"还不是版图"清单 |
| `draw_layout.py` | KLayout 批脚本，按 placement 画矩形并写 GDS |
| `sdr_bidir_pad_topology.gds` | **符号化拓扑草图**，cell 名带 `TOPOLOGY_ONLY`，标注 `NOT DRC CLEAN / SIZES TBD` |

`reports/layout_solver_report.md` 汇总结果。实测：GDS 可被 KLayout 读回（cell `sdr_bidir_pad_TOPOLOGY_ONLY`，16 个图形）；`check_layout.py` 全部通过。

## 5. 求解器两条路径都跑过

- 默认 symbolic：37/41 输入未解（31 设计参数 + 6 个 TBD 规则），9 条 unresolved + 2 条 structural，写出 sdr_bidir_pad_topology.gds（cell 名带 TOPOLOGY_ONLY，KLayout 读回 16 个图形）。
- `solve_packaged.py` 加封装 profile 与**合成测试夹具**：41/41 填齐后切到 dimensional，得到 7 条 satisfied、2 条 violated、2 条 structural。被判 violated 的是 `cell_width_fits_pitch`（CELL_WIDTH=2374µm 超过 pitch 180µm）与 `rail_em`（RAIL_WIDTH=12µm < 22.7µm），说明复合约束能检出冲突而不是一律放行。夹具明确标为 `synthetic_fixture`，不是设计值，见 `docs/PACKAGING_PROFILES.md` §3.2。

两条路径都保持 drc_clean: false；dimensional 也不等于签核，因为生成的尺寸来自合成夹具、PDK 规则仍有 6 项 TBD。

## 6. 与 P0-1~P0-5 的关系

- 求解器的输入正是 `specs/timing_contract.yaml` 里那 28 个 TBD 项的物理侧 counterparts；`modeling_plan` 里写的"怎么表征"就是这里"怎么填参数"。
- `tOE_on/off`、`dq_bit_skew`、`cmd_addr_skew` 等仍是 `null`，能力报告仍全部 `NO_GO`；求解器没有改判定。
- gf180mcu DDR1 已按本轮要求改为 `DEFERRED_LONG_TERM`（P4+），不再是硬排除；但 2.5 V SSTL_2 / VREF 缺口、`ck90`、相位源 G6 仍阻塞，仍 `NO_GO`。

## 7. 下一步（要变成真版图还差什么）

1. 把 gf180mcuD 的 DRC/LVS、ESD、latch-up、金属 EM 规则继续读进 `pdk_rules`：现已填 4/10，剩 `ESD_AREA_MIN`、`PAD_PITCH`、`PAD_OPENING`、`IO_CURRENT`、`DQ_BIT_SKEW_MAX`、`RAIL_WIDTH` 六项（其中后三项是设计输入，不是 PDK 规则）。
2. 用负载仿真填 31 个设计参数，先跑 `char_tb.spice` 的测量清单。
3. 定义 `PAD_OE_CTRL`、把预驱动展开到 `PDRV_STAGES`，确认二极管极性/体端/三端电阻。
4. 用 `--params` 跑 dimensional 模式，再跑 PEX/SPICE、EM/IR、ESD、latch-up。
5. 出 DRC/LVS-clean GDS 并做 pad ring 集成、封装/PCB 协同（见 `docs/SI_PI_PACKAGE_PCB.md`）。
6. 把同一套约束模型套到 sky130 / IHP / ics55 —— sky130 / IHP 的 device map 已绑定，ics55 仍缺 3.3 V ESD 二极管 SPICE 卡（见 `docs/PAD_GENERATOR.md` §3.1）。

## 8. 不这样做

- 不把符号化 GDS 说成可流片版图，不把 `TOPOLOGY_ONLY` cell 名去掉。
- 不填任何猜测的宽度、间距、电流密度或 ESD 目标。
- 不对约束文件里的表达式做 `eval`（闭白名单运算）。
- 不把 9 条 `unresolved` 说成"约束已满足"，不把 2 条 `structural` 说成已验证。
- 不因为生成器写了 GDS 就把 `reports/capability_report.md` 的 `NO_GO` 改掉。
- 不把 gf180mcu DDR1 的"远期计划"说成"现在支持"。
