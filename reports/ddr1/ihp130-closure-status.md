# DDR1 / IHP130 闭环状态报告

日期：2026-11-27
基线：`f35b33f`（`origin/master`，已合并 DDR1）
范围：`ihp130 pad -> 数字后端 -> 颗粒模型 -> testbench fix -> LiteDRAM 闭环`

## 1. 结论摘要

本轮把 DDR1 数字闭环、pad 边界行为闭环、IHP130 `ddr1_phy` 首次数字后端、32 MiB 颗粒模型和 CI 入口都推进到了可复跑状态。仍有三个明确的未闭合项：SS pad 在 10/11 ns 写 tDS 不通过；数字后端只是 bring-up harden，不是 DDR1 signoff；没有厂商 MT46V32M8 模型差分。

## 2. Testbench 修复与 LiteDRAM 闭环

- `tb/tb_ddr1_train.sv`：修正第 3 行 include 的结尾反引号；init 等待从 10000 改为 20000 个 sys 周期，覆盖 200 µs 上电。
- `sim/ddr1.sh`：CK 10/11/12 ns × `READ_CORNER = -1/0/+1` 共 9 角全部 `DDR1_LOOP_PASS`。
- training：`DDR1_TRAIN_PASS mode=active taps=17 cycles=10`；`mode=fail taps=16 cycles=387`。
- 脚本使用生成的 `LiteDRAMController`、`ddr1_top`、`ddr1_device_model` 和 `ddr1_timing_checker`，是 LiteDRAM -> DDR1 PHY -> 颗粒 的 RTL 数字闭环。

## 3. IHP130 pad 边界

新增：

- `rtl/ihp130_sstl2_dq_model.sv`：数字行为 pad，带 TX/RX/OE 延迟、三态和 `PAD_OE`。
- `rtl/ddr1_ihp130_io.sv`：x8 DQ + DQS + DM + CK/CK# + A/BA/CKE/CS/RAS/CAS/WE 的 pad 边界 wrapper。
- `tb/tb_ddr1_ihp130_loop.sv`：pad 边界 loop TB，写时序检查使用 `PAD_DQ/PAD_DQS/PAD_DQS_OE`。
- `sim/ddr1_ihp130.sh`：`PAD_PROFILE=tt|ss` 的 9 角脚本。

结果：

- **TT PEX**（TX/RX = 1300 ps，OE = 1500 ps）：CK 10/11/12 ns × offset -750/0/+750 ps 共 9 角全部 `DDR1_LOOP_PASS`。
- **SS PEX**（TX = 1865 ps，RX = 1615 ps，OE = 2332 ps）：
  - CK = 12 ns 的 3 个 offset 全部 `DDR1_LOOP_PASS`。
  - CK = 10/11 ns 的 6 个运行全部在第一次写 DQS 边沿报 `DDR1 write tDS violated`；10 ns 角 DQ 变化距 DQS 边沿只有 168 ps（202796865 ps）。
  - 这是当前 PEX SS pad/`ck90`/DQS OE 组合的真实边界，不是 TB 误报。

## 4. IHP130 数字后端

新增：

- `flow/config.ddr1_phy.json`
- `flow/ddr1_phy.sdc`

LibreLane IHP130 `sg13g2_stdcell` 对 `ddr1_phy` 做独立 harden：综合、布局、CTS、布线、RCX、STA、Magic/KLayout DRC、Netgen LVS、天线检查。最终一次运行（包含 `ddr_read_capture.sv` 的字节序修正）：

- Setup WNS：**+0.0078 ns**（最差角 `nom_slow_1p08V_125C`）。
- Hold WNS：**+0.1376 ns**（最差角 `nom_fast_1p32V_m40C`）。
- DRC：0；LVS：0；天线：0。
- 标准单元面积：**36,233.6 µm²**；标准单元实例：**1,825**；die 面积：**103,783 µm²**。
- 典型角总功耗：约 **4.411 mW**。
- 生成视图在 `results/ihp130/ddr1_phy/`。

边界说明：

- SDC 是 bring-up 约束，不是 DDR1 signoff：`sys_clk/ck/ck90/dqs_capture` 目前按异步 clock group 处理；输出/输入 delay 是核心边界占位值，不是 pad/PCB 实测值。
- `ddr_read_capture.sv` 的双沿捕获用 posedge/negedge 两个 always 块；综合映射成正/负沿触发器，真实 DDR 输入仍需要 IDDR/硬宏或 2x 时钟方案。
- 该 harden 不含 pad ring、电平搬移、VDDIO/VSSIO、封装和板级 SI/PI。
- 为绕过 Verilator 对双沿捕获的 `MULTIDRIVEN` 误报，`config.ddr1_phy.json` 设了 `RUN_LINTER=false`；这只是后端 bring-up，不是 lint 签核。

## 5. 颗粒模型增强

`sim/ddr1_device_model.sv`：

- 用完整 **32 MiB** 阵列 `mem[0:33554431]`（`{bank,row,column}` 直接索引）替换原来的 1024 个 sparse byte slot；不再有 `MEM_FULL` 上限。
- 新增运行时参数：
  - `READ_DQS_JITTER_PS`：DQS 边沿相对标称 tDQSCK 的逐 burst 偏移。
  - `READ_DQ_SKEW_PS`：DQ 逐 bit 飞行 skew（bit 7 为 7 倍值）。
  - `READ_SSO_PS`：每个同时翻转 bit 的额外 DQ 延迟。
- 默认值均为 0，原有 9 角回归不受影响。

`sim/ddr1_read_eye.sh` 结果：

- `J0`（全 0）pass。
- `J2000`（DQS jitter 2000 ps）pass。
- `S500`（逐 bit skew 500 ps）fail，读回数据错位。
- `SSO300`（每翻转 bit 300 ps）fail，读回数据错位。

这提供了读方向 jitter/skew/SSO 的可重复入口，但仍不是 JEDEC/PVT 签核，也没有厂商 MT46V32M8 模型差分。

## 6. CI

- `.github/workflows/ci.yml` 工作区版本新增：
  - `sh sim/ddr1.sh`（原生 LiteDRAM 9 角 + training）。
  - `sh sim/ddr1_ihp130.sh`（pad 边界 TT 9 角）。
  - `sh sim/ddr1_read_eye.sh`（读眼 jitter/skew/SSO）。
- 提交版 `f35b33f` 仍没有 DDR1 job；本轮改动未提交。

## 7. 未闭合项

1. **SS pad 10/11 ns 不通过**：第一次写 DQS 边沿的 tDS 只有 168 ps。需要重画推荐尺寸 pad、或重新分配 `ck90`/DQS OE 相位；不能按当前 PEX SS 直接做 100 MHz x8。
2. **数字后端不是 signoff**：异步 clock group、占位 I/O delay、双沿捕获、无 pad ring、无封装/板级 SI/PI；setup 余量只有 7.8 ps。
3. **颗粒模型不是厂商模型**：32 MiB 全阵列和读眼 knobs 已加，但没有 MT46V32M8 厂商模型差分；读 AC/jitter/SSO 仍是行为入口。
4. **`adpll_gen` 需求已交维护者**，本轮没有实现 `ck90` 或 DQS 延迟线；`ddr_dqs_delay_adpll` 仍未实例化进 `ddr1_top`。
5. **已提交/推送**：本轮 DDR1/IHP130 结果在 `036faa6`（分支 `ddr1-ihp130`）；封装/padring 新工作仍在工作区，见第 10 节。

## 8. 本轮涉及的文件

新增：

- `rtl/ihp130_sstl2_dq_model.sv`
- `rtl/ddr1_ihp130_io.sv`
- `tb/tb_ddr1_ihp130_loop.sv`
- `sim/ddr1_ihp130.sh`
- `sim/ddr1_read_eye.sh`
- `flow/config.ddr1_phy.json`
- `flow/ddr1_phy.sdc`
- `reports/ddr1/ihp130-closure-status.md`（本文件）

修改：

- `rtl/ddr_read_capture.sv`：posedge/negedge 分成独立数组和 always 块，保持原字节序。
- `tb/tb_ddr1_train.sv`：include 引号、20000 拍 init timeout。
- `tb/tb_ddr1_loop.sv`：增加读眼参数并传给颗粒模型。
- `sim/ddr1_device_model.sv`：32 MiB 全阵列、读眼 knobs。
- `.github/workflows/ci.yml`：DDR1 pad/read-eye step。

## 9. 复跑命令

```sh
cd /grid/ddr-phy
PYTHON=/tmp/litedram-venv/bin/python sh sim/ddr1.sh
PYTHON=/tmp/litedram-venv/bin/python sh sim/ddr1_ihp130.sh
PAD_PROFILE=ss PYTHON=/tmp/litedram-venv/bin/python sh sim/ddr1_ihp130.sh
PYTHON=/tmp/litedram-venv/bin/python sh sim/ddr1_read_eye.sh
PATH=/nix/var/nix/profiles/default/bin:$PATH TOP=ddr1_phy sh flow/run.sh ihp130
```


## 10. 封装/padring 第一轮（2026-11-27）

新增 `docs/PACKAGE_PADFRAME_PLAN.md`、`results/ihp130/package/`、`generator/extract_qfn_rlc.py`、`spice/package/qfn40_pkg.spice`。

结论：

- 全 x8 DDR1 的 32 根 signal + 7 根 power/reference 至少需要 QFN40 6x6；QFN24/28/32 不够。QFN48 7x7 是更稳的推荐。
- 用 IHP AMS template 的 `run_bondplan.py` 在 2.0 mm × 2.0 mm、40 pad coupon 上生成 QFN40 bondplan：线长 1771–2459 µm，一阶 L 1.85–2.69 nH、R 0.094–0.128 Ω、C 0.1 pF；50 Ω 的 L/R 上界 37–54 ps。
- IHP template 的 QFN32 参考线长 1296–1701 µm，L 1.31–1.77 nH，R 0.070–0.091 Ω。
- Open-Padrings 32 的 pad→core SPEF 为 370–492 Ω / 0.050–0.086 pF；这是数字 padframe 的窄 route，不能直接拿来做 30 mA SSTL-2 padring。
- 封装 + 参考 padring 的保守上界约 56–96 ps，仍小于 SS 10/11 ns 的 168 ps tDS 违规；当前失败主因仍是 pad TX/OE 与 DQS 捕获，不是封装。

状态仍是 `signoff=false`。下一步是先冻结 QFN40/QFN48 与 pinout，再做 40-pad SSTL-2 ring 和真实 PEX。
