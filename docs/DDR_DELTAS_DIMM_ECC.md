# DDR1 / DDR2 差异、DIMM 与 ECC 定位

状态：**设计记录，不是实现。** 本仓库的 `rtl/ddr1_phy.sv` / `ddr2_phy.sv` 仍未写（ARCHITECTURE.md §8），第一版硅是点对点单颗 SDR。本文记录"以后扩展时到底要加什么"以及它与现有架构决策的一致性。

## 1. 一致性检查

先说结论：下面这些内容与 `docs/ARCHITECTURE.md` 不冲突，反而补齐了它的依据。

| 本文要点 | 架构文档对应 |
|---|---|
| DDR1 2.5 V SSTL_2、DDR2 1.8 V SSTL_18，不与 3.3 V SDR 共轨 | §1 / §5 / §6 的电压表与"不要用 3.3 V 推 2.5 V 颗粒" |
| DDR1/DDR2 不照搬 DDR3 Write Leveling | §11 "不做 fly-by、不做写电平" |
| SPD 放系统软件/控制器，不塞进 PHY Datapath | §8 "SPD 不在 PHY 里"，第一版点对点、几何由板级给定 |
| ECC 不埋进每个物理 DQ Lane | §8 "ECC 也不在 PHY 里" |
| 第一版点对点单颗、无 DIMM | §1 / §8 / §11 |

一处需要说清的措辞差异：架构文档写"ECC 不进 PHY"，本文写"ECC Engine 放在 Controller 与 PHY 的边界附近"。二者不矛盾——**数据通路的额外 Lane 由 PHY 正常处理，但 Syndrome/纠错/RMW 属于控制器或紧邻控制器的逻辑**。下面 §5 展开。

## 2. SDR → DDR1 → DDR2 不是简单翻倍

| 能力 | SDR SDRAM | DDR1 | DDR2 |
|---|---|---|---|
| I/O 标准 | 通常 3.3 V LVTTL | 2.5 V SSTL_2 | 1.8 V SSTL_18 |
| 时钟 | CLK | CK / CK# | CK / CK# |
| 数据传输 | 单沿 | 双沿 | 双沿 |
| DQS | 无 | 有，双向 | 有，可有差分 DQS |
| Read Capture | 参考 CK | DQS 源同步 | DQS 源同步 |
| ODT | 通常无 | 主要靠板级端接 | DRAM 支持 ODT |
| 内部 Prefetch | 1n | 2n | 4n |
| Write Latency | 与 WRITE 命令同拍 | DDR1 特定规则 | `AL + CL - 1` |
| PHY 校准 | 通常简单 | DQS 相位调节 | DQS 相位、Gate、ODT 控制 |

DDR2 的具体规则（已由器件资料核对）：`RL = AL + CL`、`WL = RL - 1 = AL + CL - 1`；AL 由 EMRS(1) 配置，允许在 ACT 后提前发 CAS 命令；读时 DQS 在有效数据前一拍拉低作 preamble；`BL` 为 4 或 8，最小突发不小于预取值；另有 `tRTW` / `tWTR` 等转向约束。DDR1 的双向 DQS 与 SSTL_2 可参考 Micron TN-46-05。

**DDR1/DDR2 不需要 DDR3 的 Write Leveling**：那是 fly-by 拓扑引入后才必需的步骤；本项目点对点短走线不走那条路。

## 3. 最难的是 DQS Read Capture

读方向：DRAM 同时输出 DQ 与 DQS，DQS 边沿通常接近数据切换边界。PHY 需要把接收 DQS **适当延迟**，才能在 DQ 眼图中心采样。

写方向相反：PHY 要产生中心对齐的 DQS 与 DQ，并保证两端信号在 SDRAM 引脚处满足时序。

因此：

- 每个 **Byte Lane 最好有独立的 DQS 时序域与采样控制**；
- DDR2 还要处理 Read DQS Preamble / Postamble、DQS Gating、ODT 控制与 Write Latency；
- 这些都需要专门的验证环境，不能靠"行为模型跑通"代替。

与本项目已有工作的衔接：`docs/TIMING_SWEEP.md` 的相位扫描是 **SDR 无 DQS、靠 `Δt_capture` 找窗口** 的版本；`rtl/read_capture_ctrl.sv` 留的 `phase_select` 接口在 DDR1/DDR2 里会变成 **每 byte lane 一份**。但 `reports/capability_report.md` 的 G6 仍开放——没有已表征的 PLL/DLL/延迟单元，所以现在连 SDR 的相位都还没产生，更谈不上 DQS 延迟链。

## 4. Chip / Bank / Rank / DIMM 不是同义词

| 术语 | 含义 |
|---|---|
| Chip | 单颗 DRAM 器件 |
| Bank | 芯片内部可独立管理行状态的存储阵列 |
| Rank | 共同构成一个数据总线宽度、由同一个 Rank Select 选择的一组颗粒 |
| DIMM | 标准接口 + 连接器 + 多颗 DRAM + SPD 等的物理模块 |

**Rank 不是 Bank 的另一种叫法**；Micron FAQ 明确区分：Bank 是单颗器件内的子阵列，Rank 是模块级、通常等于系统数据总线宽度（64 或 72 位）。8 颗 x8 组成一个 64-bit 单 Rank；16 颗 x8 组成双 Rank。

单 Rank 位宽组织：

| 配置 | 每 Rank 颗粒数 | 总线 |
|---|---|---|
| x16 Non-ECC | 4 | 64-bit |
| x8 Non-ECC | 8 | 64-bit |
| x8 ECC | 9 | 72-bit |
| x4 ECC | 18 | 72-bit |

例：每颗 x8 为 512 Mb 时，8 颗给 512 MiB 用户数据；第 9 颗只存 ECC 校验位，**不给软件额外 64 MiB 地址空间**。

### 4.1 DIMM 需要增加的硬件与逻辑

| 扩展 | PHY / Controller 要做 |
|---|---|
| 64/72-bit Bus | 增加 DQ、DM、DQS Byte Lane |
| 多颗 DRAM | Command/Address 扇出、负载分析 |
| Multi-rank | CS、CKE、ODT Rank 选择 |
| SPD EEPROM | SMBus/I²C 读取与解析 |
| DIMM Connector | 连接器寄生模型、额外延迟 |
| Registered DIMM | 命令/地址延迟与寄存器模型 |
| ECC | 额外数据 Lane 与 ECC Engine |
| DIMM 热插拔 | 通常不支持，需系统级规定 |
| 多 DIMM 插槽 | Multi-drop、复杂端接、不同负载与拓扑 |

**SPD 放系统软件或控制器**，由它配置 PHY；没必要把 I²C Master 和 SPD Parser 强行放进高速 PHY Datapath。RDIMM 的地址/命令寄存器一般多一个命令时钟周期延迟，还可能带 PLL、C/A Parity。

### 4.2 Layout 差别

DDR2 DIMM 要按信号分组优化：Command/Address/Clock 服务多颗颗粒，可能用平衡分支、T 拓扑与专门端接；DQ/DQS/DM 按 Byte Lane 组织并保持严格的组内匹配。多 Rank 让总线负载、未选中芯片输入电容与端接状态更复杂。Micron DDR2 设计套件分别覆盖 UDIMM 与板载拓扑，含端接、Slew Rate Derating、Pre-layout / Post-layout SI 验证方法。

**布局规则不能从单颗 DRAM 直接复制到 DIMM**：颗粒数和连接器增加后，原先够用的 CLK/DQ Margin 可能不再够。方法上接 `docs/SI_PI_PACKAGE_PCB.md` §3/§5（EM 提取、EBD）。

### 4.3 UDIMM / RDIMM / FB-DIMM

| 模块 | PHY 影响 |
|---|---|
| UDIMM | 直接，C/A 连 DRAM |
| ECC UDIMM | 增加 8-bit ECC Lane |
| RDIMM | C/A 经寄存器，需额外时序处理 |
| ECC RDIMM | RDIMM + ECC Lane |
| FB-DIMM | 有 AMB 与不同主机接口，不能当普通并行 DDR2 PHY |

**ECC 与 Registered 是两种独立属性**：支持 ECC UDIMM 不代表支持 RDIMM，支持 RDIMM 也不代表实现了 ECC。

## 5. ECC 放在哪里

建议把 **ECC Engine 放在 Controller 与 PHY 的边界附近**，而不是埋在每个物理 DQ Lane 里。

```text
Data[63:0] -> ECC Encode -> PHY[71:0]        (写)
PHY[71:0] -> Syndrome -> Correct/Detect -> Data[63:0]   (读)
```

| 项目 | Non-ECC | ECC |
|---|---|---|
| 用户数据宽度 | 64 | 64 |
| 物理数据宽度 | 64 | 72 |
| x8 Byte Lanes | 8 | 9 |
| DDR DQS Lane | 8 | 9 |
| SECDED | 无 | 纠 1 位、检 2 位 |

两层职责要分开：

- **物理层**：额外的 ECC Byte Lane 与普通 Lane 一样要做 DQS Capture、Delay、SI/PI、Timing Margin 和 BIST 验证。这正是"PHY 要加一条 Lane"的部分。
- **逻辑层**：Syndrome、纠错、双位错误报告、错误注入、错误计数，以及必要的 Memory Scrubbing。
- **Partial Write**：写入不足一个完整 ECC Codeword 时，控制器通常要用 Read-Modify-Write 或等效机制，保证未修改数据位与校验位一致。
- **SECDED ≠ Chipkill**：后者要求对整颗器件失效的更强保护，涉及不同编码、数据交织与颗粒组织，不能只靠加一颗 ECC x8。

可参考 Intel 的 DDR/DDR2 SDRAM ECC Reference Design AN415（用外部 Micron 模型验证 ECC 控制器）。

## 6. 与本项目分期的关系

- **P0（当前）**：单颗点对点 SDR，x8/x16，无 DIMM、无 ECC、无 SPD、无 DQS。ARCHITECTURE.md §8 已写明这些。
- **P2**：`rtl/ddr1_phy.sv` 需要 §2/§3 的 DQS 双向、byte-lane 时序域、SSTL_2 pad；但 G1/G5/G6 仍开放。
- **P3**：接 DDR1 pad 与 `ck90`；只在 sky130 / IHP / ics55，且 IHP 要先有 2.5 V 器件仿真。
- **P4**：DDR2，只在 55 nm 且要另一套 1.8 V IO，目标 DDR2-400；AL/WL/ODT/Gating 都在这一档。
- **DIMM / ECC / Registered**：均在第一版硅范围之外，属于更后面的系统级扩展，不是 PHY 生成器当前的能力等级。

## 7. 不这样做

- 不把 DDR1 说成"SDR 改双沿"、DDR2 说成"DDR1 频率翻倍"。
- 不给 DDR1/DDR2 强加 DDR3 的 Write Leveling（本项目无 fly-by）。
- 不把 Rank 和 Bank 混用，不把第 9 颗 ECC 颗粒算进用户地址空间。
- 不把 I²C Master / SPD Parser 塞进 PHY Datapath，不把 ECC Syndrome 埋进每条 DQ Lane。
- 不把 ECC UDIMM 与 RDIMM 混为一谈，不把 SECDED 说成 Chipkill。
- 不凭 DIMM 照片猜走线，不用单颗颗粒的 Layout 规则套 DIMM。
- 不因为写了这份记录就说 `ddr1_phy.sv` 已经存在——它仍然是 `还没写`。
