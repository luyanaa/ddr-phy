# IHP130 DDR1 闭环缺口清单（f35b33f）

状态：**数字 RTL 闭环已成立；IHP130 物理闭环尚未成立。**
范围：`LiteDRAMController + LiteDRAMCrossbar -> ddr1_phy -> MT46V32M8-75E 行为模型`。不含 SoC frontend、DIMM、ECC。

## 1. 同步结果

- `origin/master` = `f35b33f`（Merge PR #2 from `luyanaa/ddr1`）。
- 本地 `master` 已快进到 `f35b33f`，与 `origin/master` 同点；`ddr1` 仍在 `9da748b`，`git diff ddr1 origin/master` 为空。
- 合并没有冲突；工作区仍有非 DDR1 的未提交改动（`ci.yml`、`docs/*`、`third_party/t1_ddr2`、`rtl/ddr2_*` 等），本轮未动。

## 2. 已经通过的部分

用 `/tmp/litedram-venv`（migen/litex + PyYAML）跑 `sim/ddr1.sh`：

- CK = 10/11/12 ns × `READ_CORNER` = -750/0/+750 ps，共 9 角全部 `DDR1_LOOP_PASS`：
  `writes=19 reads=21 adjacent=15/15 refresh=3`。
- 生成的是真 LiteDRAM `LiteDRAMController` + `LiteDRAMCrossbar`，不是手写控制器；DFI 固定读延迟 5 在 TB 中逐拍核对。
- 写侧 tDS/tDH、DQS 前后导、tDQSS、读截止、命令间隔、初始化次序都由 TB/模型检查。
- 这是 **RTL + 行为颗粒模型** 的闭环，不是 IHP130 门级或物理闭环。

## 3. 当前回归的两个真实缺陷（testbench 级）

1. `tb/tb_ddr1_train.sv:3` 的 include 结尾用了反引号而不是双引号：
   `` `include "ddr1_timing.vh` ``，Icarus 报 `malformed include directive`。
2. `tb/tb_ddr1_train.sv:151` 只等 10000 个 sys 周期。10 ns CK 下 sys = 20 ns，200 us 上电恰好是 10000 拍，还没算后面的 PRECHARGE/EMRS/MRS/REF 步骤，必然 `DDR1 train init timeout`。

在临时 worktree 中把这两处修成正常 include 和 20000 拍后，9 角闭环和 `mode=active` / `mode=fail` 两个训练模式全部 PASS；仓库本身未改。当前 `sim/ddr1.sh` 会在训练处退出 1，且训练只在 CK=10 ns 跑。

另外，`f35b33f` 的 `.github/workflows/ci.yml` 里没有 DDR1 job；本地未提交的 `ci.yml` 才加了 `sh sim/ddr1.sh`。README 写“CI 跑 DDR1 Native 闭环”，与实际提交不一致，所以这个训练失败目前不会在远端 CI 暴露。

## 4. 闭环缺口

### P0：pad 不在数字闭环里

- `rtl/ddr1_top.sv` 的边界是裸数字引脚：`dq_i/dq_o/dq_oe/dm/dqs_o/dqs_oe/pad_ck/pad_ck_n`，没有实例化任何 IHP130 pad。
- 文件头自己写明：board/PDK supplies settled CK/sys/CK90、delayed receive DQS、SSTL-2 drivers。`specs/interface.yaml` 也写 `pads: Logic-only ... SSTL-2, receiver delay and clock/power supervision belong to the backend`。
- IHP130 现有 `sch/pads/ihp130/sstl2_dq.spice` 只是单 DQ 晶体管级原型，没有 Verilog/Verilog-A 行为模型，也没有进 `tb_ddr1_loop`。
- 一个 x8 接口至少需要 32 个信号 pin：8 DQ、1 DQS、1 DM、2 CK/CK#、13 A、2 BA、CKE/CS#/RAS#/CAS#/WE# 各 1；再加 VREF 和 VDDIO/VSSIO/VDD/VSS。当前只有 1 条 DQ + 1 个 VREF pad。
- 缺 DQS/DM/CK/CK#/地址/命令各信号类的 SSTL-2 pad，缺 x8 lane array、pad ring、共享电源钳位、封装焊盘开口。
- 没有 VREF/VTT 板级网络；pad 表征负载是 50 Ω 到独立 VTT + 5 pF，不是封装/PCB。

### P0：ck90、读 DQS 延迟没有片上实现

- `ddr1_top` 的 `ck`、`ck90`、`dqs_capture` 都是输入；`ddr1_phy` 注释直接说 backend 供时钟和“received DQS delayed into the DQ eye”。
- `docs/ARCHITECTURE.md` 明确写“DDR1 的 `ck90` 是空的”：ADPLL 没有第二相位；`/grid/adpll_gen/src/ddr_clock_phy.v` 的 `CK_PHY_N` 是反相，不能当 CK90；固定速率候选（同源双边沿分频出 CK0/90）还没有核定根时钟、复位相位、布线后偏差和失锁停流。
- `rtl/ddr_dqs_delay_adpll.sv` 存在，但没有在 `ddr1_top` 里实例化；它依赖 `/grid/adpll_gen/src` 的 `PLL_DCDL_TAP_BUS_PHYS`，`sim/ddr_dqs_delay_adpll.sh` 只做通用/ICS55 展开，没有 IHP130 延迟单元映射。
- 顶层也没有 `update_idle` 端口，而 `ddr_dqs_delay_adpll` 的 tap 更新需要它；训练用的 `dqs_tap_valid/value/ready` 目前只是把码值交给外部延迟线，芯片内没有 code-to-delay 校准。
- `ddr_dqs_train` 只做数字 tap 搜索；真实延迟线的步进、非线性、温漂、PVT 和 DQS 高阻时的接收器行为都未表征。

### P1：IHP130 pad 后版图时序没有收口

- 原理图级 `results/ihp130/sstl2-dq.em6sOCDP/vtt*.json`：7 PVT × 3 VTT 全部 PASS，最坏传播约 1.476 ns（限 1.5 ns），`signoff=false`。
- 布线后 PEX `results/ihp130/sstl2-dq-route-eco/pex_tt.json` TT PASS；但 `pex_ss_low.json` 在 SS/125 °C/2.3 V/VTT+40 mV 下 FAIL：
  RX rise/fall = 1.614825 / 1.967438 ns，TX rise/fall = 1.865439 / 2.200611 ns，均超过 1.5 ns。OE 2.462/2.332 ns 虽在 2.5 ns 内，但余量很小。
- `docs/PAD_GENERATOR.md` 写明版图 `XRDRIVER` 仍是 W/L = 8/0.60 µm，而 `ddr1-tune-20261126.json` 推荐 `xrdriver_w=12 µm, xrbias_l=13 µm`。也就是说 PEX 并不是推荐尺寸的版图；即使按 12 µm 重画，SS 下 RX 比较器和预驱动延迟仍需重新设计，不能按 1.5 ns 预算直接复制 x8。
- 2.5 V 工作点用的是 IHP 3.3 V HV 器件；foundry I/O 角是 3.0/3.3/3.6 V，不证明 2.3–2.7 V 的 SSTL-2 兼容性。这是工艺电压边界，不是已签核的 2.5 V IO。
- 单 DQ 宏的 DRC/LVS/PEX 只覆盖一个 lane；没有 x8 的 DRC/LVS/PEX，也没有 pad ring/密封环/芯片级密度。

### P1：没有 IHP130 数字后端与 DDR1 STA

- 没有 IHP130 的 synthesis/PnR/CTS/STA/SDF 门级回归；`sim/ddr1.sh` 是 RTL + 行为模型，10/11/12 ns 只覆盖模型角。
- 没有 source-synchronous DQ/DQS、CK/CK# 输出、读捕获窗口的 SDC；没有 post-route skew、OCV、SI 约束。
- 1.2 V core 与 2.5 V VDDIO 的电平搬移只在 DQ pad 宏里；地址/命令/CK 输出 pad 也需要各自的电平搬移和预驱动，当前没有。
- 没有电源域上电顺序、PU_OK 全芯片分配、VDDIO/VSSIO 回流和 IR-drop 证据。

### P1/P2：外部颗粒模型不是厂商模型，覆盖也有限

- `sim/ddr1_device_model.sv` 是 clean-room 行为模型，头部写明“not a datasheet timing checker”；存储是 1024 个 sparse byte slot，不是完整 32 MB 阵列，超过就 `MEM_FULL`。
- 只覆盖 x8、单 rank、BL4、CL2、顺序突发、显式 precharge；不支持 BL8、CL3、auto-precharge、DLL off 等模式。
- 没有 DDR1 厂商模型差分；现有 `sim/micron_diff.sh` 用的是 SDR 的 `mt48lc16m16a2`，不是 MT46V32M8。
- `sim/ddr1_timing_checker.sv` 只查命令间隔；读方向的 tDQSCK 逐周期抖动、tAC/tOH/tHZ/tLZ、读眼图、SSO/PDN 没有独立检查。当前 `read_offset_ps` 是静态角，不是随机/逐 burst tDQSCK。
- 没有全阵列保持/刷新压力；循环只写 19 次、读 21 次，覆盖同一行、跨 bank、跨行和掩码，不是 full-memory retention。

### P2：训练与板级/SI 覆盖窄

- 训练只在 CK=10 ns、`LANES=1`、固定 `TRAIN_ADDR=23'h7fffff` 跑 mode 0/1；TB 的 16-tap 延迟线是行为模型，不是真实延迟线。
- 没有 per-bit skew、多 lane、PVT/温度/电压 droop、延迟线非线性/温漂；没有写 DQS/CK 输出的 margining，也没有读 DQS gate。
- 没有封装 RLC、IBIS、50 Ω 走线、VTT 端接、VREF 去耦、串扰/SSN/PDI；这些可以把“数字窗通过”变成“引脚处不通过”。

### P2：证据/CI 卫生

- `reports/capability_report.md` 里 IHP130 仍是 **NO_GO**，open gates `G1,G2,G4,G5,G6`；`signoff=false` 未变。
- 已接受的层次化 LVS、当前 ESD/latch-up、hold 的 `t_uncertainty` 不改变这些 formal flag；能力的正式状态仍是 NO_GO。
- 提交版 CI 没有 DDR1 job；本地未提交的 CI 才加，且加进去会立刻暴露上面的训练 TB 失败。

> **2026-11-27 更新**：本文件第 4 节“版图 XRDRIVER 仍是 8/0.6 µm”是历史状态。W12 实验版和 `ddr1_top` 真实 SDC 的中间结果见 `reports/ddr1/ihp130-w12-pad-sdc-20261127.md`；W12 仍未过 SS PEX 1.5 ns，`ddr1_top` setup 余量只到 +75.35 ps，不能按已闭合处理。

## 5. 建议的最小收口顺序

1. 修 `tb_ddr1_train.sv` 的 include 和 init timeout，提交 CI 的 DDR1 job，让 `sim/ddr1.sh` 在远端变绿。
2. 做“pad-in-loop”行为级闭环：先给 `ihp130_sstl2_dq` 一个带 RX/TX 延迟、OE、VREF、上电 Hi-Z 的 Verilog 模型，实例化 1 lane，跑同一套 LiteDRAM 闭环；再扩到 8 DQ + DQS/DM/CK/CA。
3. 把 `ddr_dqs_delay_adpll` 接进 `ddr1_top`，补 `update_idle`，给 IHP130 做延迟单元映射和 code-to-delay 表征；训练改为控制这条内部延迟线。
4. 明确 `ck90` 的来源：第一版测试片可以继续用板级/外部 CK90，但要在顶层和文档里标成板级假设；若要片上产生，走固定速率同源分频/DLL，先解决复位相位、post-route skew 和失锁停流，不能用 `CK_PHY_N`。
5. 按推荐 12 µm 重画 IHP130 DQ，先修 SS 下 RX/TX，再做 x8 pad ring/DRC/LVS/PEX；最后才谈 IHP130 门级 STA/SDF。

## 6. 按当前决定不算本轮阻塞的项

- 层次化 LVS：已接受，不再要求 full-chip flat LVS。
- ESD/latch-up：接受当前 SPICE + DRC 规则水平，不再要求 TLP/HBM/CDM 资格。
- `t_uncertainty`：先 hold，由用户后续解决。

这三项不阻塞“数字+行为 pad”的联合仿真；但不要把它们的接受状态写成 IHP130 DDR1 已经物理签核。
