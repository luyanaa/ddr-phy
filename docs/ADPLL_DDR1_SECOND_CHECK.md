# adpll_gen DDR1 ck90 / DQS 二次检查报告（v1.0）

日期：2026-11-28
检查人：ddr-phy 侧（Orchestrator）
检查对象：`/grid/adpll_gen` 工作区（HEAD `d8bf7e0` + **未提交**的 ddr1 工作树文件）
检查基准：`docs/ADPLL_DDR1_REQUIREMENTS.md`（v0.1）§1–§5
证据：`/grid/adpll_gen/sim/outputs/ddr1/*.log`（2026-11-28 13:20–13:26 运行）+ RTL 全文精读

## 0. 总结论

**Pass-1 行为级：结构方向正确，行为级证据充分，可以作为 Phase B 的架构基础继续。**
**Pass-2 real-cell：完全未开始，§4 证据要求一项都不满足，不得声称满足任何 DDR1 时序。**

三条禁止做法全部正确避开：没有用 `CK_PHY_N` 当 90°、没有用 fractional `OUT_DIV`、没有用 16-tap fine 线当移相器。candidate B（master/slave ratio DLL）是同源/PVT 共跟踪的正确架构。

但：行为模型内部的若干**系统性相位误差机制在行为级被零延迟掩盖**，real-cell 转换时会直接吃 ±200 ps 预算；且全部 ddr1 文件**未提交进 git**、无 make target，过程风险需要先处理。

## 1. §5 验收清单逐项判定

| # | 验收项 | 判定 | 证据/缺口 |
|---|---|---|---|
| 1 | 100 MHz CK/CK#，占空比 45–55%，交叉 ≤100 ps | **行为 PASS / real-cell 未证** | TB: 周期 10.000 ns、高电平 5.000 ns（`ddr1_clock_top_tb.log` check2/3）。交叉偏差行为级不可测（零延迟门）；`go_q & ck_a` vs `go_q & ~ck_a` 反相器路径不对称，real-cell 需匹配 + STA |
| 2 | CK90 = CK+2.5 ns ±0.2 ns（目标 ±0.1），无 180° 歧义 | **行为 PASS / 数值未证** | TB: lag 2500.0/2508.8 ps；A/B matrix 12 个 duty/skew 注入点 B 恒定 12.0 ps 误差（`ck90_ab_matrix.csv`）；check18 验证 180° 反相被 monitor 拒。但行为模型掩盖了至少 3 个 real-cell 系统误差源（§2.2），±200 ps 预算的实际消耗未知 |
| 3 | SYS_CLK 50 MHz，与 CK 上升沿对齐 ≤0.2 ns | **行为 PASS / real-cell 未证** | 行为级 check4 aligned（构造对齐）；real-cell 中 `sys_r` flop t_cq + AND 门相对 CK 路径不平衡，量级未知，需 STA |
| 4 | PHY_LOCKED 200 µs 前有效；失锁三路同时停低 | **链内 PASS / 系统级风险** | TB: 锁定 300 ns ≪ 200 µs；check10/13/17 fail-closed 全 PASS。风险：PHY_LOCKED 依赖输入 `PLL_LOCKED`，而 adpll 宏自身**相位锁定在仿真中从未断言**（`LOCK_TRANSIENT.md`：FREQ_LOCKED @578 但 LOCKED 1600 REF 内不亮）——集成时 200 µs 预算的真实瓶颈在上游 PLL |
| 5 | DQS 延迟线 0–5 ns、≥32 码、≤200 ps、单调、无负步进 | **行为 PASS / real-cell 未证且有前科** | TB 37/37 PASS：0–8890 ps、128 码、70 ps 均匀步进、strict monotonic、neg=0。但 IHP fine bank 有 15 个非单调 step 的已知记录（需求 §3.2 L71），IMPL=1 real-cell 结构存在却从未仿真，无任何 STA/SDF 单调性复验 |
| 6 | UPDATE_IDLE 握手、突发不改码、TAP_READY 稳定后拉高 | **行为 PASS，两处语义偏差需文档化** | 握手 FSM 正确（`ddr1_dqs_delay.v` L121-158），check3/3b/4/6 覆盖含 ack 窗口内 idle 撤回的死角。偏差①：`TAP_ERROR` 被重定义为"非 idle 更新违规"而非规格书的"码值越界/线失效"（RTL L41-46 辩称 TAP_VALUE 宽度恰好不可能越界——可接受但须写进接口文档）；偏差②：`SETTLE_CYCLES≤4` 上限在 RTL 无强制（L82-83 只查 ≥1），目前 TB 用 2 |
| 7 | IHP130 TT/SS/FF real-cell 证据 | **FAIL（缺失）** | 零。ddr1 全部文件无一个 sg13g2 单元引用、无 SDF/gate-level/STA/ngspice 证据；`pll_cells_ihp-sg13g2.v` 映射文件存在但 ddr1 未使用。注意 `sim/outputs/ihp-sg13g2/dll_gate_*.log` 虽有 DLL 三角 gate-level 证据，实际是 **ics55** 单元 build（`run_dll_gate.sh` 硬编码 ICS55 路径），不能算 IHP130 证据 |
| 8 | ddr1_top 10 ns + tDQSCK=±750 ps 闭环、训练 active/fail | **未开始** | 集成 TB 不存在；依赖 ddr-phy 侧 `ddr1_top` 与训练逻辑，本轮范围外 |
| 9 | Phase A/B 切换文档、接口参数表 | **部分** | bypass 机制在 `ddr1_clock_top.v` header 有完整文档（BLOCKER 8a–d，实现与文档一致）。缺：TAP_BITS/STEP_CELLS/FIRST_STAGE/SETTLE_CYCLES 合法范围与 IHP130 推荐值参数表（§4.4 要求） |

## 2. 关键技术分析

### 2.1 行为级已验证的强项（可信，无需重做）

- **ratio DLL 结构正确**：5 个相同 `DDR1_DLL_SEG` 共享 CODE，master=T 锁定 ⇒ slave=T/4 是结构比而非固定延迟（`ddr1_ck90_dll.v` L9-26），满足"同源、PVT 共跟踪"硬性要求。
- **失锁判据定量论证成立**：LOSS_TOL=640 ps master（160 ps CK90）< 200 ps 硬规格；3 样本 ≈30 ns 内环路最多 slew 3 LSB=192 ps master，不可能在 trip 前把超规格偏移拉回 band——fail-closed 论证在 L107-120 注释中完整且在 check10/17 有实测。
- **180° 拒绝**：三点采样（CK 上升须低/下降须高/CK+2.8 ns 须高），check18 实测 `errA=1 lockA=0`。
- **无 runt 释放**：`go_q` 在 CK 上升沿寄存释放（CK90 此时必低）、异步落下；TB 首脉冲验证 PASS。
- **DQS 线毛刺 gate**：`settled_q` 强制 capture 在整段 settle 窗口为低，128 码全扫描零假边沿（check4）；`update_idle` 在 ack 窗口内撤回不丢请求（check3b）——这两个是实际设计中常见的坑，已覆盖。

### 2.2 Pass-2 必修的系统误差源（行为级不可见，已在源码自认）

1. **`CK90 = EN & slave_out` 的 AND 门只在 slave 路径**（`ddr1_ck90_dll.v` L476）。行为级零延迟；real-cell 中该门延迟只加在 CK90 输出、不进 master 反馈，是**未补偿的固定相位超前误差**（IHP130 单门约 30–80 ps 量级，直接吃 ±200 ps 预算的 15–40%）。修法：master 反馈路径插 matched replica 门，或在锁定目标中校准扣除。
2. **主/从段负载失配未建模**：slave 末级驱 AND 门，master 各段驱下一级输入——real-cell 负载不同会弯曲 4:1 精确比。行为模型所有 cell 延迟相同，完全看不到这个效应。
3. **`$realtime` 时间戳 FIFO 相位测量**（L290-301）不可综合——整个锁定/失锁判据建立在行为级测量前端上。pass-2 需替换为 coarse-cycle counter + TDC（源码注释已指明方向，硬件不存在）。
4. **`assign #2.8 ck_a_qtr`**（`ddr1_clock_top.v` L260）——monitor 第三采样点的行为级延迟时钟，real-cell 需 edge-order/TDC 替代。
5. **延迟 chain 为 `#` transport + 线性 0.25 ps/LSB 控制律**——real cell 非线性、粒度更粗；16 ps/LSB 的 CK90 dither 分辨率在真实单元下未必能达到，锁定带 48 ps 的成立性需重估。
6. `dly_off_x4`/`ck90_inv_tb` TB 脚手架（pass-2 删除，源码已注明）。

### 2.3 过程风险（建议本周处理）

- **全部 9 个 ddr1 文件是未提交的工作树文件**（`git status` untracked：`ddr1_clock_top.v`、`ddr1_ck90_dll.v`、`ddr1_dqs_delay*.v`、3 个 TB 等），sim 日志也是本地生成。一旦丢失/被覆盖无恢复路径。
- `sim/tests.mk` 中**无任何 ddr1 target**（grep 零匹配），TB 靠 header 里记录的 ad-hoc iverilog 命令跑，不可复现性差。
- `sim/outputs/ihp-sg13g2/` 目录名误导：其中 dll_gate/tdc_phys 的三角证据实为 ics55 build（脚本硬编码），阅读证据时必须核对 `flow/sta/run_*.sh` 的 liberty 路径。

### 2.4 上游与机会

- 上游 PLL 风险：adpll 宏频率锁定 ~2.5 µs（满足 200 µs 预算），但**完整相位锁定行为级从未断言**；若 PLL_LOCKED 实际是"频率锁定即放行"，DDR 时钟链会带相位 dither 上电——需与 adpll_gen 维护者澄清 PLL_LOCKED 的语义。
- 机会：已提交的 `dll8` workstream（switched-cap MOSCAP 延迟线，KLayout DRC 0/LVS match，~25 commits，三角频率表征 SS 279–337/TT 437–553/FF 659–837 MHz）是**有真实 PDK signoff 证据的延迟线资产**。pass-2 的 DQS 线甚至 ck90 replica 段可评估复用 dll8 element 而非从未流片验证的 FINE_DELAY_CELL 链。

## 3. Pass-2 必做清单（按优先级）

| 优先级 | 事项 | 对应验收项 |
|---|---|---|
| P0 | ddr1 文件提交进 git + tests.mk 加 target（可复现性） | 过程 |
| P0 | IHP130 real-cell elaboration：ck90 DLL + DQS 线 IMPL=1 用 `pll_cells_ihp-sg13g2.v` 编译，Yosys/OpenSTA TT/SS/FF | #7 |
| P0 | DQS 线 real-cell code→delay 表征 + 单调性复验（含 IHP fine bank 非单调前科的处理：修或 calibrated map） | #5 |
| P1 | `EN & slave_out` AND 门的 master 路径 matched replica（或校准）；主/从负载匹配设计 | #2 |
| P1 | 相位测量硬件化：coarse counter + TDC 替换 `$realtime` FIFO | #2/#4 |
| P1 | CK/CK# 交叉匹配路径 + SYS_CLK t_cq 不平衡 STA 量化 | #1/#3 |
| P2 | monitor 三点采样的 real-cell edge-order/TDC 实现 | #2 |
| P2 | 接口参数表（TAP_BITS/SETTLE_CYCLES 等）+ TAP_ERROR 语义写入文档；SETTLE_CYCLES≤4 加 RTL 强制 | #6/#9 |
| P2 | jitter 测量口径与数据（没有则时序余量不得声称闭合，§2 L44） | #2 |
| P3 | ddr1_top + tDQSCK 闭环集成 TB（与 ddr-phy 联合） | #8 |

## 4. 对 ddr-phy 侧的提示

- `ddr1_top` 需新增 `UPDATE_IDLE` 端口与 `burst_active` 逻辑（需求 §3.3 已记），与 adpll_gen 的 FSM 语义已核实兼容：`tap_valid` 在 `UPDATE_IDLE=0` 且无在途应用时断言会置 sticky `TAP_ERROR`（仅复位或下一次成功应用才清除），训练逻辑必须保证只在 idle 窗口发请求。
- DQS 线默认 128 码/70 ps 行为模型下中心 2.5 ns ≈ 码 36；real-cell 各角码表出来后训练搜索范围需按角重定。
- 复位码 0 = 零 extra 延迟（TAP[0]=输入直通），上电 DQS 未偏移——训练序列设计注意这意味着初始采样点在 DQS 原相位。
