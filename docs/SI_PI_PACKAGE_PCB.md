# 封装寄生 / PCB / SI-PI / EBD 建模记录

状态：**方法与映射记录，尚未做任何 SI/PI 仿真。** `specs/timing_contract.yaml` 的 28 个 TBD 项没有减少；本文件说明它们将来应该"怎么被测出来"，而不是给出数值。

配套：`docs/TIMING_BUDGET.md` §4/§5（一阶预算）、`docs/TIMING_SWEEP.md`（相位扫描）、`docs/STA_PLAN.md` §4（尚未做的部分）。

## 1. 封装寄生：从 IBIS 的 RLC 开始

IBIS 文件里通常能找到：

```text
[Package]
R_pkg   L_pkg   C_pkg        ; 封装默认寄生

[Pin]
R_pin   L_pin   C_pin        ; 单引脚覆盖值
```

- `[Package]` 给的是该封装的默认寄生，`[Pin]` 可以对单引脚覆盖；更复杂的模型用 `[Package Model]`。这是 IBIS 标准规定的封装建模方式。
- **局限**：简单的单引脚 RLC 描述不了引脚间的 Mutual Inductance / Mutual Capacitance。要分析 DDR2 大量同步切换噪声（SSN / Ground Bounce），需要更完整的封装模型。

精度阶梯（本项目按"现有证据能支撑到哪一级"选，不越级声称）：

| 模型 | 精度与用途 |
|---|---|
| Lumped RLC | 早期时序预算、单线瞬态 |
| Pin-specific RLC | 比默认封装寄生更接近实际 |
| Coupled RLC | Ground Bounce、串扰 |
| Multiport S-parameter | 高频传播、反射、复杂封装耦合 |
| 3D EM Extracted Model | 已有封装几何时的详细建模 |

**若厂商没提供高精度 Package Model，可以先用官方 IBIS 的 RLC，但必须把不确定性计入设计 Margin**——对应 `specs/timing_contract.yaml` 的 `t_uncertainty`，不能悄悄当零。

Micron FAQ 的补充事实：`.ibs` 是 I/O 缓冲器的 V/I、V/T 行为表示，不含器件内部专有信息，**通常不需要 NDA**；HSpice 模型由实际电路导出，IBIS 由 HSpice 导出并做一致性校验。EBD / ODB++ / 电路板文件含模块机密信息，无 NDA 不提供。

## 2. PCB：先考虑传输线，不只是 RC

PCB 走线至少需要四个分布参数（单位长度）：

```text
R'  L'  G'  C'
```

低损耗近似：

```text
Z0        ~= sqrt(L' / C')
t_flight  ~= l * sqrt(L' * C')
          ~= l * sqrt(eps_eff) / c
```

FR-4 的典型传播延迟可粗取 **5–7 ps/mm**，具体取决于 Microstrip / Stripline、介质厚度和材料参数。50 mm 走线约 **250–350 ps** 单程。

单位间隔对照：

| 数据速率 | Unit Interval |
|---|---|
| SDR-133 | 7.52 ns |
| DDR-266 | 3.76 ns |
| DDR-400 | 2.50 ns |
| DDR2-533 | 1.88 ns |
| DDR2-800 | 1.25 ns |

DDR2-800 下 50 mm 的约 300 ps 达到一个 UI 的 24%。但**绝对传播延迟不等于时序损失**：真正要衡量的是 DQ 相对 DQS、Command 相对 CK，以及不同信号之间的**延迟差**；公共延迟可以在时序关系里抵消。

这一点直接落在本项目的约束结构上：`flow/sdr_phy.sdc` 里 `board_dq_*` 与 `board_ck_*` 是分开的占位变量，`set_input_delay` / `set_output_delay` 用的是它们的**差值**，而不是一个合并的 `set_output_delay 2`。`docs/TIMING_BUDGET.md` §4 的往返预算里 `tCLK,fwd + tDQ,return` 对 setup 是减数、对 hold 是加数，也是同一个道理。

对本项目当前的 100 MHz / CL2 基线（tCK = 10 ns），250–350 ps 的绝对延迟占比远小于 DDR2-800；但 `tAC(2) = 6.0 ns` 已经吃掉 60% 周期，**相对偏斜仍不可忽略**，因为 28 个 TBD 项里 `dq_bit_skew` / `cmd_addr_skew` / `clk_dcd` 全是 `null`。

## 3. 从真实 PCB 获得寄生：三个阶段

| 阶段 | 输入 | 方法 | 产出 |
|---|---|---|---|
| Pre-layout | Stackup、线宽、间距、长度估计 | 2D Field Solver / RLGC | 阻抗、传播延迟、串扰估计 |
| Post-layout | 完整铜层、Via、Pad、Plane | 2.5D / 3D EM Extraction | S 参数或耦合传输线网络 |
| Hardware | PCB 实物、测试夹具 | TDR / VNA / 示波器 | 实测阻抗、S 参数、时域波形 |

- **TDR**：发现连接器、过孔、端接、线宽变化造成的阻抗不连续。
- **VNA**：测 S11、S21 与多端口耦合；条件允许时要做 Calibration 和 De-embedding 去掉夹具影响。
- 最终硬件用示波器看真实 DQ/DQS/CK 波形与数据眼图。

## 4. SI/PI 工具

| 工具 | 类型 | 建议 |
|---|---|---|
| Siemens HyperLynx | SI/PI、DDR 通道 | DIMM / DDR1 / DDR2 合适 |
| Cadence Sigrity | SI/PI、PCB/Package | 复杂 DIMM、多端口与电源网络 |
| Keysight ADS | SI、SPICE、Channel | S 参数与时域联合分析 |
| Ansys HFSS / SIwave | 电磁提取 | Package、PCB、Via、PDN |
| ngspice / Xyce | 电路瞬态 | RLC、传输线、Pad SPICE 子电路 |
| openEMS | 开源电磁场仿真 | PCB 结构与通道提取 |
| scikit-rf | Python RF 工具 | S 参数分析、级联与处理 |

开源路线（适合本项目）：

```text
KiCad / PCB Geometry
  -> Antmicro gerber2ems (Gerber + 钻孔 + Stackup)
  -> openEMS
  -> Touchstone S-parameters
  -> Python SignalIntegrity / 电路仿真
  -> Eye Diagram + Timing Margin
```

Antmicro `gerber2ems` 用 PCB 的 Gerber、钻孔和 Stackup 调 openEMS 做 SI 仿真；openEMS 的 SignalIntegrity 教程讲如何把 S 参数用于时域响应与眼图。

**两条必须保留的限制**：

1. ngspice 不能简单地把任意 Touchstone S 参数直接当作宽带瞬态器件使用；需要时域 S 参数求解能力，或经过验证的拟合模型转换。
2. IBIS 的 V/I、V/T Buffer Model 与线性 S 参数网络**不是同一类模型**。有源驱动器 + 无源互连联合仿真需要支持 IBIS 的求解器，或经过验证的 IBIS-to-SPICE 表示。

这两条也解释了为什么 `docs/STA_PLAN.md` §4 把 PEX / SPICE / IBIS / SI-PI 全部列为"尚未做"：不是没工具，是没有 pad 网表、封装模型和板级模型作为输入。

## 5. 到 DIMM 后还需要 EBD

Micron FAQ 给出的 DIMM 完整 IBIS 环境组成：DRAM 器件 IBIS、寄存器/PLL 等器件模型、端接模型，以及描述 DIMM PCB 的 **EBD（Electronic Board Description）** 文件。相比只用单颗 DRAM IBIS，EBD 让仿真器理解模块内部各器件、走线与连接关系。

- 商业 DIMM：优先申请该模块具体 Part Number 对应的 EBD / HyperLynx 模型，而不是凭照片猜走线长度。Micron 说明部分模块模型可向技术支持申请；连接器模型最好从连接器厂商获得。
- Micron 的模块模型格式还包括 Cadence DML、Mentor ICX、HyperLynx；多数 IBIS EBD 由 HyperLynx EBD Writer 生成，**因模块型号太多而按需提供**。
- 开源项目若拿不到厂商 EBD，只能构造带不确定性范围的等效拓扑，并明确标注为假设。

本项目第一版硅是点对点单颗 SDR、无 DIMM（ARCHITECTURE.md §8/§11），EBD 目前不需要；但它是 P2 之后"从单颗扩到模块"的必备输入。

## 6. 映射到本项目的 TBD 项

`specs/timing_contract.yaml` 新增的 `modeling_plan` 段把下列方法逐项挂到了 TBD 上（只有方法，没有数字）：

| TBD 项 | 表征方法 |
|---|---|
| `package_rlc` | IBIS `[Package]` 默认 + `[Pin]` 单引脚 + `[Package Model]` 耦合网络 |
| `board_flight` | RLGC 传输线，`t_flight ~= l*sqrt(L'C')`，FR-4 5–7 ps/mm |
| `termination` | 板级串/并联端接；DDR2 的 ODT 跟 DFI `odt` |
| `dq_bit_skew` / `cmd_addr_skew` | 布局后 EM 提取或 TDR/VNA，按 byte lane |
| `clk_jitter` / `clk_dcd` | PLL/DLL 相噪 + pad/时钟树 SPICE；`adpll_gen` 目前返回 `FAIL_UNCHARACTERIZED` |
| `t_uncertainty` | jitter + OCV + PVT + SSN + skew 之和，不是猜一个数 |
| `tOE_on/off`、`tRX_setup/hold` | pad SPICE + 输入 pad/捕获 FF 的 Liberty |
| `tCLK_fwd_*` / `tDQ_return_*` | 输出/输入 pad + 封装 + PCB，min/max 两角 |

## 7. 不这样做

- 不把 IBIS `[Package]` 的 RLC 当成能描述引脚间互感的完整模型。
- 不把 50 mm / 300 ps 的绝对延迟直接当成时序损失；只算相对偏斜。
- 不把 FR-4 的 5–7 ps/mm 当成已表征的本板参数。
- 不把 ngspice + Touchstone 说成已验证的宽带瞬态流程，不把 IBIS 与 S 参数当成同一类模型。
- 不凭 DIMM 照片猜走线，不把"可申请 EBD"说成"已有 EBD"。
- 不因为写了这份方法记录就把 `reports/capability_report.md` 的 `NO_GO` 改掉；`tOE_on/off` 仍是 `null`。
