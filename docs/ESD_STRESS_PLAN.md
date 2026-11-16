# SDR pad ESD 应力与资格计划

状态：**计划，没有任何 TLP/HBM/CDM/latch-up 实测数据。**
当前只有反向泄漏测量（`reports/pad_char_*.json` 的 `iesd_max`）和 ics55 的 STUDY_ONLY 原型；不能把泄漏测量说成 ESD 资格。

## 1. 范围

- 目标 pad：SDR 3.3 V 双向 pad（gf180mcuD / sky130 / IHP SG13G2）。
- ics55：没有 3.3 V 二极管模型卡，走自绘 GGNMOS/GGPMOS 路线，见 `docs/ICS55_ESD_3V3.md`。
- 结构：PAD→VSSIO、PAD→VDDIO、VDDIO→VSSIO 三条路径；单器件测试结构和完整 pad 各一套。
- 不在本文：DDR1 2.5 V VREF pad 的 ESD（等 DDR1 pad 落地后再做）。

## 2. 测试结构

每个 PDK 先做独立结构，不等完整 pad：

```text
PAD ---- D_up ---- VDDIO
PAD ---- D_dn ---- VSSIO
VDDIO -- clamp --- VSSIO
PAD ---- GGNMOS -- VSSIO      (ics55 / 备用)
PAD ---- GGPMOS -- VDDIO      (ics55 / 备用)
```

- 单器件结构：每种器件至少 3 个面积/指条/间距点，带 guard ring 和电源钳位。
- 完整 pad：选中尺寸后复制到 `sch/pads/<backend>/`，再做 TLP/HBM。
- 每个结构都要有独立的 PAD、VDDIO、VSSIO、VSS 开尔文连接，避免测试夹具 IR drop。

## 3. 测量清单

| 测量 | 目的 | 现在有没有 |
|---|---|---|
| TLP I-V：It1、Vh、It2 | 触发/保持/二次击穿；GGNMOS 的核心 | 没有 |
| HBM（目标等级 TBD） | 系统级 ESD 等级 | 没有 |
| CDM（目标等级 TBD） | 封装/装配放电 | 没有 |
| 3.3 V / 125°C 反向漏电 | 正常工作和热载流子 | 只有 SPICE 反向泄漏（`iesd_max`） |
| latch-up（JESD78 类） | 自绘 ESD/guard ring | 没有 |
| HTOL / 栅氧寿命 | 3.3 V 下 overdrive 管的长期可靠性 | 没有 |
| DRC/LVS/天线 | 版图合法性 | 没有 |

目标 HBM/CDM 等级必须由产品/封装要求给出；本文不编一个“2 kV”当作已定指标。

## 4. 各 PDK 的器件与已知边界

| PDK | 3.3 V 路径 | 已知边界 |
|---|---|---|
| gf180mcuD | `diode_nd2ps_03v3` / `diode_pd2nw_03v3`；`nfet_03v3` / `pfet_03v3` | 模型卡可用；ESD 面积/指条/HBM 目标仍 TBD |
| sky130 | `diode_pw2nd_11v0` / `diode_pd2nw_11v0`；`nfet_g5v0d10v5` / `pfet_g5v0d10v5` | 11 V 是器件类名，不是工作电压；ESD 面积/HBM TBD |
| IHP SG13G2 | `diodevdd_2kv` / `diodevss_2kv`；`sg13_hv_nmos` / `sg13_hv_pmos` | 2 kV 是 ESD 单元名，不是已测 HBM 等级；2.5 V DDR1 仍未表征 |
| ics55 | 自绘 `nmod3p3_lp` / `pmod3p3_lp` GGNMOS/GGPMOS | 没有 3.3 V 二极管模型；BSIM 不描述 snapback；STUDY_ONLY |

## 5. 通过标准（待产品定义）

- 反向漏电：在 3.3 V、125°C 下低于产品目标；目标值未定，不能用“看起来很小”代替。
- TLP：It2 高于目标应力；Vh 不低于工作电压，避免闩锁。
- HBM/CDM：达到产品/封装要求的等级；没有目标就不写“通过”。
- latch-up：按 JESD78 类方法通过；guard ring/间距按 PDK 规则。
- 版图：DRC/LVS/天线 clean；PEX 后重复关键路径。

## 6. 不这样做

- 不把 `iesd_max`（SPICE 反向泄漏）说成 ESD 资格或 HBM 等级。
- 不把 BSIM 的 `.op`/`.dc` 说成 TLP 触发/保持曲线。
- 不把 `diodevdd_2kv` / `diode_pw2nd_11v0` 的名字当成已测 HBM 等级。
- 不在没有目标等级时编一个 HBM/CDM 数字。
- 不因为 GGNMOS 能网表就改 ics55 的 `NO_GO` 或绑定 SDR pad。
