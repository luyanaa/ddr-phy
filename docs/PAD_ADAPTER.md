# P0-3：Pad Adapter 与 Capability Report

状态：**数字侧适配层与能力判定已建立；真正的 pad 电路仍未画、仍未表征。**
四套硅工艺后端全部 `NO_GO`，唯一可用后端是 `generic_sim`（验证专用）。
`rtl/phy_io_adapter.sv` 现已由 `rtl/sdram_phy_top.sv` 例化（仅验证接线，未进综合）。

## 1. 交付物

| 文件 | 作用 |
|---|---|
| `rtl/phy_io_adapter.sv` | 数字侧 pad 适配器，按 `BACKEND` 绑定 I/O 后端 |
| `sim/pad_cell_generic.sv` | 行为级双向 LVTTL pad（上电 Hi-Z、OE 延时、争用检测） |
| `backends/*.yaml` | 5 份后端能力记录（generic_sim + 4 套 PDK） |
| `generator/check_capabilities.py` | 校验能力记录并生成报告 |
| `reports/capability_report.md` / `.json` | 生成的 Go/No-Go 报告 |
| `tb/tb_pad_adapter.sv`、`sim/pad.sh` | 适配器契约测试 |
| `docs/PAD_ADAPTER.md` | 本文件 |

## 2. 适配器契约

`phy_io_adapter` 把核心域（VDD）和引脚域（VDDIO）分开，暴露：

- 核心侧：`core_cmd`（打包的命令/地址/DQM 总线）、`core_dq_o`、`core_dq_oe`、`core_dq_i`、`core_ck`
- 引脚侧：`pad_cmd`、`pad_dq`（inout）、`pad_ck`
- 配置/状态：`io_power_ok`、`pad_config`、`pad_ready`、`contention`

三个后端：

| BACKEND | 含义 | 状态 |
|---|---|---|
| 0 `generic_sim` | 行为级 pad，验证专用 | 可用，`SIM_ONLY` |
| 1 `asic_pad` | 需要集成方提供合格 IO macro | 未提供 |
| 2 `fpga_io` | 本 ASIC 项目范围外 | 不支持 |

**关键约束**：没有"回退到核心标准单元直接驱动外部 DQ"的路径。选中不支持的后端时，适配器在 `t=0` 打印 `FATAL` 并 `$finish`，而不是悄悄生成一个不能驱动 SDRAM 的纯核心网表。`sim/pad.sh` 里有一条负向测试专门验证这一点。

`pad_config` 是后端专属（驱动强度、slew、上下拉）；`generic_sim` 没有模拟旋钮，故意不使用它。

`pad_cmd` / `pad_ck` 在 `generic_sim` 下是直接透传——**这只是把义务显式化，不是履行了义务**。真正的命令/时钟输出 pad 仍属于 `asic_pad` 后端。

## 3. 能力报告结果

由 `generator/check_capabilities.py` 从 `backends/*.yaml` 生成，判据不是手写结论：

- `status: supported` 且所有 gate 关闭、所有 pad 标志为真、`tOE_on/off` 非 null → `GO`
- `status: supported` 但证据不全 → 脚本报错退出（防止虚假声明）
- 行为级后端 → `SIM_ONLY`
- 其余 → `NO_GO`

| 后端 | PDK | 核心/VDDIO | 现有 IO 库 | 判定 |
|---|---|---|---|---|
| generic_sim | — | — | 行为模型 | SIM_ONLY |
| sky130 | sky130A | 1.8 / 3.3 V | `sky130_fd_io` | NO_GO |
| gf180mcu | gf180mcuD | 3.3 / 3.3 V | `gf180mcu_fd_io`（5 V） | NO_GO |
| ihp130 | ihp-sg13g2 | 1.2 / 3.3 V | `sg13g2_io` | NO_GO |
| ics55 | icsprout55-pdk | 1.2 / 3.3 V | `ICsprout_55LLULP1233_IO_251013` | NO_GO |

四套 PDK 的 IO 库本地都确实存在（已探测），但按 `docs/ARCHITECTURE.md` §5 它们只是结构参考，**不是本设计的 pad**：本设计要求四套工艺共用一张手工画的原理图。所有后端共同缺的是：

- G1：手工 3.3 V 双向 LVTTL pad（含 ESD、电平搬移、上电 Hi-Z）
- G5：`tOE_on` / `tOE_off` / slew / 输入门限的表征值（报告里全部是 `null`）
- G6：clock forwarding 与读采样相位的已表征延迟/PLL
- G4：没有已表征延迟单元，所以连"固定相位"声明也被保留

另外各自的具体缺口写在 `backends/*.yaml` 的 `notes` 里：gf180 的 5 V GPIO 不能接 3.3 V SDRAM、ihp130 的 2.5 V 工作点未表征、ics55 的 3.3 V ESD SPICE 卡缺失且厂商 SPICE 只供评估、sky130 的 5 V/11 V 只是器件类别而非工作电压。

## 4. 契约测试

`sh sim/pad.sh` 全部通过：

| 用例 | 结果 |
|---|---|
| 上电期间 `io_power_ok=0`，即使 OE 为高 DQ 仍为 Z | PASS |
| `pad_ready` 在供电就绪前为低 | PASS |
| OE 开启不是瞬时（`T_OE_ON`） | PASS |
| 供电就绪后 DQ 正确驱动 | PASS |
| 外部驱动经 pad 到达 `core_dq_i` | PASS |
| OE 关闭不是瞬时（`T_OE_OFF`） | PASS |
| 释放后 DQ 回到 Z | PASS |
| 双方同时驱动且值不同 → `contention` | PASS |
| 不支持的后端大声失败、不回退核心单元 | PASS |

## 5. 与 P0-2 的关系

P0-2 的 `T_BOARD` 是往返延迟占位数；P0-3 把其中一个来源拆开了：pad 的 `tOE_on/off`、输出 pad 延时、输入门限。但它们仍是 `null`——**28 个 TBD 项没有减少**。只有等 `backends/*.yaml` 里 `toe_on_ps` / `toe_off_ps` 被真实表征值填上，P0-2 的扫描表才能从"如果 B 是 X"变成"实际 B 是 Y"。

这也是脚本把 `tOE_on/off` 列为 `GO` 必要条件的原因：不能一边说支持、一边把最关键的 pad 延时留空。

## 6. 不这样做

- 不把现有 GPIO 库当成本设计的 pad，不把 IO 库存在当成"3.3 V pad 可用"。
- 不把 `generic_sim` 的行为级 pad 说成可综合、可流片或有电气意义。
- 不把 `pad_cmd` / `pad_ck` 的透传说成命令/时钟输出 pad 已完成。
- 不因为"适配器写好了"就把任一后端从 `NO_GO` 改成 `GO`；改判定必须改能力证据并重跑生成器。
- 不填 `tOE_on/off` 的猜测值；没有表征就是 `null`。
