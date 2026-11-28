# IHP130 DDR1：RX=1.822 ns read capture 与物理 DQS 延迟链接入

日期：2026-11-28  
分支：`ddr1-ihp130`  
范围：100 MHz 数字 + IHP130 pad 边界行为级闭环；不是 gate-level/SDF、综合或后端签核。

## 1. 结论

`PAD_RX=1.822 ns` 在 100 MHz 下已能读回，固定 `sys_clk` capture slot 不再是硬边界。
`ddr_read_capture` 改为 DQS 首沿启动、计满 2 个上升沿 + 2 个下降沿后冻结；
`ddr1_ihp130_io` 里的理想 `assign #(DQS_CAPTURE_DELAY_PS)` 已删除，
替换为修复版 `ddr_dqs_delay_adpll` + 128-tap `DDR1_DQS_DELAY_LINE_PHYS`。

验证结果：

- 行为级 18/18：CK 10/11/12 ns × TT/SS × DRAM read corner -1/0/+1，全部 `DDR1_LOOP_PASS`。
- 带修复版 DQS 线 18/18：TT 9 点、SS 9 点；每点内部扫 read offset 0/±750 ps。
- `ddr_dqs_delay_adpll` 单元测试 `DDR_DQS_DELAY_ADPLL_PASS`。
- `ddr1_top` 训练 TB `DDR1_TRAIN_PASS mode=active taps=17 cycles=10`。
- `ddr1_top` 7-bit tap 端口 Yosys elaboration 通过。

但这仍不是“物理线签核”：仿真里的 `LINE_IMPL=0` 是行为延迟单元，
没有 IHP130 结构化的 `FINE_DELAY_CELL`、没有 routed line/SDF/GLS；
现有 hardened `ddr1_top` ODB 也还是旧 4-bit tap 端口。

## 2. Read capture 改造

文件：`rtl/ddr_read_capture.sv`。

旧结构用 `capture[slot]` 固定 SYS 窗口直接 gate 上升/下降沿计数。SS
`PAD_RX=1.822` 时第 4 个延迟 DQS 边沿落在 203265.152，slot 在 203265 关闭，
只采到 2 rise + 1 fall，`read_frame_good=0`，随后报 `PHY fault read=1 DFI=0`。
把 `DQS_CAPTURE_DELAY` 从 200 扫到 2800 也找不到同时满足“4 沿在窗口内”和
“首拍数据已建立”的点：cap=400 能采 4 沿但首拍是 `00`，读出 `c3fc0300`。

新结构：

- `capture[slot]` 只做 arm，不再作为采样窗口。
- 第一个 rising DQS 边沿才启动 burst；内部 `armed/started` 保持。
- 计满 2 rise + 2 fall 后置 `slot_done` 并冻结计数，后续 burst 不会把计数推到 3。
- `clear_slot` 仍在 slot 释放时清状态；scheduler 和 DFI 返回延迟未改。

这把“第 4 沿必须落在 slot 关闭前”变成“首沿之后计满 4 沿”，因此 RX 从
1.615 增加到 1.822 造成的 207 ps 整体后移不再触发 slot 边界。

## 3. DQS 延迟线接入

### 3.1 Wrapper

文件：`rtl/ddr_dqs_delay_adpll.sv`。

- 由旧的 16 个单 fine cell `PLL_DCDL_TAP_BUS_PHYS` 改为
  `DDR1_DQS_DELAY_LINE_PHYS` consumer wrapper。
- 默认 `LINE_NTAPS=128`、`CELLS_PER_TAP=2`，7-bit code 覆盖 0–5 ns；
  TT 70 ps/tap、SS 122 ps/tap、FF 48 ps/tap。
- 保留 apply-on-idle / `SETTLE_CYCLES` / ack 不重编程的握手。
- 增加 `settled_q`：码值更新 settle 期间 `dqs_capture` 强制低。
- `tap_error` 在 `UPDATE_IDLE=0` 时收到 `tap_valid` 置 sticky。

### 3.2 顶层与 IO

文件：`rtl/ddr1_top.sv`、`rtl/ddr1_ihp130_io.sv`、`rtl/ddr1_phy.sv`。

- `ddr1_top` 默认 `TAP_BITS` 从 4 改为 7；新增 `DQS_TAP_CODE`（默认 9）。
- `TRAIN_ENABLE=0` 时，top 在复位后发一次 `dqs_tap_valid`，收到 line ack 后撤销；
  避免每个 idle 周期重复 apply 同一码值、反复关掉 `dqs_capture`。
- `ddr1_phy` 新增 `read_capture_busy`：由 `slot_busy | capture_frame |
  return_due | read_pipe[1]` 组成。
- `ddr1_ihp130_io` 删除理想 `assign #(DQS_CAPTURE_DELAY_PS)`，实例化
  `ddr_dqs_delay_adpll`，`update_idle = !read_capture_busy && !dqs_oe && !dq_oe`。
- `DQS_CAPTURE_DELAY_PS` 保留为兼容参数，但已不参与逻辑。

100 MHz 工作码值：

| corner | code | cell | 估算延迟 |
|---|---:|---:|---:|
| TT | 9 | 35 ps | 9×2×35 = 630 ps |
| SS | 5 | 61 ps | 5×2×61 = 610 ps |
| FF | 13 | 24 ps | 13×2×24 = 624 ps |

FF 码值只做了线延迟估算，没有跑 FF pad 回归。

## 4. 验证

### 4.1 100 MHz 行为级矩阵

参数：CK=10000/11000/12000 ps；TT=`PAD_TX=1300,PAD_RX=1822,PAD_OE=1500,DQ_OE=-1`；
SS=`1980/1822/2332/1820`；DRAM read corner -1/0/+1；旧临时矩阵 `DQS_CAPTURE_DELAY=600`。
结果 18/18 PASS，日志 `/tmp/m100_matrix.log`。

### 4.2 带物理线回归

`sim/ddr1_ihp130.sh` 已把 SS profile 从旧 `PAD_RX=1615` 改为 `1822`，
SS 默认 `DQ_OE=1820`，并把新 RTL 编进回归。TT/SS 各 3 个 CK × 3 个 DRAM corner：

| profile | PAD_TX/RX/OE (ps) | DQ_OE (ps) | code/cell | CK (ps) | 结果 |
|---|---|---:|---|---|---|
| TT | 1300 / 1822 / 1500 | -1 | 9 / 35 | 10000/11000/12000 | 9/9 PASS |
| SS | 1980 / 1822 / 2332 | 1820 | 5 / 61 | 10000/11000/12000 | 9/9 PASS |

日志：`/tmp/ddr1_phys/tt_reg7.log`、`/tmp/ddr1_phys/ss_reg7.log`。
每个 PASS 行为 `DDR1_LOOP_PASS ck=... offset=... writes=19 reads=21
adjacent=15/15 refresh=3`；每次 run 内部扫 offset 0/±750 ps。

### 4.3 其它检查

- `sh sim/ddr_dqs_delay_adpll.sh` → `DDR_DQS_DELAY_ADPLL_PASS`。
- `tb_ddr1_train`（`TAP_BITS=4` 显式覆盖）→ `DDR1_TRAIN_PASS mode=active taps=17 cycles=10`。
- `yosys hierarchy -check -top ddr1_top; proc; check -assert` 通过（7-bit tap 端口）。

## 5. 限制与未收口

1. **不是结构化的 IHP130 物理线。** `LINE_IMPL=0` 是
   `DDR1_DQS_DELAY_CELL_BEH` 的 `#delay` 链；`LINE_IMPL=1` 需要
   `FINE_DELAY_CELL`，仓库里只有 TB stub，IHP130 后端没有对应结构单元。
   因此没有 routed delay line、没有 line SDF、没有 PVT 后仿。
2. **没有 PVT 跟踪/训练。** 100 MHz 用固定码值（TT 9、SS 5、FF 13 估算）；
   码值来自特征化 cell 延迟，不是硅上测量。`TRAIN_ENABLE=1` 的训练路径没有
   在带物理线的 100 MHz 闭环里重跑。
3. **hardened `ddr1_top` 已过期。** `flow/runs/ihp130-ddr1_top/final` 的
   ODB/SPEF/SDF 仍是 4-bit tap 端口、无物理线；top 现在默认 7-bit，必须重跑
   综合/STA/后端，不能把旧 final 指标当成当前 RTL 的签核。
4. **133/166 未用物理线重跑。** 报告里的 133 TT `cap=500`、SS 1770/1775 ps
   边界仍是理想 `#delay` 结果；修复版线是否改变 5 ps 边界没有证据。
5. **read capture 只有行为级。** 没有 post-route SDF GLS；`dqs_capture` 仍是
   async group，`t_uncertainty` 仍 0.200/0.050。
6. **`DQS_CAPTURE_DELAY_PS` 已废弃。** 旧脚本/旧 TB 传这个参数不会报错，但
   不再改变 DQS 延迟；后续应改用 `DQS_TAP_CODE`/`DQS_LINE_CELL_PS`。
7. **`tap_error` 未上顶层。** IO 内部有 `dqs_tap_error`，但没有引出到
   `ddr1_top` 端口；训练/启动时若违约，仿真只能看内部波形。

## 6. 变更文件

- `rtl/ddr_read_capture.sv` — DQS 首沿 armed、2R+2F、slot_done 冻结。
- `rtl/ddr_dqs_delay_adpll.sv` — 128-tap line wrapper、settle gate、tap_error。
- `rtl/ddr1_dqs_delay_line_phys.v` — 新 line 仓库副本（与 adpll_gen 源同步）。
- `rtl/ddr1_top.sv` — `TAP_BITS=7`、`DQS_TAP_CODE`、one-shot init、`read_capture_busy`。
- `rtl/ddr1_phy.sv` — `read_capture_busy` 输出。
- `rtl/ddr1_ihp130_io.sv` — 删除理想 `#delay`，实例化 DQS wrapper。
- `sim/ddr1_ihp130.sh` — TT/SS 新 profile、物理线 RTL。
- `sim/ddr_dqs_delay_adpll.sh` — 编译新 line。
- `tb/tb_ddr1_ihp130_loop.sv` — 新增 line 参数。

## 7. 下一步

1. 把 `DDR1_DQS_DELAY_LINE_PHYS` 的 `IMPL=1` 映射到 IHP130 可综合结构单元，
   做 line-only 综合/STA，确认 128 tap 的单调性和负载后的步进。
2. 重跑 `ddr1_top` 综合/STA/后端，更新 7-bit tap 端口后的 ODB/SPEF/SDF；
   在此之前不要把旧 final 的 WNS/面积当当前值。
3. 用带物理线的 100 MHz 做 SDF GLS，至少覆盖读 burst 和 delay update idle 窗口。
4. 用物理线重跑 133 TT/SS 边界，确认 5 ps 窗口是否仍成立；166 仍按当前结论
   不成立。
5. 若要上硅，补 PVT 码值表/启动校准，并把 `tap_error` 引到顶层状态寄存器。
