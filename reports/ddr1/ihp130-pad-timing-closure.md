# IHP130 DDR1 pad-boundary timing closure (first pass)

日期：2026-11-27

## 1. 结论

在 IHP130 行为 pad 边界上，SS PEX 参数不再必然失败：

- **写方向**：把 DQ 的 OE 延迟从 SS 默认 2332 ps 提前到 **1932 ps**（相对 DQS OE 提前 400 ps），CK=10/11 ns 的第一次写 tDS 违规消失。
- **读方向**：把 DQS 捕获延迟从默认 1500 ps 调到 **600 ps**，CK=10 ns、`READ_CORNER=+750 ps` 的 `read_error` 消失；500–750 ps 是可通过窗口，800 ps 起重新失败。
- **全矩阵**：`PAD_PROFILE=ss DQ_OE_PS=1932 DQS_CAPTURE_DELAY_PS=600` 下，CK=10/11/12 ns × `READ_CORNER=-750/0/+750 ps` 共 **9/9 PASS**。
- TT 用同一组补偿值也 9/9 PASS；TT 原始值（OE=1500、capture=1500）同样 9/9 PASS。

这不是 DDR1 signoff。它只证明行为 pad + 理想捕获延迟这一层可以被调到通过；真实 pad ring、`ck90`、adpll 延迟线、封装 RLC、SI/PI 仍未接入。

## 2. 写方向：DQ OE 提前 400 ps

SS 原始参数：TX=1865 ps、RX=1615 ps、OE=2332 ps。

| CK | corner | 原始结果 | 失败点 |
|---|---|---|---|
| 10 ns | 0 | FAIL | 第一次写 DQS 边沿 tDS，202796865 ps |
| 10 ns | -1 | FAIL | 同上 |
| 10 ns | +1 | FAIL | 同上 |
| 11 ns | 0 | FAIL | 第一次写 DQS 边沿 tDS，203078365 ps |
| 11 ns | -1 | FAIL | 同上 |
| 11 ns | +1 | FAIL | 同上 |
| 12 ns | 全部 | PASS | — |

CK=10 ns、corner 0 下扫 DQ OE：

| DQ_OE_PS | 结果 |
|---|---|
| 2232 | FAIL tDS |
| 2132 | FAIL tDS |
| 2032 | FAIL tDS |
| **1932** | **PASS** |
| 1832 | PASS |

单独把 DQS OE 往后推（2532/2732/2932/3132 ps）没有改善，仍在同一时间报 tDS；有效的是把 DQ 驱动使能提前，而不是把 DQS 边沿推后。

这给出一个明确的物理要求：**SS 角下 DQ 数据必须在 DQS 边沿前约 400 ps 建立**。当前 PEX 的 DQ OE 比 DQS OE 慢，是这个违规的直接来源。

## 3. 读方向：捕获延迟 600 ps

在 `DQ_OE_PS=1932`、CK=10 ns、`READ_CORNER=+750 ps` 下扫 `DQS_CAPTURE_DELAY_PS`：

| capture (ps) | 结果 |
|---|---|
| 0 | 数据字节错位：`got=c3fc0300 expected=3ac3fc03` at 203305000 |
| 200 | 同上 |
| 400 | 同上 |
| **500** | **PASS** |
| **550** | **PASS** |
| **600** | **PASS** |
| **650** | **PASS** |
| **700** | **PASS** |
| **750** | **PASS** |
| 800 | `PHY fault read=1 DFI=0` at 203285001 |
| 850–3500 | 同上，失败时间不变 |

读路径对捕获点很敏感：太早是字节错位，太晚进入 `read_error`；当前行为模型在 500–750 ps 有窗口，取 600 ps。

## 4. 全矩阵

`PAD_PROFILE=ss DQ_OE_PS=1932 DQS_CAPTURE_DELAY_PS=600`：

```
DDR1_LOOP_PASS ck=10000ps offset=0ps
DDR1_LOOP_PASS ck=10000ps offset=-750ps
DDR1_LOOP_PASS ck=10000ps offset=750ps
DDR1_LOOP_PASS ck=11000ps offset=0ps
DDR1_LOOP_PASS ck=11000ps offset=-750ps
DDR1_LOOP_PASS ck=11000ps offset=750ps
DDR1_LOOP_PASS ck=12000ps offset=0ps
DDR1_LOOP_PASS ck=12000ps offset=-750ps
DDR1_LOOP_PASS ck=12000ps offset=750ps
```

TT 同一组补偿值也 9/9 PASS；原生 `sim/ddr1.sh` 仍是 9 角 + training 全 PASS。

## 5. 边界与下一步

仍未闭合：

1. `DQ_OE_PS=1932` 是行为 pad 参数，不是版图/SPICE 证据。需要确认推荐尺寸 `XRDRIVER w=12u` 的 OE 路径能否做到 1932 ps，或改 pad ring / OE 缓冲。
2. `DQS_CAPTURE_DELAY_PS=600` 是理想 `#delay`，不是 adpll 延迟线。`ddr_dqs_delay_adpll` 仍未实例化进 `ddr1_top`，`TAP_BITS=4`。
3. 读窗口 500–750 ps 只是 CK=10 ns、`+750 ps` 单点扫参；还需要全 PVT、全 corner、jitter/SSO 下的窗口。
4. 封装 RLC 还未接到 pad PEX 后重跑；QFN40/QFN48 仍未冻结。
5. `ck90` 仍为空，数字后端仍是 bring-up SDC。

下一步优先级：

- 用 SPICE 验证 `XRDRIVER` 的 OE 上升路径能否提前 400 ps，不能则改 pad ring 的 DQ/DQS 驱动分配。
- 把 `DQS_CAPTURE_DELAY_PS` 替换成 adpll 延迟线接口，至少在 `ddr1_top` 里留出 `UPDATE_IDLE/TAP_VALID/TAP_VALUE/TAP_READY`。
- 在 `PAD_PROFILE=ss` 下把 600 ps 窗口扫到全 CK/corner，形成可签核的 capture 窗口表。

## 6. 复跑

```sh
cd /grid/ddr-phy

# SS 原始：仍失败，作为边界证据
PAD_PROFILE=ss PYTHON=/tmp/litedram-venv/bin/python sh sim/ddr1_ihp130.sh

# SS 补偿：9/9 PASS
PAD_PROFILE=ss DQ_OE_PS=1932 DQS_CAPTURE_DELAY_PS=600 \
  PYTHON=/tmp/litedram-venv/bin/python sh sim/ddr1_ihp130.sh

# TT
PAD_PROFILE=tt DQS_CAPTURE_DELAY_PS=600 \
  PYTHON=/tmp/litedram-venv/bin/python sh sim/ddr1_ihp130.sh

# 原生数字闭环
PYTHON=/tmp/litedram-venv/bin/python sh sim/ddr1.sh
```
