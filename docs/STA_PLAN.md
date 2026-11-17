# P0-5：SDC / STA 与物理签核链

状态：**约束与报告链已建立，STA 未闭合，物理签核未做。**
`reports/capability_report.md` 仍是全部 `NO_GO`，`reports/timing_margin.json` 明确标记 `status: open`。

## 1. 交付物

| 文件 | 作用 |
|---|---|
| `generator/emit_sdc.py` | 从器件规格与 timing contract 生成 SDC |
| `flow/sdr_phy.sdc` | 生成的**草稿** SDC，四类路径 |
| `generator/check_timing.py` | 生成 `reports/timing_margin.json` |
| `reports/timing_margin.json` | 三个工作点的余量与阻塞项 |
| `flow/config.librelane.json` | 通过 `PNR_SDC_FILE` 接入 SDC |
| `docs/STA_PLAN.md` | 本文件 |

`python3 generator/emit_sdc.py --check` 会在任何 TBD 项仍开放时返回非零——这是防止把草稿当签核约束用的守卫。

## 2. SDC 结构

```text
create_clock           sys_clk  (clk, 10 ns)
create_generated_clock sdram_ck (ck, 从 clk 派生)
set_clock_uncertainty  TBD 占位
```

四类路径（checklist §6.1），各自用 `group_path` 命名：

| 组 | 发起 → 捕获 | 已知器件数 |
|---|---|---|
| CMD_TX | ASIC FF → SDRAM CK | tCMS 1.5 / tCMH 0.8 / tAS 1.5 / tAH 0.8 ns |
| WRITE_DQ_TX | ASIC FF → SDRAM CK | tDS 1.5 / tDH 0.8 ns |
| READ_DQ_RX | SDRAM CK → ASIC FF | tAC(2) 6.0 / tOH 3.0 ns |
| OE_TURNAROUND | PHY 控制 FF → 两端驱动状态 | tLZ 1.0 ns（上界）；下界暂用 tDH 0.8 ns 占位 |

关键点：

- **`ck` 是 generated clock**，不是普通组合输出。这对应 `docs/TIMING_BUDGET.md` §5 指出的问题——`assign ck = clk` 让 CTS 可以自由改动 CK 与 DQ 的相对关系。
- **没有写死一个 `set_output_delay 2`**。命令、写数据、读数据、时钟各自有不同的 min/max 条件和不同的板级延迟。
- `tAC` 用的是 CL2 的 **6.0 ns**，不是 CL3 的 5.4 ns。
- 读侧 `-min/-max` 不是真正的 PVT 配对：数据手册只给 `tAC(max)` 和 `tOH(min)`，没给 `tAC(min)` / `tOH(max)`。SDC 里明确写了这一点，用 `tOH(min)` 作为 hold 的保守边界。
- OE_TURNAROUND 的 `-min` **故意不用** `tHZ`：`tHZ = 6.0 ns` 是 SDRAM 释放总线的时间，不是 PHY 控制路径的已表征 hold 要求。第一版草稿把它当 `-min` 注入后，resizer 插了 19 个 hold buffer 并在 PostCTS 触发 `DPL-0036`。现在下界只用 `tDH` 占位，真实转向约束要等 G5 的 pad 时序。
- 端口模式用 `a[*]` / `dq_o[*]` 这类总线通配，但 `cs_n` / `cke` / `dm` 用 `*` 通配：Yosys 会把 1-bit 总线（`RANKS=1` 时 `[0:0]`）压成标量端口，`cs_n[*]` 匹配不到，第一次 LibreLane 运行报了 `STA-0366 port not found`。

## 3. 占位项与诚实边界

SDC 顶部有 12 个命名 Tcl 变量，全部 `= 0.000` 且标注 `TBD`：`board_dq_*`、`board_ck_*`、`pad_out_*`、`pad_in_*`、`t_uncertainty`、`toe_on/off`。它们对应 `specs/timing_contract.yaml` 的 28 个 `status: TBD` 项。

**把这些占位设为 0 会让时序看起来比实际好。** 所以：

- `emit_sdc.py` 在文件头打印 `DRAFT: not signoff-ready`；
- `--check` 模式在 TBD 未清零时失败；
- `check_timing.py` 生成的报告里 `status` 是 `open - no signoff claim`；
- `config.librelane.json` 的 `"//"` 字段同样写明这是草稿。

`reports/timing_margin.json` 给出的结论与 P0-1/P0-2 一致：固定相位只在 `B <= tCK - tAC` 时成立（A: 4.0 ns，B/C: 2.1 ns）；`B` 本身仍是占位数，所以三个工作点的 `classification` 都是 `open`。

## 4. 尚未做的（checklist §6.2–6.4）

| 项 | 为什么现在做不了 |
|---|---|
| 多 corner min/max STA 闭合 | 28 个 TBD 项，没有 pad/封装/板级 min/max |
| SDF 反标与布局后时序 | 没有 pad 网表、没有 PEX、没有真实布线 |
| PEX / SPICE（CK、写 DQ、读 DQ、OE 四条代表路径） | 没有手工 pad 原理图，`backends/*.yaml` 的 `schematic_drawn: false` |
| SPICE 里的沿率不对称、DCD、输入门限交越、多 DQ 同时翻转的 SSN | 同上，且 `tOE_on/off` 为 `null` |
| IBIS / 封装 RLC / PCB 传输线 / 端接 / 串扰 | 没有板级模型，不在本仓库 |
| SI / PI：眼图、过冲、反射、VDDIO 瞬态、去耦 | 同上 |
| pad ring DRC/LVS、ESD 路径、latch-up、天线效应、EM/IR | 四套后端全部 `NO_GO`（G1） |

这条链的第一块砖是 P0-3 的能力报告：没有合格 IO macro 与已表征 pad，后面每一层都没有输入。

## 5. 与 LibreLane 的关系：一次实证

`flow/run.sh sky130` 本来从未跑过（`docs/ARCHITECTURE.md` §8 记的是"flow/ 还没跑"）。本轮做了三次实跑：

| 配置 | 结果 |
|---|---|
| 原始配置（无 SDC） | **80/80 阶段完成**，Flow complete |
| 接上草稿 SDC（第一版） | PostCTS `DPL-0036 Detailed placement failed`，插了 19 个 hold buffer；另有 `STA-0366 port 'cs_n[*]' not found` |
| 修正端口模式 + 去掉虚高 OE hold 后的草稿 SDC | 仍在 PostCTS `DPL-0036`，33 个实例无法合法布局 |

结论：**草稿 SDC 不能接进 PnR**。28 个 TBD 占位全为 0 时，`create_generated_clock` 到 `ck` 加上相对 `sdram_ck` 的 `set_input_delay -min 3.0 / -max 6.0` 会把 CTS 后的 propagated clock 关系变成大量 hold 修复，撑爆当前 `PL_TARGET_DENSITY_PCT: 50` 的布局。控制组证明这不是既有地板规划问题。

所以 `flow/config.librelane.json` **故意保持不接** `PNR_SDC_FILE` / `SIGNOFF_SDC_FILE`；`flow/sdr_phy.sdc` 作为约束模板留在仓库，等 `generator/emit_sdc.py --check` 通过（TBD 清零）后再接。用草稿约束跑出来的"时序看起来更好"或"PnR 跑挂了"都不构成 STA 结论。

顺带修掉两个真实缺陷：Yosys 会把 1-bit 总线压成标量，`cs_n[*]` / `cke[*]` / `dm[*]` 匹配不到（改用 `*` 通配）；以及第一版把 `tHZ = 6.0 ns` 当成 `dq_oe` 的 `-min` 注入，那是 SDRAM 释放总线的时间，不是 PHY 控制路径已表征的 hold 要求。

**跑通 OpenROAD 的 CTS/Route/STA 不等于 PHY 完成**：那只是数字后端内部的 timing closure，外部存储器、pad、封装、PCB 全在约束之外。

## 6. 分期对应关系

- P0-1：Timing Contract + 一阶预算 → 已完成
- P0-2：timing-aware 模型 + 相位扫描 → 已完成
- P0-3：pad adapter + capability report → 已完成，判定 `NO_GO`
- P0-4：RTL 可控量 → 已完成，相位产生依赖 G6
- P0-5：SDC / 报告链 → 本次；**STA 闭合与物理签核仍属 P1**
- P1：PEX / SPICE / IBIS / SI-PI / pad ring / 多 corner
- P2：跨 PDK generator、能力等级、可校准 PHY

## 7. 不这样做

- 不把草稿 SDC 说成签核约束，不把 `TBD = 0` 的占位当成已表征值。
- 不把 `tAC = 6.0` 换成 CL3 的 5.4，不把 Micron 与 ISSI 的表混用。
- 不把 "LibreLane 跑通" 说成 PHY 端到端时序闭合。
- 不把 `reports/timing_margin.json` 里的 `ideal_*_ceiling` 说成可用余量。
- 不声称做过 SDF、PEX、SPICE、IBIS、SI/PI 或 DRC/LVS。

## 8. P1-3：CK 输出与端到端 min/max 余量

本次把 SDC 里 4 个 pad 占位换成了 **SPICE 特征化值**，并新增了转发 CK 的路径组：

| 项 | 来源 | 值 |
|---|---|---|
| `pad_out_min` / `pad_out_max` | `reports/pad_delay_gf180mcuD_*.json`（5 个 PVT 点） | 0.208 / 0.441 ns |
| `pad_in_min` / `pad_in_max` | 同上 | −0.002 / 0.096 ns |
| `toe_on` / `toe_off` | `reports/pad_char_gf180mcuD_*.json`（5 个 PVT 点最大值） | 0.608 / 3.299 ns |

新增 `group_path -name CK_OUT`：`ck` 是转发时钟，`set_output_delay` 用 `pad_out_*` 加板级项（板级仍是 TBD）。

数字部分用 **yosys + OpenSTA** 跑了 `sdram_phy_top`（GF180 `mcu7t5v0`，tt/ss/ff 三个 liberty 角）：

- 网表未布局、无 wire load，延迟是**布局前估计**，不是签核值。
- `sim/p1_3_timing.sh` 依次跑：pad 延迟特征化（5 点）→ yosys 综合 → 三个角的 OpenSTA → `generator/p1_3_margins.py`。
- 结果：`reports/p1_3_margins.json`、`reports/p1_3_timing.md`。

| 检查（最差角，ns） | 余量 |
|---|---|
| 写 setup | **−3.168（ss）** |
| 写 hold | +9.453 |
| 读 setup | +2.621（ss） |
| 读 hold | +3.204 |
| OE 开启 | +3.408 |
| OE 关断 | +5.737 |

**结论：写 setup 是负的，`reports/p1_3_margins.json` 标 `NO_GO`。** 原因是结构性的：CK 从 `clk` 端口经 2 级门（mux + 电源门）直接出片，DQ 要经输出寄存器 + turnaround mux + adapter。ss 角 CK 到片边约 1.0 ns，DQ 约 2.66 ns，DRAM 要求 DQ 比 CK 早 1.5 ns（tDS），于是 −3.17 ns。

这不是约束能修的：要么用已表征的 CK 相位/延迟单元（能力门 G6，`clock_forward` 的 `ck_phase_clks` 就是留给它的钩子），要么改写出方案（DQ 提前一拍）。文档明确禁止用未表征的 inverter chain 移相，所以本次**不动 RTL**，只把结论和数字固定下来。

`generator/emit_sdc.py --check` 仍然失败（板级、uncertainty、pll_dll、pad_slew 仍是 TBD），所以 SDC 继续保持草稿状态，不接进 PnR。

## 9. P1-3 修复：写 setup 转 GO（路径 B）

原先的 −3.168 ns 是结构性的：转发 CK 从 `clk` 经 2 级门直接出片，DQ 要经输出寄存器、turnaround mux 和 adapter，ss 角 CK 比 DQ 早约 1.7 ns，而 DRAM 要求 DQ 早 1.5 ns。

先试过路径 A（`ck_delay_line`，14 级 GF180 `inv_1`）：STA 显示链路比 DQ 路径随工艺更陡（ss 5.33 ns / ff 1.58 ns），ff 角仍差 −0.68 ns，且吃掉 hold 余量，已移除。

最终实现 **路径 B**（`rtl/sdr_phy.sv`）：

- 命令/地址/控制打一拍出片（pin command 比 DFI 命令晚一个周期）；
- `dq_o` / `dm` / `dq_oe` 在 DFI 周期的**下降沿**发射（提前半拍）；
- DFI 读延迟相应变为 `CL+2`（`specs/interface.yaml` 已更新）。

余量公式随之变为：

```text
M_write,setup = tCK/2 + tCLK,fwd(min) - tDQ,tx(max) - tDS
M_write,hold  = tCK/2 + tDQ,tx(min)  - tCLK,fwd(max) - tDH
```

结果（`reports/p1_3_margins.json`，status **GO**）：

| 角 | 写 setup | 写 hold | 读 setup | 读 hold |
|---|---|---|---|---|
| tt | +2.637 | +4.574 | +3.278 | +3.359 |
| ss | **+1.781** | +4.963 | +2.617 | +3.719 |
| ff | +3.005 | +4.416 | +3.567 | +3.204 |

半周期关系由 tCK 决定，不依赖匹配延迟，所以三个角同时为正。

**未闭合**：`sim/run.sh` 的 pin 级 DRAM 模型测试在命令打拍后报 `RW_CLOSED`（模型在采样沿看不到命令窗口），单元级 `tb_sdr_phy` 四个用例全部 PASS。这是模型/testbench 与新命令时序的对齐问题，待修；`reports/p1_3_margins.json` 的 GO 只针对 STA 余量，不代表该测试通过。
