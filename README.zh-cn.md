# ddr-phy

面向 [LiteDRAM](https://github.com/enjoy-digital/litedram) 控制器的外部 DRAM ASIC PHY，覆盖四套开源 PDK：**sky130、gf180mcu、IHP SG13G2（130 nm）、ICsprout 55**。控制器沿用 LiteDRAM，不改它的调度、刷新和交叉；本仓库做可综合的数字 PHY 和手工 I/O pad。四套工艺共用同一套数字 PHY 和同一张 pad 原理图，换的是器件和电源，不是四套架构。

设计决策、证据边界和分期计划的权威记录在 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 设计分类

| 类 | 存储器 | 接口 | 工艺 | VDDIO | 状态 |
|---|---|---|---|---|---|
| S | SDR SDRAM | 与 `GENSDRPHY` 相同的 DFI，1:1 | 四套全做 | 3.3 V | 数字核已实现并通过多层验证 |
| D | DDR1 | 新写的 1:2 DFI | sky130、IHP、ics55 | 2.5 V | 规划中，RTL 未开始 |
| D2 | DDR2 | LiteDRAM DDR2 DFI，1:2，带 ODT | 仅 55 nm（需自研 SSTL_18 IO） | 1.8 V | 远期 |

第一版硅目标是点对点一颗 x8，SDR 的 CK = 100 MHz。不做 DIMM、fly-by、写电平；SPD 和 ECC 不在 PHY 里。

## 当前进展（P0）

Class S 数字侧已经有的东西：

- `rtl/sdr_phy.sv` — 1:1 SDR PHY，`GENSDRPHY` 的可综合翻译：写延迟 0，读延迟 CL+1，命令/DQ/DM 各一级寄存器，三态驱动留给 pad。
- `rtl/sdram_phy_top.sv` — 集成顶层：CK 走 `clock_forward` 专用路径，DQ 走 `dq_turnaround` + `phy_io_adapter`，读捕获第一级 FF 由 `read_capture_ctrl` 的 `cap_clk` 时钟。
- `rtl/sdr_ctrl.sv` — 闭环用的 1:1 控制器（不是 LiteDRAM 网表），抄 `GENSDRPHY` 的 DFI 时序和初始化命令顺序；WRITE 受 PHY `turnaround_busy` 门控；可选 tREFI 刷新。
- `rtl/sdr_bist.sv` — PRBS-8 写读比对 BIST，可选 `phase_sel` 扫描。诊断辅助，不是时序签核，也不实现 DRAM 训练。
- `rtl/read_capture_cdc.sv`、`rtl/dq_turnaround.sv`、`rtl/clock_forward.sv`、`rtl/phy_io_adapter.sv` — 读捕获 CDC、读写转向守护、时钟转发、pad 适配。

验证与实现证据（分层，不越级）：

1. **DFI 行为**：`tb/tb_sdr_phy.sv`，CL 2/3 × x8/x16 通过。
2. **引脚级闭环**：`sim/sdram_model.sv` + `tb/tb_sdr_loop.sv`，行命中、换 bank、换行、掩码写、BL 2/4/8 突发通过。模型只报命令顺序错误，不测 tRCD/tRP/tRAS/tRFC。
3. **命令间隔**：`sim/sdram_checker.sv`，按 Micron 256Mb SDR -75 档（tCK = 10 ns）数时钟，每条规则一个实例。
4. **时序感知读捕获**：`sim/sdram_timing_model.sv` + `sim/read_capture.sv`，相位扫描与负向测试（`sim/sweep.sh`）；静态 phase 0/1/2 测试（`tb/tb_read_capture_phase.sv`）。
5. **门级功能**：`sim/gate.sh` 把 `sdr_phy` 映到 sky130 HD 跑功能仿真。无 SDF、无线延迟、无 pad——不是时序仿真，更不是签核。
6. **物理实现**：`flow/` LibreLane，sky130 控制组 80/80 跑通；草稿 SDC 故意未接入（见 `docs/STA_PLAN.md` §5）。
7. **pad**：`generator/` 产出四套工艺的拓扑模板（`sch/pads/`），gf180mcuD / sky130 / IHP 已绑定器件并生成；已有预驱动+输出级/接收器切片和 ESD 反向泄漏的 ngspice 仿真，标为 `design_assumption`。ics55 缺 3.3 V ESD 二极管 SPICE 卡（`docs/ICS55_ESD_3V3.md`）。尺寸未签核。
8. **可选差分**：`sim/micron_diff.sh` 对 Micron MT48LC16M16A2 行为模型做差分测试；模型本地获取、不随仓库分发，缺席时自动跳过。

CI（`.github/workflows/ci.yml`）跑生成器检查、产物一致性、全部 RTL/模型回归、退出码变异测试（`sim/mutation.sh`，证明 FAIL 的测试台真的返回非零）和可选 Micron 差分。

## 目录结构

```text
rtl/            可综合 SystemVerilog：PHY、控制器、BIST、读捕获、转向、时钟转发、pad 适配
tb/             测试台（Icarus Verilog，-g2012）
sim/            行为/时序模型、检查器、回归脚本、门级网表壳
generator/      Python 生成器与证据检查：pad 拓扑、器件抽取、PDK 规则、时序、封装
specs/          接口契约（interface.yaml）、时序契约（timing_contract.yaml）、器件与 pad 规格
sch/pads/       生成器产出的 pad 拓扑模板与封装 profile 闭合产物
backends/       各 PDK 后端配置（sky130 / gf180mcu / ihp130 / ics55 / generic_sim）
flow/           LibreLane 硬化流程（run.sh、config、SDC 草稿）
docs/           架构与专题文档（中文）
third_party/    litedram（submodule，不改）；reference/（本地评估模型，不分发）
results/        物理实现产物（gitignore）
```

## 快速开始

依赖：Icarus Verilog、Yosys、Python 3 + PyYAML。物理流程另需 LibreLane 环境（脚本会自动进 `/opt/librelane` 的 nix-shell）和对应 PDK。

```sh
# 基础回归：DFI 行为、引脚级模型、控制器闭环、命令间隔检查
sh sim/run.sh

# 增强 PHY 模块、DQM 读掩码、BIST 闭环（x8 / x16）
sh sim/phy.sh

# pad 能力报告 + pad 适配契约测试
sh sim/pad.sh

# 时序感知读捕获相位扫描 + 负向测试
sh sim/sweep.sh

# 退出码变异测试：注入错误必须让仿真器非零退出
sh sim/mutation.sh

# 可选：Micron 参考模型差分（模型缺席时跳过，获取方式见 docs/DRAM_MODEL_REFERENCES.md）
sh sim/micron_diff.sh

# sky130 HD 功能门级（无 SDF）
sh sim/gate.sh

# 生成器与证据检查
python3 generator/check_pads.py
python3 generator/check_capabilities.py
python3 generator/check_timing.py

# LibreLane 硬化：sky130（默认）/ ihp130 / ics55 / gf180-as-7t3v3
sh flow/run.sh sky130
```

gf180 必须用 3.3 V AS 标准单元视图（先在 `./pdks/gf180mcuD` 组好）；foundry 的 5 V 单元库不是本 PHY 的规格。

## 文档

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — 架构决策、DFI 契约、手工 I/O 分工、验证分层、分期与缺口
- [PHY_RTL_GAPS.md](docs/PHY_RTL_GAPS.md) — RTL 已知缺口
- [STA_PLAN.md](docs/STA_PLAN.md) / [TIMING_BUDGET.md](docs/TIMING_BUDGET.md) / [TIMING_SWEEP.md](docs/TIMING_SWEEP.md) — 时序约束与预算
- [PAD_GENERATOR.md](docs/PAD_GENERATOR.md) / [PAD_ADAPTER.md](docs/PAD_ADAPTER.md) — pad 生成器与适配契约
- [ESD_STRESS_PLAN.md](docs/ESD_STRESS_PLAN.md) / [ICS55_ESD_3V3.md](docs/ICS55_ESD_3V3.md) — ESD 计划与 ics55 3.3 V 缺口
- [DRAM_MODEL_REFERENCES.md](docs/DRAM_MODEL_REFERENCES.md) — DRAM 参考模型的来源与许可边界
- [SI_PI_PACKAGE_PCB.md](docs/SI_PI_PACKAGE_PCB.md) / [PACKAGING_PROFILES.md](docs/PACKAGING_PROFILES.md) — 封装与板级

## 许可

本仓库源码采用 **Apache-2.0**（见 [LICENSE](LICENSE)，源文件带 SPDX 头）。第三方材料各有边界：

- `third_party/litedram` 是 submodule，BSD 许可（EnjoyDigital），本仓库不修改它。
- Micron MT48LC16M16A2 行为模型为 "All rights reserved"，**不随仓库分发**，仅本地评估使用（已 gitignore）。
- ICsprout 55 foundry SPICE 模型是厂商数据，不在 Apache-2.0 之内，只供教学和研究评估；用它做的仿真不构成签核，也不能当可再发布的 PDK 附件。
- JEDEC 标准正文不在本仓库；时序默认值来自公开的颗粒数据手册二次资料，出处见架构文档。