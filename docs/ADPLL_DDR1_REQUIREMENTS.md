# adpll_gen DDR1 / IHP130 接口需求（v0.2）

日期：2026-11-27（v0.2 增补：2026-11-28，加入 §4.5 过程要求）
用途：交给 `adpll_gen` 维护者的 handoff 需求，不是签核结论。
范围：`ddr-phy` 的 IHP130 DDR1（MT46V32M8-75E，100 MHz，2.5 V SSTL-2）所需的核心时钟与 DQS 接收延迟线。
边界：`adpll_gen` 只负责 **1.2 V core 时钟/延迟线 RTL 与 IHP130 标准单元实现**；IHP130 SSTL-2 pad、VREF/VTT、封装、SI/PI、全芯片电源由 `ddr-phy`/板级负责。DQS/DQ pad 之间的失配不计入 `adpll_gen` 的 CK90 预算，但 `ddr-phy` 必须单独约束。

当前起点（维护者需要知道）：`DDR_CLOCK_PHY` 目前只有 200 MHz 的 `CK_PHY/CK_PHY_N`，没有 `CK90`；DQS 延迟线目前只有 16 个 fine tap、约 1 ns 范围；IHP130 只有结构/单元映射线索，没有 100 MHz 的 real-cell 证据。下面是对 DDR1 的新要求，不是对现有 200 MHz 结果的复用。

## 0. 总体策略

分两阶段，避免把未签核的 PLL 变成 DDR1 bring-up 的阻塞项：

- **Phase A（默认，先跑通）**：第一版测试片继续由板级/外部提供 `CK`、`CK90`、`SYS_CLK`。`adpll_gen` 只需保证不挡路：提供 bypass/quiet 模式，输出在未锁定时为低，接口与 Phase B 一致。
- **Phase B（片上时钟）**：`adpll_gen` 提供 100 MHz `CK/CK#`、100 MHz `CK90`、50 MHz `SYS_CLK`，以及 DQS 接收延迟线。满足下面的接口与时序要求；没有 IHP130 证据前，不得声称满足 DDR1 时序。

明确禁止的三种“看起来像”做法：

1. 不要把 `CK_PHY_N` 当 `CK90`。它是 180° 反相，不是 90°。
2. 不要用 fractional `OUT_DIV` 直接驱动 DDR 时钟/DLL。当前 `OUT_DIV` 边沿间距不均匀，full-period DLL 不能锁定；需要整数分频后的均匀参考。
3. 不要用 `SEL_REQ` 的 16 个 fine tap 当 90° 移相。它们只覆盖约 1 ns，且不是 PVT 跟踪的 2.5 ns 正交时钟。

## 1. 时钟接口（Phase B）

| 信号 | 方向 | 频率/电平 | 要求 |
|---|---|---|---|
| `CK_PHY` | out | 100 MHz，1.2 V core | 周期 10 ns；占空比 45–55%；锁定前为低 |
| `CK_PHY_N` | out | 100 MHz，1.2 V core | `CK_PHY` 的互补；与 `CK_PHY` 走匹配路径，差分交叉偏差 ≤100 ps |
| `CK90_PHY` | out | 100 MHz，1.2 V core | 相对 `CK_PHY` **滞后 90°**，即 2.5 ns；不能是 180° 或由独立自由运行延迟线产生 |
| `SYS_CLK` | out | 50 MHz，1.2 V core | `CK_PHY/2`；上升沿与某一条 `CK_PHY` 上升沿对齐；占空比 45–55% |
| `PHY_LOCKED` | out | 电平 | 仅在 PLL/DCC/CK90 全部有效时为高；失锁立即为低 |
| `ERR` | out | 电平 | sticky 错误；至少覆盖失锁、CK90 相位越界、延迟线码越界 |

`CK_PHY`/`CK_PHY_N` 是送 IHP130 CK pad 宏的 core 信号，不是 2.5 V SSTL 输出；`CK90_PHY` 只在 core 内给 `ddr_edge_out` 发射 DQ/DM，不要求做 pad 输出。

## 2. 时钟时序要求

以下为初始预算，最终要由 IHP130 STA/SPICE 确认；不能只给 RTL 仿真结果。

- **周期**：10 ns ±1%（100 MHz）；只要求生产点 100 MHz，不要求 `adpll_gen` 扫 10/11/12 ns；仿真扫频可由外部时钟完成。
- **占空比**：`CK_PHY` 高/低各 4.5–5.5 ns（45–55%）；`CK_PHY_N` 与 `CK_PHY` 的差分交叉应居中，单端占空比偏差 ≤5%。
- **CK90 相位**：`t(CK90) - t(CK) = 2.5 ns ±0.2 ns`（初始目标 ±0.1 ns），在 core 输出端、所有 PVT 角**包含漂移**；不能靠一条未校准的固定延迟线通过。
- **SYS_CLK 相位**：50 MHz，周期 20 ns ±1%；上升沿相对 `CK_PHY` 上升沿偏差 ≤0.2 ns（全 PVT）；占空比 45–55%。
- **抖动**：目标 period jitter ≤100 ps pk-pk、cycle-to-cycle ≤50 ps；必须给出测量/仿真口径。没有 jitter 数据时，不得把 DDR1 时序余量写成已闭合。
- **锁定/启动**：`PHY_LOCKED` 必须在 DDR1 200 µs 上电窗口结束前为高（目标 <100 µs）；锁定前 `CK_PHY`、`CK_PHY_N`、`CK90_PHY` 全部为低；首次有效 `CK` 必须已经带确定 90° 关系，不能有 180° 相位歧义。
- **失锁**：`PHY_LOCKED` 拉低时，`CK_PHY`、`CK_PHY_N`、`CK90_PHY` 必须同时停低；允许最后一个高脉冲被截断，但控制器必须把它当故障并停止数据。`CK90` 不能单独继续跑。
- **同源**：`CK`、`CK90`、`SYS_CLK` 必须来自同一根参考/同一 PLL，不允许 `CK90` 由独立自由运行延迟线或独立 PLL 产生；`CK90` 的 PVT 漂移必须与 `CK` 共同跟踪。

## 3. DQS 接收延迟线

### 3.1 接口

保持 `ddr-phy` 现有 `rtl/ddr_dqs_delay_adpll.sv` 的语义，`adpll_gen` 提供可实现的物理延迟线/primitive：

| 信号 | 方向 | 说明 |
|---|---|---|
| `DQS_IN[LANES-1:0]` | in | 来自 IHP130 DQ/DQS pad 的 **1.2 V core 接收器输出**；总线高阻时必须为确定的低电平，不能是 raw SSTL pad |
| `DQS_CAPTURE[LANES-1:0]` | out | 延迟后的 DQS，送 `ddr_read_capture` |
| `TAP_VALID[LANES-1:0]` | in | sys 域请求 |
| `TAP_VALUE[LANES*TAP_BITS-1:0]` | in | 每 lane 独立码值 |
| `TAP_READY[LANES-1:0]` | out | 仅在 `UPDATE_IDLE=1` 且码值已稳定后拉高 |
| `UPDATE_IDLE` | in | 只允许在无读突发、无在途 DQS 边沿时更新；`ddr1_top` 需要新增该端口 |
| `TAP_ERROR[LANES-1:0]` | out | 码值越界/延迟线失效，可选但建议有 |

`LANES=1` 对应 x8；`LANES=2` 对应 x16。`TAP_BITS>=5`（至少 32 码），不能继续用 4 bit/16 码覆盖 5 ns。

### 3.2 延迟范围与精度

- **范围**：0–5 ns。中心工作点 2.5 ns 用于把读 DQS 移进 DQ 眼；要覆盖 `tDQSCK = ±0.75 ns`、DQS/DQ pad 失配和板级 skew。
- **码数/步进**：≥32 码；平均步进 ≤200 ps（0–5 ns 用 32 码时约 161 ps），目标 ≤170 ps；若要 ≤150 ps，至少 34 码。全范围单调，不允许负步进；coarse/fine 边界步进不得超过标称步进的 1.5 倍。
- **单调性**：code→delay 在 TT/SS/FF 及温度角单调；不能只用 Liberty 证明 fine 步进（IHP fine bank 目前有 15 个非单调 step 的记录，必须先修或给出 calibrated map）。
- **建立/保持**：码值更新后 `TAP_READY` 只能在输出稳定后拉高；`SETTLE_CYCLES` ≤4 个 sys 周期；更新期间 `DQS_CAPTURE` 不得出现毛刺或半个脉冲。
- **突发保护**：`UPDATE_IDLE=0` 时不得改码；码值在整段读突发内保持；复位码为 0（最小延迟）。
- **输入行为**：`DQS_IN` 为静态低时，`DQS_CAPTURE` 必须为静态低；不得因 pad 高阻/接收器抖动产生假边沿。若 pad RX 不能保证，需在 `ddr-phy` 侧加 gate，不能把责任推给延迟线。

### 3.3 现有实现的差距（维护者需要知道的起点）

- `PLL_DCDL_TAP_BUS_PHYS` 只是 `NTAPS` 个 `FINE_DELAY_CELL` 串联；IHP 每个 fine cell 约几十 ps，16 个 tap 约 1 ns，**不够 5 ns 范围**。
- `ddr_dqs_delay_adpll` 默认 `TAP_BITS=4, STEP_CELLS=1`，实际范围小于 1 ns；当前训练 TB 用的是 fake 16-tap/312.5 ps 模型，不是这条物理线。
- `ddr_dqs_delay_adpll` 的 `UPDATE_IDLE` 已经存在，但 `ddr1_top` 没有该端口；`ddr-phy` 会补顶层端口和 `burst_active` 逻辑，并把 `ddr_dqs_train` 的 `TAP_BITS` 从 4 扩到 5（或参数化）。
- `PLL_SEGMENTED_DELAY_PHYS` 有 coarse/fine 结构，但原始 4-seg 边界曾非单调；DQS 线若复用该结构，必须保留边界单调性修复和边界测试。

## 4. IHP130 实现与证据要求

`adpll_gen` 交付不能只给 ics55 结果；IHP130 至少要提供：

1. `DDR_CLOCK_PHY` 100 MHz IHP130 real-cell elaboration：
   - `pll_cells_ihp-sg13g2.v` + `sg13g2_stdcell` Liberty；
   - Yosys/OpenSTA TT/SS/FF（1.2/1.08/1.32 V，25/125/−40 °C）；
   - `CK_PHY`/`CK_PHY_N`/`CK90_PHY` 的周期、占空比、相位、fail-closed 检查。
2. `DDR_DQS_DELAY` IHP130 real-cell 表征：
   - 32 码（或以上）的 code→delay 表，TT/SS/FF；
   - 范围、步进、单调性、coarse/fine 边界、每 lane skew；
   - 至少一个 gate-level/SDF smoke；PEX/PVT 可后续补，但必须标注“未做”。
3. 集成 TB：
   - `ddr1_top` + 生成式 LiteDRAM controller + `ddr1_device_model`；
   - CK=10 ns，`tDQSCK=±750 ps`，至少 9 角；若 `adpll_gen` 只支持 100 MHz，9 角中的 11/12 ns 可用外部时钟，片上只验证 10 ns；
   - 训练模式 active/fail 都要跑；`TAP_READY`/`UPDATE_IDLE` 时序要逐拍检查。
4. 约束/文档：
   - `create_clock`/generated clock、CK/CK90 的 phase 约束、DQS delay 的 false/multicycle 约束；
   - 一张接口/参数表，列出 `TAP_BITS`、`STEP_CELLS`、`FIRST_STAGE`、`SETTLE_CYCLES` 的合法范围和 IHP130 推荐值；
   - 明确“core 1.2 V、非 2.5 V pad”的边界。
5. **过程要求（P0，先于一切 pass-2 工作；源自二次检查 §2.3，`ADPLL_DDR1_SECOND_CHECK.md`）**：
   - 目前全部 9 个 ddr1 源文件（`ddr1_clock_top.v`、`ddr1_clock_top_tb.v`、`ddr1_ck90_dll.v`、`ddr1_ck90_de2.v`、`ddr1_ck90_compare_tb.v`、`ddr1_dqs_delay.v`、`ddr1_dqs_delay_line_phys.v`、`ddr1_dqs_delay_tb.v` 及相关输出）是 **untracked 工作树文件**，必须先提交进 git；后续所有 pass-2 证据必须可从已提交内容复现。
   - `sim/tests.mk` 中目前没有任何 ddr1 target（grep 零匹配），TB 靠 TB header 里的 ad-hoc iverilog 命令运行；必须为 `ddr1_clock_top_tb`、`ddr1_ck90_compare_tb`、`ddr1_dqs_delay_tb` 加正式 make target，并纳入回归（`test_p0` 或同级）。
   - 证据目录命名需避免误导：`sim/outputs/ihp-sg13g2/dll_gate_*.log`、`tdc_phys_gl_*.log` 实际是 ics55 单元 build（`flow/sta/run_*.sh` 硬编码 ICS55 liberty），IHP130 证据必须与 ics55 证据分目录、分命名，不得混放。

## 5. 验收清单

- [ ] 100 MHz `CK/CK#`，占空比 45–55%，差分交叉偏差 ≤100 ps。
- [ ] `CK90` = `CK` 滞后 2.5 ns ±0.2 ns（目标 ±0.1 ns，全 PVT），无 180° 歧义。
- [ ] `SYS_CLK` = 50 MHz，与 `CK` 上升沿对齐 ≤0.2 ns。
- [ ] `PHY_LOCKED` 在 200 µs 前有效；失锁时三路时钟同时停低。
- [ ] DQS 延迟线 0–5 ns、≥32 码、步进 ≤200 ps、单调、边界无负步进。
- [ ] `UPDATE_IDLE`/`TAP_VALID`/`TAP_VALUE`/`TAP_READY` 握手在突发期间不改码，`TAP_READY` 只在稳定后拉高。
- [ ] IHP130 TT/SS/FF real-cell 证据；没有证据的 corner 明确标注未闭合。
- [ ] `ddr1_top` 10 ns + `tDQSCK=±750 ps` 闭环通过；训练 active/fail 通过。
- [ ] 文档写明 Phase A（外部时钟）与 Phase B（片上时钟）的切换方式，以及未签核边界。

## 6. 非目标

- 不要求 `adpll_gen` 设计 IHP130 2.5 V SSTL-2 pad、VREF/VTT、封装、IBIS/SI/PI。
- 不要求本轮做全芯片 PLL/CSR/DFS/scan/电源管理。
- 不要求 200 MHz 或 ics55 结果直接等价到 IHP130；200 MHz/ics55 只能作为结构参考，不能作为 IHP130 签核证据。
- 不要求 `adpll_gen` 支持 10/11/12 ns 全扫；生产点 100 MHz，仿真扫频可由外部时钟完成。

## 7. 交接物

- `DDR_CLOCK_PHY` 或新的 `DDR1_CLOCK_TOP` RTL：端口、参数、100 MHz 配置。
- DQS 延迟线 primitive/wrapper RTL：`CLK_IN`/`TAP` 或 `SEL` 接口、码表、IHP130 映射。
- IHP130 测试 target 与日志：elaboration、Yosys/OpenSTA、gate-level/SDF、集成 TB。
- 上述证据的路径和“未做”清单；不要只写 PASS 不带 corner/条件。
