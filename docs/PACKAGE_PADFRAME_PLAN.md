# IHP130 DDR1 封装与 padring 方案（第一轮）

状态：**QFN40 与 QFN48 两个 coupon 版本均已完成 bondplan + 一阶 RLC；仍未签核。**
本文不改变 `signoff=false` / IHP130 NO_GO。它回答三件事：QFN 24/28/32 是否够、两个候选封装各是什么量级、封装寄生对当前 SS tDS 失败有多大影响。

## 1. 结论

1. **全 x8 DDR1 不能用 QFN24/28/32。** 32 根信号本身已经占满 QFN32 的 32 个 lead，没有任何 VDDIO/VSSIO/VDD/VSS/VREF 引脚。即使把 VREF 片上生成、电源全放 exposed pad，VDDIO/VSSIO 仍需要独立 lead；QFN32 不够。
2. **QFN40 6x6 是能装下全 x8 的最小标准封装。** 32 signal + 7 power/reference = 39，剩 1 个 NC。
3. **QFN48 7x7 是更稳的版本。** 48 lead 可以给 32 signal + 16 power/ground，bondplan 也更干净：min gap +67 µm、max lead skew 2.0°；代价是 die 从 2.0 mm 增到 2.4 mm、最坏 L 从 2.69 nH 增到 3.04 nH。
4. **QFN32 只在缩减接口时成立。** 例如 x4、A0–A11、5 个电源脚，刚好 32；这已经不是当前 `MT46V32M8` x8 + 13 地址位的接口。
5. **封装寄生不是当前 SS 10/11 ns tDS 失败的主因。** QFN40 的 50 Ω 保守 L/R 上界 37–54 ps，QFN48 为 44–61 ps；Open-Padrings 32 的 pad→core SPEF 为 370–492 Ω / 0.050–0.086 pF，对应约 19–42 ps。两者串起来约 56–103 ps，仍小于第一次写 DQS 边沿的 168 ps 违规量。剩余主因仍是 pad TX/OE 延迟与 DQS 捕获路径。
6. **不要直接把 Open-Padrings 的数字 padframe 当 DDR padring。** 它的 SPEF 路线电阻是数百欧级，适合小电流数字 IO，不适合 30 mA SSTL-2 输出。DDR padring 必须用宽金属、低阻 route，并把 package RLC 加在 pad PEX 之外，而不是替代 pad PEX。

## 2. 参考工程的实际内容

| 参考 | 已核对的事实 | 对本项目的作用 |
|---|---|---|
| `iic-jku/ihp-sg13g2-ams-chip-template` @ `789d094` | 1.6 mm × 1.6 mm die，32 bondpad（8/边），pad pitch 114 µm、opening 65.8 µm；`packaging/config.yaml` 把 `OP_QFN32_A4_FIT` 映射到 32 die pad；`result.md` 的 bondwire 长 1296–1701 µm；`packaging/scripts/run_bondplan.py` 可从 die GDS + Europractice package library 自动生成 bondplan | 直接给出 QFN32 的 bondplan 流程、pad 检测、lead 几何、线长检查；已复用到 QFN40/QFN48 coupon |
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
| QFN48 7x7 | 48 | 可行：32 signal + 16 power/ground；无 NC，bondplan 更干净 |

## 4. QFN40 / QFN48 coupon 与一阶寄生

两个版本都用 IHP AMS template 的 `run_bondplan.py` 和 `EP_PACKAGES_08022018.gds` 生成。

**QFN40 版本**：2.0 mm × 2.0 mm die，40 pad（10/边），70 µm opening、114 µm pitch，放进 `OP_QFN40_6x6mm`：

- bondwire：**1771–2459 µm**，mean 2047 µm；
- 最小线-线 gap 在实际 pinout 下有 **-25 µm** 的告警（pin 29/30 附近），说明 40 lead 的边角 assignment 还要重排；这是 pinout 问题，不是封装不可行；
- 40 根线全部可布，最大 lead skew 4.3°。

**QFN48 版本**：2.4 mm × 2.4 mm die，48 pad（12/边），70 µm opening、114 µm pitch，放进 `OP_QFN48`：

- bondwire：**2056–2735 µm**，mean 2395 µm；
- 最小线-线 gap **+67 µm**，无负 gap；
- 48 根线全部可布，最大 lead skew 2.0°。

按 25 µm 金线、200 µm 铜 leadframe、0.1 pF 集中并联电容计算：

| 封装/参考 | die | wire 长 (µm) | L_total (nH) | R_total (Ω) | 50 Ω 的 L/R 上界 (ps) |
|---|---:|---:|---:|---:|---:|
| QFN32 template | 1.6 mm | 1296–1701 | 1.31–1.77 | 0.070–0.091 | 26–35 |
| QFN40 coupon | 2.0 mm | 1771–2459 | 1.85–2.69 | 0.094–0.128 | 37–54 |
| QFN48 coupon | 2.4 mm | 2056–2735 | 2.19–3.04 | 0.108–0.142 | 44–61 |

数据：`results/ihp130/package/qfn40_pkg_rlc.json`、`qfn48_pkg_rlc.json`、`qfn32_template_pkg_rlc.json`；每 pin 表在 `qfn40_coupon_result.md` 和 `qfn48_coupon_result.md`；可复现脚本 `generator/extract_qfn_rlc.py`；ngspice 一阶模型 `spice/package/qfn40_pkg.spice`、`spice/package/qfn48_pkg.spice`。

这些数字是 **一阶几何+RLC**，不是 3D EM/IBIS。它们足以回答“量级”，不能替代封装厂/电磁场提取。

## 5. 对 SS tDS 失败的影响

当前 SS 失败是第一次写 DQS 边沿的 tDS 违规 168 ps（CK=10 ns 角）。把封装与 padring 的保守上界相加：

- QFN40 封装：54 ps（最坏 L）；
- QFN48 封装：61 ps（最坏 L）；
- Open-Padrings 32 的数字 route：492 Ω × 0.086 pF ≈ 42 ps（最坏 RC）；
- 合计约 **96 ps（QFN40）到 103 ps（QFN48）**。

仍小于 168 ps。并且这两项不是同一路径上的全部延迟：封装 L 对 50 Ω 负载的实际阶跃延迟通常小于 `L/50` 上界；padring route 只对高阻接收节点近似 RC。结论是：

**封装/padring 会把余量进一步吃掉，但不能解释 SS 10/11 ns 的第一次写 tDS 失败；应先修 pad TX/OE 与 DQS 捕获，再谈封装签核。**

这也意味着“用 package RLC 替换行为 pad 模型”不能解决 SS 失败。正确做法是：

1. 保留 `ihp130_sstl2_dq_model.sv` 作为数字 co-sim 的 pad 边界；
2. 在晶体管级 `sstl2_dq_pex.spice` 的 PAD 端口外接 `qfn40_pkg` 或 `qfn48_pkg` 子电路；
3. 数字 TB 只给 DQ/DQS 加一个有界的 package skew derate（当前建议 ≤60 ps），不要把 RLC 当成新的 `#delay` 行为模型。

## 6. 两个初版 pinout（待冻结）

### 6.1 QFN40：39 used + 1 NC

| 边 | pin | 信号 |
|---|---:|---|
| W | 1–10 | CK, CK#, VDDIO, VSSIO, VREF, CKE, CS#, RAS#, CAS#, WE# |
| S | 11–20 | A0–A9 |
| E | 21–30 | A10, A11, A12, BA0, BA1, VDDIO, VSSIO, VDD, VSS, NC |
| N | 31–40 | DQ0, DQ1, DQ2, DQ3, DQS, DQ4, DQ5, DQ6, DQ7, DM |

QFN40 的 pin 29/30 bond 告警说明这个 pinout 必须重跑 `run_bondplan.py` 并消掉负 gap。

### 6.2 QFN48：32 signal + 16 power/ground

| 边 | pin | 信号 |
|---|---:|---|
| W | 1–12 | CK, CK#, VDDIO, VSSIO, VREF, CKE, CS#, RAS#, CAS#, WE#, VSS, VDD |
| S | 13–24 | A0–A11 |
| E | 25–36 | A12, BA0, BA1, VDDIO, VSSIO, VDD, VSS, VSSIO, VDDIO, VSS, VDD, VSSIO |
| N | 37–48 | DQ0, DQ1, DQ2, DQ3, DQS, DQ4, DQ5, DQ6, DQ7, DM, VSSIO, VDDIO |

QFN48 没有 NC：多出来的 9 个 lead 全部给 VDDIO/VSSIO/VDD/VSS。代价是 DQ/DQS 在北边 10 个 pad 中被 VSSIO/VDDIO 占掉两个，DQ bus 的间距需要再核对。

两个分组都只优化了“DQ/DQS 同边、控制同边、电源靠近两边”，还没有做 lead 间耦合、地回流、bondwire crossing 和封装厂 rule check。

## 7. 下一步（按顺序）

1. **二选一冻结封装**：QFN40 6x6（最小，1 NC，bond 有负 gap 待修）或 QFN48 7x7（更大、更干净、16 个电源/地）。先确认封装厂是否有对应真实 leadframe 图纸/厚度/金线直径；当前 Europractice 图只是 drawing。
2. **冻结 pinout**：用第 6 节做起点，两个版本都重跑 bondplan，要求 min gap > 0、无 crossing、DQ/DQS 线长差 < 300 µm。QFN48 目前已经满足 min gap > 0，QFN40 还需要重排 pin 29/30。
3. **做 pad ring**：QFN40 做 40-pad ring（32 signal + 7 power + 1 NC）；QFN48 做 48-pad ring（32 signal + 16 power/ground）。padring route 用宽金属，目标单段 R < 50 Ω，而不是参考数字 padframe 的 370–492 Ω。
4. **PEX**：对 x8 padring + 代表性 DQ/DQS 做 RC 提取；把对应 package 子电路接到 PEX 的 PAD 端口，重跑 TT/SS 的 `char_ihp130_sstl2.py`。
5. **再跑 SS 10/11 ns**：如果 tDS 仍失败，优先修 pad TX/OE 和 DQS capture；封装只作为已量化的加项。

## 8. 复现

两个 coupon 的生成与 bondplan（需要 IHP AMS template 的 `packaging/scripts/run_bondplan.py` 和 `EP_PACKAGES_08022018.gds`）：

```sh
# QFN40: 2.0 mm die, 40 pads, 70 um opening, 114 um pitch
python3 generator/gen_qfn_padring_coupon.py \
    --output results/ihp130/package/qfn40_padring_coupon.gds \
    --cell-name qfn40_padring_coupon --pads-per-side 10 \
    --die-um 2000 --edge-inset-um 287 --pitch-um 114 --pad-um 70
cd results/ihp130/package
python3 /path/to/ihp-sg13g2-ams-chip-template/packaging/scripts/run_bondplan.py \
    qfn40_coupon_config.yaml DESIGN_NAME=qfn40_padring_coupon VERSION=0.1
python3 ../../../generator/extract_qfn_rlc.py \
    --bondplan qfn40_coupon_result.md --package OP_QFN40_6x6mm \
    --die-size-um 2000 --pad-pitch-um 114 --output qfn40_pkg_rlc.json

# QFN48: 2.4 mm die, 48 pads, 70 um opening, 114 um pitch
python3 ../../../generator/gen_qfn_padring_coupon.py \
    --output qfn48_padring_coupon.gds \
    --cell-name qfn48_padring_coupon --pads-per-side 12 \
    --die-um 2400 --edge-inset-um 287 --pitch-um 114 --pad-um 70
python3 /path/to/ihp-sg13g2-ams-chip-template/packaging/scripts/run_bondplan.py \
    qfn48_coupon_config.yaml DESIGN_NAME=qfn48_padring_coupon VERSION=0.1
python3 ../../../generator/extract_qfn_rlc.py \
    --bondplan qfn48_coupon_result.md --package OP_QFN48 \
    --die-size-um 2400 --pad-pitch-um 114 --output qfn48_pkg_rlc.json
```

`qfn40_coupon_config.yaml` / `qfn48_coupon_config.yaml` 里 `PACKAGE_LIBRARY_GDS` 指向模板的 `EP_PACKAGES_08022018.gds`；该文件是 Europractice drawing，不是硅验证 leadframe。所有 RLC 结果 `signoff=false`。
