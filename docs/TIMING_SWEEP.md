# P0-2：Timing-aware 模型与读采样相位扫描

状态：**仿真层的可行性研究**。不是 STA，不是 SDF 时序仿真，不是 pad / 板级仿真，更不是签核。`T_BOARD` 是 `specs/timing_contract.yaml` 里 TBD 往返项的**占位数**，不是已表征的板级延迟。P0-1 的 28 个 TBD 项一个都没被填掉。

复现：`sh sim/sweep.sh`（走 nix-shell；工具在 PATH 上也可 `IN_LIBRELANE_SHELL=1 sh sim/sweep.sh`）。

## 1. 这一层补了什么

按 checklist §3 的三层划分：

| 层 | 文件 | 回答什么 | 状态 |
|---|---|---|---|
| 1 行为 / 协议 | `sim/sdram_model.sv`、`sim/sdram_checker.sv` | Bank、Row、Burst、命令间隔、数据正确性 | 已有 |
| 2 Timing / Boundary | `sim/sdram_timing_model.sv`（本轮） | tAC/tOH/tHZ/tLZ、tDS/tDH、bit skew、jitter/OCV 占位、总线争用 | 本轮新增 |
| 3 Electrical / Physical | 无 | SPICE / IBIS / 传输线 / 封装 / PVT / SI-PI | 未做 |

两层刻意**独立、可组合**，不合并进一个模型：第二层不实现 Bank/Row/命令解码，它需要 TB 给一个 `launch` 脉冲；第一层继续负责协议正确性。

`sim/read_capture.sv` 是**验证模型，不是可综合 RTL**，也不修改 `rtl/sdr_phy.sv`。它代表 P0-4 才会在 PHY 里实现的"相位可调捕获 FF"。今天的 `rtl/sdr_phy.sv:100` 是 `dfi_rddata <= dq_i` 在 `posedge clk` 上采样、没有任何相位控制，对应本扫描的 `phase = 0`（`delta_capture = 0`）。

## 2. 模型的时间轴

`launch` 在 CK 沿 T0 触发一拍（BL=1）：

```text
T0 + B + T_LZ              DQ 离开 Hi-Z
T0 + B + T_AC + U          DQ = launch_data, data_valid 升起
T0 + B + T_CK + T_OH - U   data_valid 落下（tOH,min 保证结束）
T0 + B + T_CK + T_HZ       DQ 回到 Hi-Z
```

- `B = T_BOARD`：`tCLK,fwd + tDQ,return` 的单数占位。
- `U = T_UNC`：jitter / DCD / OCV 的占位，加到数据到达、从保持保证里扣掉。
- `T_SKEW` 只加到 DQ 最高位；`data_valid` 之外，`read_capture` 还把采到 `X/Z` 判为错。
- 写侧 `tDS/tDH` 由 `always @(phy_dq)` 在绝对时间轴上检查；`contention = model_oe && phy_oe`。
- 延迟是整数 ps（`timescale 1ps/1ps`），所有旋钮是运行时输入端口，**一次编译扫完所有角**。

器件数值来自 `specs/devices/*.yaml`（Micron -75 / ISSI -7 的 AC 表），见 `docs/TIMING_BUDGET.md` §2。

## 3. 扫描设置

- 三个工作点：A = Micron -75 / 100 MHz / CL2（tAC 6.0、tOH 3.0、tCK 10.0 ns）；B = Micron -75 / 133 MHz / CL3（5.4 / 3.0 / 7.5）；C = ISSI -7 / 133 MHz / CL2（5.4 / 2.5 / 7.5）。
- `B` 从 0 到 6000 ps，步进 500 ps；`phase` 在 `[0, tCK)` 内取 31 点。
- 主表用 `U = 0`、`T_SKEW = 0`；两者的效果另见 §5 和变异测试。
- 测量局限：采样选通有 2 ps 固定偏移，`phase` 被截在 `tCK - 50 ps`。所以表里窗口上界在高 `B` 处是**被扫描范围截断的下界**，不是真实上界；相位步进 250–333 ps 也带来一格以内的量化误差。

## 4. 结果

固定相位（`delta = 0`，即当前 `sdr_phy`）的可用边界：

| 工作点 | P0-1 预算 `tCK - tAC` | 扫描里最后一个 PASS 的 B | 第一个 FAIL 的 B |
|---|---|---|---|
| A | 4000 ps | 4000 ps | 4500 ps |
| B | 2100 ps | 2000 ps | 2500 ps |
| C | 2100 ps | 2000 ps | 2500 ps |

**与 P0-1 的一阶预算逐数值吻合**。P0-1 写的是 `M_read,setup = tCK - tAC,max - T_unknown + Δ`；把 `Δ = 0` 代入，`M >= 0` 正好要求 `B <= tCK - tAC`。

各 `B` 下的安全相位窗口（节选，完整输出见 `sh sim/sweep.sh`）：

| B | A: safe phase | A: 固定相位 | B: safe phase | C: safe phase |
|---|---|---|---|---|
| 0 ps | 0 .. 2666 | PASS | 0 .. 2750 | 0 .. 2250 |
| 2000 ps | 0 .. 4666 | PASS | 0 .. 4750 | 0 .. 4250 |
| 4000 ps | 0 .. 6666 | PASS | 2000 .. 6750 | 2000 .. 6250 |
| 4500 ps | 666 .. 7333 | **FAIL** | 2500 .. 7450 | 2500 .. 6750 |
| 6000 ps | 2000 .. 8666 | **FAIL** | 4000 .. 7450 | 4000 .. 7450 |

解析形式（与扫描一致）：

```text
safe_phase = [ max(0, B + tAC + U - tCK),  B + tOH - U ]
width(未截断时) = tCK - tAC + tOH - 2U
```

三条结论：

1. **窗口随 B 线性右移，不是消失。** 宽度约 `tCK - tAC + tOH`（A ≈ 7.0 ns、B/C ≈ 7.5 ns / 7.0 ns）。所以 `B` 变大不是"没救"，而是**必须把采样相位往后挪** `Δ ≈ B - (tCK - tAC)`。这正是 P0-4 要加的 `phase_select` / `capture_delay` 接口；今天 `sdr_phy` 没有这个可控量。
2. **Δ 不是越大越好。** 上界是 `B + tOH`，过了就掉进 hold 违规。表里窗口在 B/C 高 `B` 处被一个 `tCK` 的扫描范围截断；真实上界超出一个时钟周期时，意味着需要额外一拍流水线（`read_latency` 从 `CL+1` 变成 `CL+2`），**那会改 DFI 契约**，不能悄悄加。
3. **tCK 贴着器件下限。** A 的 10.0 ns、B/C 的 7.5 ns 分别是 `tCK(2)` / `tCK(3)` 的 min，颗粒本身没有频率余量；抖动和 DCD 直接吃这个周期。

## 5. 不确定性敏感度（corner A，B = 0）

| U | safe phase | width |
|---|---|---|
| 0 ps | 0 .. 2666 | 2666 ps |
| 500 ps | 0 .. 2333 | 2333 ps |
| 1000 ps | 0 .. 1666 | 1666 ps |
| 1500 ps | 0 .. 1333 | 1333 ps |

每 250 ps 的 `U` 约吃掉 333 ps 窗口（含量化）。`U` 目前只是占位；真实 jitter / DCD / OCV 分布仍属 `t_uncertainty` 这个 TBD 项。

## 6. 负向 / 变异测试

`tb/tb_timing_checks.sv` 7 项全 PASS。只跑好设计不能证明测试环境；这些用例故意注入故障并断言被拒绝：

| 用例 | 检测方 |
|---|---|
| 对照组（正确参数、固定相位、B=0） | 必须通过 |
| `tAC` 抬到 11 ns（> tCK） | `read_capture` 的 `data_valid` |
| `tOH` 压到 0 + 晚采样 | `data_valid` |
| DQ bit skew 拉到一整拍 | `X/Z` 检测 + 数据比对 |
| PHY 与 SDRAM 同时驱动 DQ | `contention` |
| DQ 在 CK 沿后 `tDH/2` 变化 | `in_hold_violation` |
| DQ 在下一 CK 沿前 `tDS/2` 变化 | `in_setup_violation` |

调试中确实抓到两个模型缺陷并修掉：`data_r` 跨拍复用旧值（导致 skew 变异漏检）、争用测试的延时参考点取错（落在 SDRAM 已释放 DQ 之后）。这两处正是 checklist 要求"验证测试环境本身的检测能力"的价值。

## 7. P0-2 的产出与仍未回答的

产出是**设计约束**，不是"固定相位可行"的结论：

- 一旦 P0-3 给出 pad 的 `tCLK,fwd` / `tDQ,return`、P0-5 给出板级延迟，把 `B` 代进 §4 的表即可读出所需 `Δ`，并判断它是否落在一个 `tCK` 内。
- 若 `B` 小于 `tCK - tAC`，固定相位够用；否则第一版就必须带相位控制，或者降到更低频率。

仍未回答：

- `B` 仍是占位；`specs/timing_contract.yaml` 的 28 个 TBD 项、4 个签核 gate 全部保持 open。
- 没有 min/max PVT 配对、没有 jitter/DCD 真实分布、没有封装/PCB/端接、没有 SI/PI、没有 SDF。
- SDC 草稿已由 `generator/emit_sdc.py` 生成但未接入 PnR；`cap_clk` 已在 `rtl/sdram_phy_top.sv` 暴露为接口，`rtl/sdr_phy.sv` 仍在 `posedge clk` 采样 `dq_i`，`Δ` 尚未作用到核心（G6 开放）。多 corner STA 仍未闭合。
- 写路径的 `ck = clk` 问题（`docs/TIMING_BUDGET.md` §5）本轮没有解决，只验证了写侧 `tDS/tDH` 检查器能报违规。

## 8. 不这样做

- 不把 `T_BOARD` 当成已表征的板级延迟，不把 `U` 当成已表征的抖动。
- 不把相位扫描说成 PVT 签核、STA 或电气仿真。
- 不把 `read_capture.sv` 当成对 `sdr_phy` 的修改；`sdr_phy` 仍是固定相位。
- 不把"窗口存在"说成"固定相位可行"——表里 `fixed(delta=0)` 有明确 FAIL 行。
- 不把高 `B` 处被扫描范围截断的窗口上界当成真实上界。
- 不把这一层的通过说成第一层协议检查或第三层物理签核已经满足。
