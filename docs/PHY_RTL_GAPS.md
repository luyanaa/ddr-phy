# P0-4：补齐 Generic PHY RTL 缺口

状态：**P0 的数字侧剩余项已补完并验证；相位产生与真实 pad 仍是后端义务。**
`specs/timing_contract.yaml` 的 28 个 TBD 项没有减少，`reports/capability_report.md` 仍是全部 `NO_GO`。
本文件记录 P0-4 与后续 P0 收尾（BL / 刷新 / 集成顶层）两部分，见 §3.1。

## 1. 新增模块

| 文件 | 补的缺口 | 关键约束 |
|---|---|---|
| `rtl/read_capture_ctrl.sv` | `phase_select` / `capture_delay` 接口 | 相移时钟由后端提供；无后端时回退到 `clk`（`Δ=0`） |
| `rtl/clock_forward.sv` | 专用 CK forwarding 路径 | `ck` 不再当普通组合输出；供电就绪前拉低 |
| `rtl/dq_turnaround.sv` | OE 时序与 READ→WRITE 转向 | 守卫周期后放行 OE，用 `turnaround_busy` 与控制器协商 |
| `rtl/sdr_bist.sv` | BIST / DFT、相位扫描控制 | PRBS 图案、错误计数、相位步进、状态寄存器 |

复现：`sh sim/phy.sh`（全部 PASS；含 §3.1 的三组新测试）。

### 读采样相位
P0-2 的结论是：`B > tCK - tAC` 时必须把采样相位往后挪 `Δ ≈ B - (tCK - tAC)`。但 `reports/capability_report.md` 的 G6 仍开放——四套 PDK 都没有已表征的 PLL/DLL/延迟单元。所以 P0-4 只交**接口**：`read_capture_ctrl` 从后端给的 `phase_clks` 里选一路，`phase_sel` 由 CSR/BIST 控制，`phase_clocks_ready=0` 时明确回退到 `clk`。

选路是普通 mux，不是无毛刺时钟 mux；真 ASIC 需要 PDK 的无毛刺 mux 单元，这是后端义务，不是 RTL。**没有声称相位已经产生。**

### CK forwarding
`rtl/sdr_phy.sv:77` 仍是 `assign ck = clk`，没有改动（保持 9 项原有测试与 sky130 门级仿真不变）。`clock_forward` 提供了一条可替换的显式路径和 `ck_phase_sel` 钩子，并在 SDC 里对应 `create_generated_clock`。把 `sdr_phy` 的 `ck` 改接到这条路径属于集成步骤，本轮未做——因为接上去而没有已表征相位，只会把不确定性换个地方藏起来。

### 转向守卫
`dq_turnaround` 在读后阻塞 PHY 自己的 OE `GUARD_CYCLES` 拍，并用 `turnaround_busy` 告诉控制器暂缓列命令。它**不自己在引脚上插 NOP**（checklist §4.4）。`GUARD_CYCLES` 是设计参数，不是已表征的 `tHZ`；真值需要 G5 的 pad 时序。

### BIST
PRBS-32 图案经 `sdr_ctrl` 用户接口写入再读回比较，含 `error_count`、`pattern_count`、`phase_sel`、`bist_pass`、`phase_scan_done`。它在 `tb/tb_bist_loop.sv` 里跑真实 `sdr_ctrl + sdr_phy + sdram_model` 闭环，并编译两次覆盖 x8 / x16。

调试中修掉两个真实缺陷：BIST 的 nonblocking 握手与 `sdr_ctrl` 的寄存 `user_ready` 撞车（请求被静默丢弃，加了 request gap），以及 8-bit LFSR 在 `DATA_BITS=16` 时被切片越界产生 `X`（改为 32-bit LFSR）。

## 2. 对现有文件的修改

| 文件 | 修改 |
|---|---|
| `sim/sdram_model.sv` | 补 **DQM 读侧 2 拍屏蔽**：per-byte OE + `dqm_r1/r2` 延迟链；数据输出沿前两拍的 DQM 决定该字节是否 Hi-Z |
| `rtl/sdr_ctrl.sv` | `dfi_wrdata_mask` 宽度改为 `DATA_BITS/8`，放宽 `DATA_BITS != 8` 限制 → **x16 闭环成立** |

`tb/tb_phy_enh.sv` 里新增了 DQM 读屏蔽的正反用例：屏蔽字节在数据沿为 Z，未屏蔽读回 `16'hA55A`。`tb/tb_bist_loop.sv` 的 x16 编译验证了闭环。

## 3. 对照 P0-4 原清单

| 原列缺口 | 状态 |
|---|---|
| `ck` 专用 forwarding + generated clock | **已改接**：`rtl/sdram_phy_top.sv` 把 pad CK 接到 `clock_forward`，`sdr_phy.ck` 不再连 pad；`sdr_phy.sv` 本身未改 |
| read capture 独立化、留 `phase_select`/`capture_delay` | 接口已实现并暴露为顶层 `cap_clk`；相位产生仍依赖 G6 |
| DQM 读侧 2 拍屏蔽 | 模型已实现并验证 |
| OE turnaround 协商 | 已实现并验证 |
| `BL=2/4/8` | **已实现并验证**（§3.1） |
| x16 闭环 | 已实现并验证 |
| 初始化后刷新 / tREFI | **已实现并验证**（§3.1） |
| BIST / DFT 接口 | 已实现并验证 |

### 3.1 P0 剩余项补完

| 缺口 | 实现 | 验证 |
|---|---|---|
| `BL=2/4/8` 写 | `sim/sdram_model.sv` 增加写突发流水线：WRITE 拍取 beat 0，后续 CK 沿按 `wrap_col` 依次采样，每拍用当拍 DQM | `tb/tb_burst.sv` 覆盖 BL 2/4/8 写后读回 |
| 初始化后刷新 / tREFI | `rtl/sdr_ctrl.sv` 增加 `T_REFI`（默认 0 保持既有测试）：到期先 PRE 所有 bank，再 AUTO REFRESH，等 tRFC | `tb/tb_refresh.sv`：3 次周期刷新、无 `REF_OPEN`、数据仍为 `A5` |
| `ck` 专用 forwarding 改接 | `rtl/sdram_phy_top.sv` 把 `clock_forward` / `read_capture_ctrl` / `dq_turnaround` / `phy_io_adapter` 接成一条链，命令打包成 CMD 总线 | `tb/tb_phy_top.sv`：上电前 CK 拉低、`cap_clk` 回退、DFI 写到达 pad DQ、转向守卫门控 OE |

三个测试都并入 `sim/phy.sh`。**集成顶层是验证 / 接线用途，不是 LibreLane 硬化目标**——它例化了行为级 pad cell，不能进综合。

### 3.2 回归退出码与 CI

- `tb/tb_burst.sv`、`tb/tb_phy_top.sv`、`tb/tb_refresh.sv`、`tb/tb_bist_loop.sv` 以前只打印 `FAIL` 再 `$finish`，`set -e` 抓不到。现在这些测试以及 `tb_pad_adapter` / `tb_phy_enh` / `tb_timing_checks` 在有 error 时统一 `$fatal(1, ...)`。
- `sim/mutation.sh` 用 `-DMUTATE` 给每个 TB 注入一个错误，要求模拟器返回非零；这是退出码路径的 mutation test，不是数据通路的 mutation 覆盖。
- `.github/workflows/ci.yml` 跑生成器/证据检查、生成产物一致性 diff、`run.sh` / `phy.sh` / `pad.sh` / `sweep.sh`，以及 `sim/mutation.sh`。它不依赖本机 PDK，所以不跑 `gate.sh` / `char_pad.sh` / LibreLane。

### 3.3 Turnaround 协商

- `sdr_ctrl` 新增 `phy_turnaround_busy` 输入：忙时 WRITE 不被 `user_ready` 接受，`S_IDLE` 也不发 WRITE 命令；READ 仍可继续。
- `dq_turnaround` 的 guard 参数拆成 `GUARD_CYCLES + READ_TAIL_CYCLES + DQM_OFF_CYCLES + T_OE_OFF_CYCLES`，总时长仍是设计参数，不是已表征的 tHZ/tOE_off。
- `tb/tb_turnaround_ctrl.sv` 验证：忙时 WRITE 不被接受/不发命令；释放后 WRITE 发出且数据正确；READ 不被阻塞。
- 现有 `tb_sdr_loop` / `tb_refresh` / `tb_bist_loop` 把 `phy_turnaround_busy` 接 0，保持原有闭环行为；新测试单独覆盖协商。

### 3.4 Read Capture 第一阶段

- `rtl/sdram_phy_top.sv` 在 `cap_clk` 域增加了一个真实 capture FF，采样 pad 输入；`sdr_phy` 仍在 `clk` 域寄存这个捕获值。
- phase 0（`cap_clk = clk`）走 bypass；phase 1 使用**领先** core edge 的时钟。`tb/tb_read_capture_phase.sv` 在 early edge 与 core edge 之间改变 pad 数据，证明 phase 0 取到 late 值、phase 1 取到 early 值。
- 仍缺：late phase、Read FIFO/CDC、相位切换后的 pipeline latency 调整、动态训练。相位选择必须在初始化后锁定。
## 4. 与前后阶段的关系

- P0-3 的 `phy_io_adapter` 定义了 pad 边界；P0-4 的四个模块都停在**核心侧**，没有跨过 `dq_o/dq_oe/dq_i` 这条线。
- P0-5 的 SDC 把 `clock_forward` 的 `ck` 当作 generated clock 来约束，把 `dq_turnaround` 的 OE 当作第四类路径。
- 只要 G5/G6 一天不关，这些模块就只是**预留的可控量**，不构成时序闭合。
- P0 收尾的 `sdram_phy_top.sv` 把上述模块真正接成一条链；`cap_clk` 只暴露为接口，核心仍在 `posedge clk` 采样 `dq_i`。

## 5. 不这样做

- 不把 `read_capture_ctrl` 说成相位已经产生，不把普通时钟 mux 说成无毛刺 mux。
- 不把 `GUARD_CYCLES` 说成已表征的 `tHZ`，不声称 `dq_turnaround` 覆盖了 pad 的 OE 延时。
- 不把 BIST 通过说成时序签核或训练流程。
- 不把 x16 BIST 通过说成 BL>1 或刷新已支持。
- 不为了"看起来完整"去改 `sdr_phy` 的 `ck` 接法而破坏已通过的门级仿真：改接在集成顶层完成，`sdr_phy.sv` 保持不动。
- 不把 `sdram_phy_top.sv` 说成可硬化网表，不把 `cap_clk` 暴露说成 `Δ` 已作用到核心。
- 不把只打印 `FAIL` 的测试当成失败退出；新增 TB 必须走 `$fatal(1, ...)` 路径。
