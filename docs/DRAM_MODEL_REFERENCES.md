# 外部 DRAM 模型参考资料目录

状态：**本地 import 一个 Micron SDR 模型（仅供评估，不入库），并增加可选的差分运行；其余全部只作参考索引。**
本仓库的 `sim/sdram_model.sv` 仍是自己写的 Apache-2.0 行为模型，没有被任何外部模型替换。与 `docs/ARCHITECTURE.md` §7 / §11 的许可纪律一致：源码不抄、许可未核对的不写"已核实"。

## 1. 本次 import 的模型

| 项 | 值 |
|---|---|
| 来源 | `https://github.com/juliusbaxter/mor1kx-dev-env/blob/master/bench/verilog/mt48lc16m16a2.v` |
| 文件 | `third_party/reference/mt48lc16m16a2.v`（**gitignored，不提交**） |
| SHA256 | `a981dd64039d5d118e45c6ac61ff0cbc9cdfa7f973fe0a968f7bd5df894d7425` |
| 规模 | 1242 行 / 50467 字节 |
| 版本 | MT48LC16M16A2.V v2.1，2002-06-06，BUS Functional，原面向 Model Technology |
| 器件 | Micron 256Mb SDRAM，4Meg x 16 x 4 Banks |
| 头部限制 | `Doesn't check for 8192 cycle refresh`；要求仿真精度设为 ps |

复现命令：

```sh
curl -sSL 'https://raw.githubusercontent.com/juliusbaxter/mor1kx-dev-env/master/bench/verilog/mt48lc16m16a2.v' \
  -o third_party/reference/mt48lc16m16a2.v
```

### 1.1 许可评估与决定

文件头原文要点：

```text
Disclaimer: THESE DESIGNS ARE PROVIDED "AS IS" WITH NO WARRANTY WHATSOEVER ...
Copyright (c) 2001 Micron Semiconductor Products, Inc.
All rights reserved
```

这是一个**仅含免责声明的 "All rights reserved" 版权头，没有任何再分发授权**。把它提交进 Apache-2.0 仓库会与项目许可冲突，也和 `docs/ARCHITECTURE.md` §7 里"GPL-3.0 代码不进本仓库""许可未核对"的做法相悖。

因此：

- 文件落在 `third_party/reference/` 并在 `.gitignore` 明确排除，**只在本机用于评估**；
- 不进 git、不进 `rtl/`、不进 `sim/`、不参与 `sim/run.sh`；
- 若要正式用于验证，需先向 Micron 确认再分发权（`modelsupport@micron.com`），或改用许可证明确的模型。

### 1.2 依赖与本地验证

模型 `include` 两个文件：`timescale.v`、`test-defines.v`。上游在同路径返回 404，因此本地补了两个**我们自己写的**占位文件（`third_party/reference/timescale.v` 只提供 ps 精度的时间单位指令；`test-defines.v` 只有注释，不注入任何宏）。模型自身的 `ifdef` 只用 `MT48LC*` / `INIT_CLEAR_MEM_BANKS` / `PRELOAD_RAM`，都在文件内定义。

已用 Icarus `-g2012` 通过精化和 §3.4 的集成 PHY 差分回归；未用该模型的时序参数做签核。

### 1.3 重要发现：它的时序参数不是我们的 -75 档

模型内部参数（`mt48lc16m16a2.v` 约 165–176 行）与本仓库 `specs/devices/micron_mt48lc16m16a2-75.yaml` 对比：

| 参数 | 模型值 (ns) | 本仓库 -75 值 (ns) | 判定 |
|---|---|---|---|
| tRCD | 15 | 20 | 不同档 |
| tRP | 15 | 20 | 不同档 |
| tRAS | 37 | 44 | 不同档 |
| tRC | 60 | 66 | 不同档 |
| tRRD | 14 | 15 | 不同档 |
| tWR (manual) | 14 | 15 | 不同档 |
| tRFC | 66 | 66 | 一致 |
| tAC | 5.4 | CL2=6.0 / CL3=5.4 | 只对得上 CL3 |
| tOH | 3.0 | 3.0 | 一致 |
| tHZ | 5.4 | CL2=6.0 / CL3=5.4 | 只对得上 CL3 |

模型的 tRCD/tRP/tRAS/tRC/tRRD/tWR 对应 **Micron -7E / 133 MHz 档（或 ISSI -7 档）**，不是 `-75`；`tAC=5.4` 对应 CL3，而本项目的 100 MHz 基线是 CL2 的 `tAC=6.0`。而且 tRFC=66 又与 -75 一致，属于混合参数。

**结论：这个模型不能作为本项目 -75 Timing Contract 的数值来源，也不能直接拿它的通过结果说"我们的 PHY 时序对了"。** `sim/sdram_checker.sv` 头部"不要把 Micron 与 ISSI 两张表混用"的告诫，在这里同样适用。

## 2. 各厂商 SDRAM / DDR1 / DDR2 模型目录

以下为本次检索到的获取渠道；"未核对"表示没有读到该厂商的许可原文，不写成已核实。

| 厂商 | 模型类型 | 获取渠道 | 许可 / 限制 |
|---|---|---|---|
| Micron | SDR / DDR / DDR2 / DDR3 / DDR4 Verilog 行为模型；IBIS (`.ibs`)；HSpice；DIMM EBD (`.ebd`)、DML、ICX、HyperLynx | 各 part detail 页的 Download Sim Model；`modelsupport@micron.com`；TN `Accelerate Design Cycles with Micron Simulation Models` | 部分条目显示 `Get Access` 需账号；行为模型头部为 All rights reserved；EBD 因模块型号太多**按需申请** |
| Micron（IBIS 性质） | `.ibs` 为 V/I、V/T 曲线，不含器件内部专有信息 | Micron FAQ | 官方说明"IBIS 文件通常不需要签 NDA"；HSpice 由实际电路导出，IBIS 由 HSpice 导出并一致性校验 |
| Micron（板文件） | EBD / ODB++ / 电路板文件 | Micron FAQ | 电路板文件含模块机密设计信息，**无 NDA 不提供**；Gerber 一词常被混用，要先确认客户到底要 EBD 还是 ODB++ |
| ISSI | SDR SDRAM 的 IBIS（按封装分 TSOP / BGA），产品页逐型号列出 | `issi.com` SDR SDRAM 产品页 | 页面写明 `Simulation Models not listed above may be available upon request`；Verilog 模型未在公开页列出 |
| Samsung / SK hynix | IBIS | 各自 support 页面（二手资料称需注册） | 本次未逐一核对许可，**标为未核对** |
| Nanya | — | 本次检索未命中 | 未核对 |
| Winbond | Verilog / IBIS | 搜索命中其 W25N SPI NAND 等器件的模型页 | **不是 SDR/DDR DRAM 模型**；不能拿来当 DRAM 参考 |
| 开源替代 | MIT `SDRAM_Controller.v`（TheSonders，MT48LC16M16A2P-75，CL3@133）；GPL-3.0 `sdram.v`（Sorgelig / MiSTer）；checklist 提到的 `SDRAMsim_MiSTer` | GitHub | MIT 可用；**GPL-3.0 不进本仓库**（ARCHITECTURE.md §11） |

Micron TN 的一句话值得记住：数据手册本身不足以完成设计，厂商同时提供模拟（IBIS/HSpice）与行为（Verilog）模型；IBIS 与 HSpice 会互相校验并在有条件时与实验室测量比对。

## 3. `dv365lab/awesome-dram` 逐一参考

仓库自述：约 5880 文件 / 2.9 GB，4 个一级目录，**"学习归档，非原创；上游链接以各子目录 readme 为准"**，合集层面仅作"学习交流使用，请尊重原作者版权"。目录名 `29个DDR验证项目/` 实际只有 28 个子项目。

**这本身就决定了它只能当索引，不能 vendor 进本仓库**：2.9 GB 第三方资料、许可按各子目录自述、合集层面无授权。

### 3.1 四个一级目录

| 目录 | 内容 | 对本项目 |
|---|---|---|
| `29个DDR验证项目/` | 28 个开源 DDR/DRAM 项目，~2.2 GB | 验证方法/目录范式参考；控制器源码不抄 |
| `DDR-LPDDR-Sim-Model/` | Micron 官方行为级仿真模型，~6 MB | **与我们 import 的 Micron 模型同类，All rights reserved，不能入库** |
| `DDR相关的应用/` | 教程、Layout、SI、原理、论文，~207 MB | SI/PI 方法参考，见 `docs/SI_PI_PACKAGE_PCB.md` |
| `DRAM-Specs/` | 32 份 JEDEC / DFI PDF，~431 MB | DDR1 `JESD79F`、DDR2 `JESD79-2F`+`JESD208`、DFI `6.0.1`；本项目不抄 JEDEC 正文（ARCHITECTURE.md §2） |

`DRAM-Specs` 的缺口也如实记录：LPDDR5 未收录、DDR6/GDDR 目录为空。

`DDR-LPDDR-Sim-Model` 的 6 个子目录（SDR→DDR4）：`sdr_sdram/`（`sdr.v`，64M~512M，速率档 6a/75/**7e**）、`4077mt48lc32m16a2_sdram_model/`（512Mb SDRAM v2.1）、`11512Mb_ddr/`（`ddr.v` + `ddr_dimm.v`）、`39571024Mb_ddr2/`（`ddr2.v` + `ddr2_mcp.v` + `ddr2_module.v`）、`DDR3 SDRAM Verilog Model/`、`ddr4_verilog_models/`（加密 `.svp`）。子目录名含乱码，实为 Micron 通用参数化模型。**注意 SDR 模型带 75 和 7e 两个速率档，正好对应 §1.3 的参数混用风险。**

### 3.2 28 个项目逐条参考

| # | 项目 | 对本项目参考价值 |
|---|---|---|
| 01 | DRAM-Bender | 真实器件表征方法学（RowHammer/Retention）；本项目第一版硅的失效地址记录思路可借鉴 |
| 02 | SoftMC | "软件定义命令"架构；对应本项目 DFI 注入器做初始化/训练 |
| 03 | **litedram** | **已是本仓库 submodule**，控制器与 DFI 契约的基准；不需另抄 |
| 04 | ddr5_phy | DFI 频比 1:1/1:2/1:4 与 UVM 分层；本项目 nphases=1，仅看接口组织 |
| 05 | DDR3 MC DUT+TB | 控制器 RTL 与验证环境分离的目录范式 |
| 06 | DDR3-controller-verification | UVM agent/sequence/driver/monitor 模板；本项目是轻量 SV TB，可参考分层 |
| 07 | SDRAM-Verification | **SDR SDRAM + OpenCores sdr_ctrl，OOP vs UVM 双版本**：与本项目 Class S 同代际，验证结构最贴近 |
| 08 | BrianHG-DDR3-Controller | 多端口控制器状态机、PHY 时序约束写法 |
| 09 | UberDDR3 | 控制器+PHY 一体 + SymbiYosys 形式验证；形式验证可用于本项目命令间隔检查器 |
| 10 | core_ddr3_controller | DFI 时序序列、AXI 桥接 |
| 11 | DDR4_controller | MIG PHY 之上的控制器 TB 写法 |
| 12 | rdimm-ddr4-tester | KiCad RDIMM 载板、SI/电源分区：板级参考，非自研范例 |
| 13 | sodimm-ddr5-tester | 板级走线参考 |
| 14 | DDR (RamController) | 23 态 FSM + SymbiYosys 入门 |
| 15 | wav-lpddr-hw | 商业级 PHY 架构、训练/校准、UVM+VIP 流程：读它了解"签核级验证长什么样"，不抄代码 |
| 16 | lpddr4-test-board | Antmicro 测试载板，板级参考 |
| 17 | lpddr4 SoC 集成 | LiteX 把 PHY 包成 SoC：对应本项目 §8 "怎么接进芯片" |
| 18 | lpddr5-testbed | 板级平台 |
| 19 | DDR2_Controller | DDR2 初始化状态机 + Micron 模型；本项目 DDR2 仍在 P4，先看命令顺序 |
| 20 | DDR4MemoryController | 模块化 FSM 拆分（仲裁/读写/命令/时序） |
| 21 | ddr_sdr_V1_1 | OpenCores DDR1 控制器，可作命令顺序参考；本项目使用 LiteDRAM 驱动 `rtl/ddr1_phy.sv` |
| 22 | ddr2_sdram | MIG 核接法，板级实战 |
| 23 | ddr3_sdram | 紧凑控制器与软核对接 |
| 24 | ddr3_synthesizable_bfm | 可综合内存 BFM：与本项目 `sim/sdram_model.sv` 思路相近 |
| 25 | genesys_ddr2 | Wishbone 桥接、板上调试 |
| 26 | sdram_16bit | **最精简 SDR SDRAM 控制器**，与本项目 Class S 同代际，入门对照 |
| 27 | DDR_SDRAM | MIG 生成的真实 DDR 控制器结构 |
| 28 | hpdmc | 成熟 DDR/DDR2 控制器、CSR/FML 接口 |

横向分类里与本项目直接相关的三类：**生成式控制器框架**（03，已在用）、**SDR 同代际验证**（07/26，07 最贴近）、**板级 SI 参考**（12/13/16/18）。ARCHITECTURE.md §7 已经列过一批外部控制器并明确"只看命令顺序、不抄源码、不做成 submodule"，这份 28 项清单是它的扩展，**结论不变**。

### 3.3 规范速查（与本项目有关的两条）

- DDR1 `JESD79F`、DDR2 `JESD79-2F` + `JESD208`（1066 扩展）、DFI `6.0.1`。
- 本项目 P0 是 SDR，ARCHITECTURE.md §2 写明"JEDEC 正文不在本仓库，不抄"；这些 PDF 只在需要核对 DDR1/DDR2 具体电气定义时查阅。

### 3.4 可选差分运行

- `tb/tb_micron_diff.sv` 把相同 DFI 流量送进两条独立路径：裸核 `sdr_phy` 接自研行为模型，`sdram_phy_top` 经仿真 pad 接 Micron `mt48lc16m16a2`（只用低字节）。按两者相差三拍的固定返回延迟对齐，逐拍比较 `dfi_rddata_valid` 和 `dfi_rddata`，并检查集成端的读超期和总线争用。
- 覆盖 CL2/CL3、单读写、写屏蔽（DQM）、周期刷新（`T_REFI=40`）及 READ→WRITE 转向；控制器使用集成 PHY 的 `turnaround_busy`。
- `tb/tb_micron_burst.sv` 另做模型级 Burst 差分（BL=2/4/8）；它绕过控制器，因为 `sdr_ctrl` 还没有 BL>1 事务路径。
- `sim/micron_diff.sh` 在模型存在时编译/运行 CL2 和 CL3；模型不存在时打印 `SKIP` 并以 0 退出。模型仍在 `.gitignore`，不提交。
- 测试把 `T_RFC` 设为 7 拍（10 ns 下 70 ns），以满足 Micron -7E 模型的 tRFC；这**不是**把模型的 -7E 参数写进本项目 -75 contract。
- 通过只证明这条命令/数据 trace 在两个模型上一致；不证明 tAC/tOH/tDS/tDH、PVT、pad 或板级时序。模型报 `ERROR:` 时脚本失败。

## 4. 决策与不做的事

- `sim/sdram_model.sv`、`sim/sdram_checker.sv`、`sim/sdram_timing_model.sv` 保持自研；不引入任何厂商模型作为仿真依赖。
- 外部模型只作**命令顺序 / 验证结构 / 参数交叉核对**参考，且必须注明许可状态。
- 不用 `mt48lc16m16a2.v` 的时序参数覆盖 `specs/devices/*.yaml`。
- 不把 awesome-dram 的任何文件、任何 GPL-3.0 或 "All rights reserved" 源码复制进本仓库。
- 不把"IBIS 通常不需要 NDA"推广成"所有厂商模型都可自由再分发"。
