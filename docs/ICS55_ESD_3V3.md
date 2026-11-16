# ics55 的 3.3 V ESD：设计研究，不是现成单元

状态：**STUDY_ONLY。没有 3.3 V ESD 表征，没有 TLP/HBM 数据，不能把 ics55 SDR pad 标成已支持。**
本文只记录“缺 3.3 V ESD 二极管 SPICE 卡”之后的可选路线和需要的证据，不选尺寸、不签核。

## 1. 问题

- ics55 的 foundry SPICE 只有 1.2 V（`dio_core.mdl`）和 2.5 V（`dio_io25.mdl`）二极管；没有 `dio_3p3_*` 的模型卡。
- LVS 认识 `dio_3p3_pp_nw_lp`，3.3 V IO 库 CDL（`ICSIOA_N55_3P3.cdl`）也实例化它，但那是**版图/网表名**，没有可跑的 `.model`。
- `pdk_rules` / `specs/pads/devices/ics55.yaml` 因此把 `DIODE_TO_VSSIO`、`DIODE_TO_VDDIO`、`DIODE_CLAMP` 保持 `null`，`emit_pads.py` 不生成 ics55 SDR SPICE。把 `dio_2p5_*` 改名成 3.3 V 是禁止的。

## 2. 可选路线

### A. 自绘 GGNMOS / GGPMOS 钳位（推荐做原型）

用 ics55 已有的 3.3 V overdrive 器件 `nmod3p3_lp` / `pmod3p3_lp`：

```text
PAD ---- drain  nmod3p3_lp  source/bulk ---- VSSIO
                 gate ---- VSSIO（经栅电阻）
PAD ---- drain  pmod3p3_lp  source/bulk ---- VDDIO
                 gate ---- VDDIO（经栅电阻）
VDDIO -- drain  nmod3p3_lp  source/bulk ---- VSSIO
                 gate ---- VSSIO（经栅电阻）
```

- 优点：不需要缺失的 3.3 V 二极管模型；器件是 PDK 给 3.3 V IO 用的 overdrive 管；可作为独立 ESD 测试结构先流片。
- 缺点：BSIM4 模型**不描述 snapback**，SPICE 只能看关态漏电和导通电阻，不能证明触发/保持电压；栅电阻、触发电路、版图指条和镇流都需要 TLP 迭代。
- 关键未知：3.3 V 下的栅氧/结寿命、触发电压、保持电压、二次击穿电流、latch-up。

### B. 用 2.5 V 二极管版图做“定制 3.3 V 二极管”

- 优点：结构简单，和现有 PAD 二极管拓扑一致。
- 缺点：没有 3.3 V 模型卡；2.5 V 器件的结/氧化层在 3.3 V 下的可靠性未表征；仅放大面积不改变击穿电压。不能把 `dio_2p5_*` 直接改名。
- 只有在 foundry 给出 3.3 V 卡，或用 TLP/HTOL 数据证明 2.5 V 版图可迁移时才成立。

### C. 例化现成 `P65_1233_*` GPIO 的 ESD 网络

- 优点：厂商已经做过 3.3 V IO。
- 缺点：它是完整 GPIO，不是本设计的 pad；CDL 里仍然引用缺失的 `dio_3p3_pp_nw_lp`；架构上也不允许把现成 GPIO 当自研 pad。只能作为结构参考。

## 3. 已落地的 STUDY_ONLY 原型

- 规格：`specs/pads/ics55_esd_3v3.yaml`（12 个 W/L/NF/R 参数全 `null`）。
- 模板：`specs/pads/templates/ics55_esd_3v3.spice.tpl`。
- 生成器/校验：`generator/emit_ics55_esd.py`、`generator/check_ics55_esd.py`。
- 产物：`sch/pads/ics55/esd_ggnmos_3v3.spice`、`esd_ggnmos_3v3_manifest.json`、`esd_ggnmos_3v3_README.md`、`reports/ics55_esd_3v3.md`。
- 复现：`sh sim/ics55_esd.sh`。

产物明确标 **STUDY_ONLY / NOT SIMULATABLE / NOT A QUALIFIED ESD CELL**；没有绑定进 `specs/pads/devices/ics55.yaml` 的 ESD 槽位，也不参与 `emit_pads.py`。它只是给版图和 TLP 评审用的拓扑原型。

## 4. 推荐顺序

1. **先做 A 的独立测试结构**：GGNMOS / GGPMOS / 电源钳位各一个，带栅电阻和多种指条/间距；不接 SDR PHY。
2. 用 TLP（或至少 HBM 枪 + 漏电）测触发/保持/二次击穿；记录 3.3 V、125°C 的关态漏电。
3. 把测得的 TLP 结果和 BSIM 关态/导通仿真对齐；如果模型不覆盖 snapback，明确写“SPICE 不预测 ESD”。
4. 只有通过 TLP/HBM/latch-up 后，才把 `ics55.yaml` 的 ESD 槽位绑定到自定义单元，并把 `custom_esd.status` 从 `STUDY_ONLY` 改成 `CHARACTERIZED`。
5. 在这之前，ics55 SDR 仍保持 `TBD` / 不生成 SPICE；DDR1 的 2.5 V VREF 只用 `dio_2p5_*`，且仍是 topology only。

## 5. 需要的证据

| 证据 | 为什么 |
|---|---|
| TLP I-V（触发、保持、It2） | GGNMOS 的核心；BSIM 不提供 |
| HBM / CDM 目标与实测 | 没有 HBM 目标就不能谈 ESD 等级 |
| 3.3 V、125°C 关态漏电 | overdrive 管在 3.3 V 下的可靠性 |
| 栅氧寿命 / HTOL | 2.5 V 命名器件在 3.3 V 下不是已表征的 3.3 V 器件 |
| latch-up / guard ring DRC | 自绘 ESD 的版图规则 |
| 与 foundry 3.3 V IO 单元的对照 | 证明自绘结构不弱于厂商方案 |

## 6. 不这样做

- 不把 `dio_2p5_*` 改名成 3.3 V，不把它的 `bv≈10 V` 当成 3.3 V 额定。
- 不把 BSIM 的 `.op`/`.dc` 当成 ESD 触发/保持曲线。
- 不因为 GGNMOS 能网表就改 `ics55.yaml` 的 `status` 或 `NO_GO`。
- 不把 `P65_1233_*` GPIO 直接放进本设计的 pad。
- 不在没有 TLP/HBM 数据时声称 ics55 SDR 已支持。
