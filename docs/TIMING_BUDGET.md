# SDR PHY 读/写时序预算（P0-1）

状态：一阶预算。不是 STA，不是 SDF 时序仿真，不是 pad / 板级仿真，更不是签核。
本文只回答一件事：**在已知器件参数的条件下，读/写采样还剩多少时间余量，以及还缺哪些数才能算完**。所有未表征的量保持空；不用典型值补齐，不从别的 speed grade 借数，不把镜像转录说成"已核对官方 PDF"。

配套文件：`specs/timing_contract.yaml`、`specs/interface.yaml`、`specs/devices/*.yaml`。架构决策仍在 `docs/ARCHITECTURE.md`，本文不重复它。

## 1. 数据来源与可信度

这一轮补到了 `sim/sdram_checker.sv` 里刻意没写的 AC 参数。两张表都是制造商数据手册 AC 表的镜像渲染，不是现场核对的 Micron / ISSI 官方 PDF：

| 器件 | 表 | 来源 |
|---|---|---|
| Micron MT48LC16M16A2 -75 | Table 20, AC Operating Conditions (-7E, -75)，只取 -75 列 | alldatasheet.co.uk 镜像 |
| ISSI IS42S16160J / IS42S83200J -7 | AC ELECTRICAL CHARACTERISTICS，-7 列，页眉 Rev. D 02/27/2025 | alldatasheet.net 镜像 |

版本标注不一致，签核前必须核对官方 PDF：

- `sim/sdram_checker.sv:9` 引用 Micron `256Mb_sdr.pdf Rev. W (05/15)`；镜像页眉是 `Rev. L 10/07`。转录的 -75 数值与 checker 一致（tRCD 20、tRP 20、tRAS 44、tRC 66、tRFC 66、tRRD 15、tWR 1CLK+7.5 / 15、tCK(2) 10、tCK(3) 7.5）。
- `sim/sdram_checker.sv:20` 引用 ISSI `Rev. C4 (09/17/2020)`；镜像是 `Rev. D 02/27/2025`。tRCD 15、tRP 15、tRAS 37、trc 60 一致。

**不要混表。** 不要把 -7E 列当成 -75，不要把 Micron 的 `tRFC = 66 ns` 安到 ISSI 上（ISSI 表没有单独 tRFC，刷新恢复用 `trc = 60 ns`）。这与 `sim/sdram_checker.sv:20-22` 的告诫一致。

## 2. 补到的关键 AC 参数（ns）

| 参数 | Micron -75 | ISSI -7 | 说明 |
|---|---|---|---|
| tCK(2) min | 10.0 | 7.5 | CL=2 最小时钟周期 |
| tCK(3) min | 7.5 | 7.0 | CL=3 最小时钟周期 |
| tAC(2) max | **6.0** | 5.4 | Micron CL=2 不是 5.4 |
| tAC(3) max | 5.4 | 5.4 | |
| tOH min | 3.0（带负载） | 2.5 | Micron 另有空载 `tOHN = 1.8` |
| tHZ max | 6.0 (CL2) / 5.4 (CL3) | 5.4（另有 min 2.5） | 决定 READ→WRITE 何时放开 DQ |
| tLZ min | 1.0 | 0.0 | 决定 DQ 何时开始驱动 |
| tDS / tDH min | 1.5 / 0.8 | 1.5 / 0.8 | 写数据与命令的输入建立/保持 |
| tAS / tAH min | 1.5 / 0.8 | 1.5 / 0.8 | |
| tCMS / tCMH min | 1.5 / 0.8 | 1.5 / 0.8 | 含 DQM |
| tRCD / tRP / tRAS / tRC min | 20 / 20 / 44 / 66 | 15 / 15 / 37 / 60 | |
| tRFC min | 66 | **无单独项，trc = 60** | |

两个容易踩的点：

1. **Micron -75 的 `tAC(2) = 6.0 ns`，`tAC(3) = 5.4 ns`**。100 MHz / CL2 的预算必须用 6.0；checklist §4.2 的 5.4 ns 对应的是 133 MHz / CL3，两者不冲突但不能互换。
2. `tOH` 有负载条件。Micron 带负载 3.0、空载 1.8；ISSI 是 2.5，且 `tHZ` 是双边（min 2.5 / max 5.4）、`tLZ` min 为 0。这些 min/max 必须成对进 STA，不能只取 max。

## 3. 三个工作点与理想上限

| 工作点 | 器件 | tCK | CL | tAC max | tOH min | setup 上限 | hold 上限 |
|---|---|---|---|---|---|---|---|
| A 基线 | Micron -75 | 10.0 | 2 | 6.0 | 3.0 | **4.0** | 3.0 |
| B 提速 | Micron -75 | 7.5 | 3 | 5.4 | 3.0 | **2.1** | 3.0 |
| C 备选 | ISSI -7 | 7.5 | 2 | 5.4 | 2.5 | **2.1** | 2.5 |

`setup 上限 = tCK - tAC,max`，`hold 上限 = tOH,min`，均假设 `tCLK,fwd + tDQ,return + tRX,setup + t_uncertainty = 0`。它们是**上界，不是可用余量**。

- A 的 tCK = 10.0 正好等于 `tCK(2)` 下限，**颗粒本身没有频率余量**；抖动和占空比失真直接吃这 10 ns。
- B 的 2.1 ns 与 checklist §4.2 的 `7.5 - 5.4` 一致；tCK = 7.5 同样正好贴着 `tCK(3)` 下限。
- C 说明 ISSI -7 允许 CL2 跑到 7.5 ns 且 tAC 仍是 5.4，所以 setup 上限也是 2.1 ns，但 hold 只有 2.5 ns。

## 4. 读路径预算

Forwarded-clock 往返的一阶模型。设 ASIC 在内部沿发出，CK 到达颗粒引脚延迟 `tCLK,fwd`，读数据从颗粒引脚回到捕获 FF 的 D 端延迟 `tDQ,return`；捕获沿用 `read_latency = CL+1`（GENSDRPHY 的几何，多出的一拍容纳往返和 DQ 输入寄存器）。捕获沿相对基准偏移 `Δt_capture`（正值 = 延后）。

```text
M_read,setup = tCK - tAC,max - tCLK,fwd(max) - tDQ,return(max) - tRX,setup - t_unc + Δt_capture
M_read,hold  = tOH,min + tCLK,fwd(min) + tDQ,return(min) - Δt_capture - tRX,hold - t_unc
```

- 往返延迟对 setup 是减数、对 hold 是加数。**必须按 min/max 配对**：setup 用数据路径 max / 时钟路径 min，hold 反过来。上式按单一延迟值写，只对 setup 保守；真实 STA 要对每个角分别取 min/max。
- `Δt_capture > 0` 改善 setup、恶化 hold。没有"往后移 90° 就更好"的通用结论，安全窗口只能靠全 PVT 相位扫描找。
- `tHZ(max)` 决定 READ→WRITE 转向时颗粒何时放开 DQ；`tLZ(min)` 加 pad 的 `tOE,on` 决定 PHY 何时开始驱动。两者要在同一时间轴上检查，不能只看 `rtl/sdr_phy.sv` 里 `dq_oe` 那一个 FF。

代入已知数，仍然**不能闭合**。令 `T_unknown = tCLK,fwd + tDQ,return + tRX,setup + t_unc`：

```text
Case B:  M_setup = 2.1 ns - T_unknown + Δ
Case B:  M_hold  = 3.0 ns + (min 往返) - Δ - tRX,hold - t_unc
```

敏感性（Δ = 0，未计 hold 侧收益）：

| T_unknown | A setup | B setup | C setup |
|---|---|---|---|
| 0.0 ns | 4.0 | 2.1 | 2.1 |
| 1.0 ns | 3.0 | 1.1 | 1.1 |
| 2.0 ns | 2.0 | 0.1 | 0.1 |
| 3.0 ns | 1.0 | -0.9 | -0.9 |

负数表示固定相位在该工作点已不成立，需要加 `Δ` 或降频。A 的 4.0 ns 看着宽裕，但 tCK 已贴着器件下限，且 `T_unknown` 全部未表征——**不能据此说 100 MHz 已可行**。

## 5. 写路径预算与 `ck = clk` 的后果

SDR 的 WRITE 命令和第一拍 DQ 由颗粒在**同一个 CK 上升沿**采样（`write_latency = 0`）。设 `Δtx = tDQ,tx - tCLK,fwd`，即 DQ 到达颗粒引脚相对 CK 沿到达的时差：

```text
M_write,setup = tCLK,fwd(min) - tDQ,tx(max) - tDS - t_unc          [同一沿采样]
M_write,hold  = tDQ,tx(min) + tCK - tCLK,fwd(max) - tDH - t_unc
```

上式假定 DQ 在下一拍前保持驱动；BL=1 时 `dq_oe` 只有一拍，实际还要把 pad 的 `tOE,off` 和总线 Hi-Z 后的板级保持算进去，这里未计入。

`tDS = 1.5`、`tDH = 0.8` 现在是已知数（§2），所以写路径的要求可以写成对 **DQ 与 CK 路径相对偏斜** 的约束，而不是对绝对延迟的约束——这正是 `docs/ARCHITECTURE.md` 说"片外 tCO 主要变成 pad 延迟差"的那一层，也是 `flow/config.librelane.json` 目前完全没有约束的一层。

但 `rtl/sdr_phy.sv:77` 是 `assign ck = clk`：CK 与 DQ 从同一个内部沿、经同一类输出寄存器出发，**没有任何刻意的 CK 相位或延迟**。按上式 `M_write,setup` 退化成 `tCLK,fwd - tDQ,tx - tDS`，除非 CK pad 路径比 DQ 路径慢至少 `tDS` 加余量，否则写沿没有 setup 余量。这不是"仿真没跑"的问题，是当前微架构没有可控量：`ck` 被当成普通组合输出，综合和 CTS 可以自由改动它与 `dq_o` 的关系。

checklist §4.1 / §4.3 的两条路都还没走：要么给 forwarded CK 一个经过特征化的相位/延迟（PDK 已有 PLL/DLL 或已表征延迟单元），要么把写数据相对命令提前一拍并重新定义 `write_latency`。**不要靠未经约束的 inverter chain 移相，也不要让 CTS 自由决定 CK 与 DQ 的相对时序。**

## 6. 还缺什么（逐项对应后续工作）

| 未知量 | 由谁产生 | 对应任务 |
|---|---|---|
| `tCLK,fwd` / `tDQ,return` 的 min-max | CK/DQ pad + 封装 + PCB | P0-3 / P0-5 |
| `tRX,setup` / `tRX,hold` | 输入 pad + 捕获 FF | P0-3 |
| `t_uncertainty`（jitter、DCD、OCV、PVT、SSN） | 时钟 + PVT 角 | P0-2 / P0-5 |
| `Δt_capture` / `ck_phase` 的可控性 | PHY RTL | P0-4 |
| `tOE,on` / `tOE,off`、`tHZ`/`tLZ` 同一时间轴 | pad + timing-aware 模型 | P0-2 / P0-3 |
| DQ bit-to-bit skew、命令/地址 skew | 版图 + 封装 | P0-5 |
| 板级 flight、端接、负载 | 板级 SI | P0-5 |

`specs/timing_contract.yaml` 里这些全部是 `status: TBD` 且 `value: null`；它们构成 P0-1 的开口。

## 7. P0-1 出口条件

1. `specs/timing_contract.yaml` 中所有 `status: TBD` 项变成 `verified` 或明确标成 `assumption`。
2. 用 min/max 配对重算 §4 / §5，产出 `reports/timing_margin.json`。
3. 对 A/B/C 三个工作点给出"固定相位可行 / 不可行 / 需降频"的结论。

目前三条都不满足，**固定相位是否可行仍未定**。把 `T_unknown` 变成数的两步是 P0-2（timing-aware 模型 + 相位扫描）和 P0-3（pad 表征），而不是继续细化本文档。

## 8. 不这样做

- 不把 5.4 ns 当成 Micron -75 的 CL2 `tAC`（是 6.0）。
- 不把 Micron 的 `tOH = 3.0` 或 `tRFC = 66` 搬到 ISSI -7（2.5，无单独 tRFC，trc = 60）。
- 不从 typ 推断 min，不把镜像转录说成"已核对官方 PDF"，不在版本标注未核对前把这些数当签核限值。
- 不把 2.1 / 4.0 ns 的理想上限说成可用余量。
- 不把这份一阶预算说成 STA、SDF 时序仿真、pad 仿真或电气签核。
- 不因为 A 的 setup 上限较大就说 100 MHz 已闭合。
