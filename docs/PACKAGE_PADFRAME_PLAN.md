# IHP130 DDR1 封装与 padring 方案（第一轮）

状态：**封装/padring 方向已落地到可复现的 QFN40 coupon 与一阶 RLC；仍未签核。**
本文不改变 `signoff=false` / IHP130 NO_GO。它回答三件事：QFN 24/28/32 是否够、参考工程能提供什么、封装寄生对当前 SS tDS 失败有多大影响。

## 1. 结论

1. **全 x8 DDR1 不能用 QFN24/28/32。** 32 根信号本身已经占满 QFN32 的 32 个 lead，没有任何 VDDIO/VSSIO/VDD/VSS/VREF 引脚。即使把 VREF 片上生成、电源全放 exposed pad，VDDIO/VSSIO 仍需要独立 lead；QFN32 不够。
2. **QFN40 6x6 是能装下全 x8 的最小标准封装。** 32 signal + 7 power/reference = 39，剩 1 个 NC。若希望每个电源/地有 2 个 lead、并留 route/ground 余量，选 **QFN48 7x7**。
3. **QFN32 只在缩减接口时成立。** 例如 x4、A0–A11、5 个电源脚，刚好 32；这已经不是当前 `MT46V32M8` x8 + 13 地址位的接口。
4. **封装寄生不是当前 SS 10/11 ns tDS 失败的主因。** QFN40 参考 bondwire 的 50 Ω 保守 L/R 上界为 37–54 ps；Open-Padrings 32 的 pad→core SPEF 为 370–492 Ω / 0.050–0.086 pF，对应约 19–42 ps。两者串起来约 56–96 ps，仍小于第一次写 DQS 边沿的 168 ps 违规量。剩余主因仍是 pad TX/OE 延迟与 DQS 捕获路径。
5. **不要直接把 Open-Padrings 的数字 padframe 当 DDR padring。** 它的 SPEF 路线电阻是数欧百欧级，适合小电流数字 IO，不适合 30 mA SSTL-2 输出。DDR padring 必须用宽金属、低阻 route，并把 package RLC 加在 pad PEX 之外，而不是替代 pad PEX。

## 2. 参考工程的实际内容

| 参考 | 已核对的事实 | 对本项目的作用 |
|---|---|---|
| `iic-jku/ihp-sg13g2-ams-chip-template` @ `789d094` | 1.6 mm × 1.6 mm die，32 bondpad（8/边），pad pitch 114 µm、opening 65.8 µm；`packaging/config.yaml` 把 `OP_QFN32_A4_FIT` 映射到 32 die pad；`result.md` 的 bondwire 长 1296–1701 µm；`packaging/scripts/run_bondplan.py` 可从 die GDS + Europractice package library 自动生成 bondplan | 直接给出 QFN32 的 bondplan 流程、pad 检测、lead 几何、线长检查；可复用到 QFN40 coupon |
| `KrzysztofHerman/Open-Padrings` @ `c795072` | 24/28/32 三个 padframe；32 版 die 1.28 mm × 1.28 mm，32 个 IO + 4 个 power pad，pad pitch 114 µm、opening 65.8 µm；`final/spef/nom/...spef` 有 pad→core RC；`final/gds`、`lef`、`lib`、`sdf` 是 LibreLane 生成视图 | 证明“参考 padring 上直接求 SPEF”可行；同时暴露数字 padframe 的 route R 过大，不能直接用于 SSTL-2 |
| `chipfoundry/openframe_user_project` | sky130 openframe wrapper 的 DEF/LEF/GDS/LIB/SDC/signoff 全套；wrapper 是预定义 openframe 里的 user area，不是可配置 padring | 用作“全芯片 wrapper + 固定 padframe + signoff 视图”的组织方式参考 |
| `chipfoundry/double_wide_openframe` | `librelane/padframe/` 有 `config.yaml`、`pad_lists.yaml`、`pad_pos.tcl`、`pad_cfg.tcl`、`bridge_*`、`run_padframe.py`；63 GPIO + 24 power bond pad，按边排序，带 clamp/power bridge | 用作 padring 生成、按边 pin 列表、power clamp 连接、DRC/LVS 脚本结构的参考；不是封装参考 |

## 3. 引脚预算

全 x8 DDR1（`MT46V32M8`，13 row / 10 column / 4 bank）需要的 off-chip 信号：

| 组 | 数量 |
|---|---:|
| DQ0–DQ7 | 8 |
| DQS / DM | 2 |
| CK / CK# | 2 |
| A0–A12 | 13 |
| BA0–BA1 | 2 |
| CKE / CS# / RAS# / CAS# / WE# | 5 |
| **signal 小计** | **32** |
| VDDIO / VSSIO / VDD / VSS / VREF | 5（最少） |
| **合计（最少）** | **37** |

若 VDDIO/VSSIO 各 2 个、VDD/VSS 各 1 个、VREF 1 个，则 32 + 7 = **39**。

| 封装 | lead 数 | 全 x8 可行性 |
|---|---:|---|
| QFN24 | 24 | 不可行 |
| QFN28 | 28 | 不可行 |
| QFN32 | 32 | 仅“32 signal + 0 power”或缩减到 x4/少地址；全 x8 不可行 |
| QFN40 6x6 | 40 | 可行：39 used + 1 NC；最小标准封装 |
| QFN48 7x7 | 48 | 可行且推荐：39 used + 9 spare，可加地/电源与 route 余量 |

## 4. QFN40 coupon 与一阶寄生

为了不空算，按 IHP AMS template 的 `run_bondplan.py` 做了一个 2.0 mm × 2.0 mm、40 pad（10/边）、70 µm opening、114 µm pitch 的 coupon die，放进 `OP_QFN40_6x6mm`，得到真实 bondplan：

- bondwire：**1771–2459 µm**，mean 2047 µm；
- 最小线-线 gap 在实际 pinout 下有 -25 µm 的告警（pin 29/30 附近），说明 40 lead 的边角 assignment 还要重排；这是 pinout 问题，不是封装不可行；
- 40 根线全部可布，最大 lead skew 4.3°。

按 25 µm 金线、200 µm 铜 leadframe、0.1 pF 集中并联电容计算：

| 封装/参考 | wire 长 (µm) | L_total (nH) | R_total (Ω) | 50 Ω 的 L/R 上界 (ps) |
|---|---:|---:|---:|---:|
| QFN32 template，1.6 mm die | 1296–1701 | 1.31–1.77 | 0.070–0.091 | 26–35 |
| QFN40 coupon，2.0 mm die | 1771–2459 | 1.85–2.69 | 0.094–0.128 | 37–54 |

数据：`results/ihp130/package/qfn40_pkg_rlc.json`、`qfn32_template_pkg_rlc.json`；每 pin 表在 `qfn40_coupon_result.md`；可复现脚本 `generator/extract_qfn_rlc.py`；ngspice 一阶模型 `spice/package/qfn40_pkg.spice`。

这些数字是 **一阶几何+RLC**，不是 3D EM/IBIS。它们足以回答“量级”，不能替代封装厂/电磁场提取。

## 5. 对 SS tDS 失败的影响

当前 SS 失败是第一次写 DQS 边沿的 tDS 违规 168 ps（CK=10 ns 角）。把封装与 padring 的保守上界相加：

- QFN40 封装：54 ps（最坏 L）；
- Open-Padrings 32 的数字 route：492 Ω × 0.086 pF ≈ 42 ps（最坏 RC）；
- 合计 ≈ 96 ps。

仍小于 168 ps。并且这两项不是同一路径上的全部延迟：封装 L 对 50 Ω 负载的实际阶跃延迟通常小于 `L/50` 上界；padring route 只对高阻接收节点近似 RC。结论是：

**封装/padring 会把余量进一步吃掉，但不能解释 SS 10/11 ns 的第一次写 tDS 失败；应先修 pad TX/OE 与 DQS 捕获，再谈封装签核。**

这也意味着“用 package RLC 替换行为 pad 模型”不能解决 SS 失败。正确做法是：

1. 保留 `ihp130_sstl2_dq_model.sv` 作为数字 co-sim 的 pad 边界；
2. 在晶体管级 `sstl2_dq_pex.spice` 的 PAD 端口外接 `qfn40_pkg` 子电路；
3. 数字 TB 只给 DQ/DQS 加一个有界的 package skew derate（当前建议 ≤50 ps），不要把 RLC 当成新的 `#delay` 行为模型。

## 6. 建议的 QFN40 初版 pinout（待冻结）

40 lead，39 used + 1 NC。按边分组，DQ/DQS 集中在北边，地址在南/东，控制和 VREF 在西：

| 边 | pin | 信号 |
|---|---:|---|
| W | 1–10 | CK, CK#, VDDIO, VSSIO, VREF, CKE, CS#, RAS#, CAS#, WE# |
| S | 11–20 | A0–A9 |
| E | 21–30 | A10, A11, A12, BA0, BA1, VDDIO, VSSIO, VDD, VSS, NC |
| N | 31–40 | DQ0, DQ1, DQ2, DQ3, DQS, DQ4, DQ5, DQ6, DQ7, DM |

这个分组只优化了“DQ/DQS 同边、控制同边、电源靠近两边”，还没有做 lead 间耦合、地回流、bondwire crossing 和封装厂 rule check。QFN40 的 pin 29/30 bond 告警说明最终 pinout 必须重新跑 `run_bondplan.py` 并消掉负 gap。

## 7. 下一步（按顺序）

1. **冻结封装**：QFN40 6x6（最小）或 QFN48 7x7（推荐）。先确认封装厂是否有 `OP_QFN40_6x6mm` 对应的真实 leadframe 图纸/厚度/金线直径；当前 Europractice 图只是 drawing。
2. **冻结 pinout**：用第 6 节做起点，重跑 bondplan，要求 min gap > 0、无 crossing、DQ/DQS 线长差 < 300 µm。
3. **做 40-pad ring**：把 32 个 SSTL-2 lane + 7 个电源/参考 pad 放进 2.0 mm die；padring route 用宽金属，目标单段 R < 50 Ω，而不是参考数字 padframe 的 370–492 Ω。
4. **PEX**：对 x8 padring + 代表性 DQ/DQS 做 RC 提取；把 `qfn40_pkg.spice` 接到 PEX 的 PAD 端口，重跑 TT/SS 的 `char_ihp130_sstl2.py`。
5. **再跑 SS 10/11 ns**：如果 tDS 仍失败，优先修 pad TX/OE 和 DQS capture；封装只作为已量化的加项。

## 8. 复现

QFN40 coupon 的生成与 bondplan（需要 IHP AMS template 的 `packaging/scripts/run_bondplan.py` 和 `EP_PACKAGES_08022018.gds`）：

```sh
# 1) coupon GDS: 2.0 mm die, 40 pads, 70 um opening, 114 um pitch
#    见 results/ihp130/package/qfn40_coupon_config.yaml 的 DIE_GDS 约定
# 2) bondplan
cd results/ihp130/package
python3 /path/to/ihp-sg13g2-ams-chip-template/packaging/scripts/run_bondplan.py \
    qfn40_coupon_config.yaml DESIGN_NAME=qfn40_padring_coupon VERSION=0.1
# 3) RLC
python3 generator/extract_qfn_rlc.py \
    --bondplan results/ihp130/package/qfn40_coupon_result.md \
    --package OP_QFN40_6x6mm --die-size-um 2000 --pad-pitch-um 114 \
    --output results/ihp130/package/qfn40_pkg_rlc.json
```

`qfn40_coupon_config.yaml` 里 `PACKAGE_LIBRARY_GDS` 指向模板的 `EP_PACKAGES_08022018.gds`；该文件是 Europractice drawing，不是硅验证 leadframe。所有 RLC 结果 `signoff=false`。

