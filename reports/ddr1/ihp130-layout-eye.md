# IHP130 DDR1 版图与眼图导出（2026-11-27）

基线：`89d7f70`（`ddr1-ihp130`，pad 时序闭环第一轮）
范围：`LiteDRAM controller + DDR1 init + DDR1 PHY -> IHP130 harden -> QFN48 package assembly -> DQ write eye`

## 1. 结论

本轮把 IHP130 DDR1 的**数字全顶层**（LiteDRAM controller + `ddr1_init` + `ddr1_phy`）单独硬化成 GDS，并放进 QFN48 7×7 mm / 2.4 mm die 的封装 coupon，导出装配版图和版图预览。

同时用晶体管级 IHP130 SSTL-2 pad + QFN48 封装 RLC 生成了 **DQ write eye**：TT 和 SS 各 64 UI，5 ns UI。眼图不是读眼，也不是 SI/PI 签核；它只证明这条 pad + package 链路在标称/慢角下的电压开口。

## 2. 数字全顶层 harden

配置：

- `flow/config.ddr1_top.json`
- `flow/ddr1_top.sdc`
- `flow/prep_ddr1_top.sh`（`generator/emit_ddr1.py` 生成 CK=10 ns 束到 `flow/runs/ddr1_top_build/`）

LibreLane IHP130 `sg13g2_stdcell` 80/80 完成：

| 项目 | 结果 |
|---|---|
| DRC | 0 |
| LVS | 0 |
| 天线 | 0 |
| die | 645.61 × 664.33 µm |
| 标准单元 | 7,075 个，134,599 µm² |
| 全部实例（含 fill） | 32,136 |
| 利用率 | 33.6% |
| 典型功耗 | 7.41 mW |
| setup/hold | 无违例（worst setup +5.9 ps，worst hold +112 ps，见边界说明） |
| max-fanout 告警 | 104 |
| unannotated net | 112 |

产物：

- `results/ihp130/ddr1_top/gds/ddr1_top.gds`
- `results/ihp130/ddr1_top/def/ddr1_top.def`
- `results/ihp130/ddr1_top/spef/ddr1_top.spef`
- `results/ihp130/ddr1_top/lef/ddr1_top.lef`
- `results/ihp130/ddr1_top/lib/ddr1_top.lib`
- `results/ihp130/ddr1_top_layout.png`（GDS 渲染）

边界：

- SDC 仍是 bring-up：`sys_clk/ck/ck90/dqs_capture` 异步分组，I/O delay 是占位值；`WNS=0` 不能读成 DDR1 时序签核。
- 104 个 max-fanout 告警和 112 个 unannotated net 未清零。
- 该 harden 不含 SSTL-2 pad ring、电平搬移、VDDIO/VSSIO、封装和板级 SI/PI。

## 3. QFN48 封装装配图

`generator/compose_ddr1_layout.py` 把 `ddr1_top` GDS 放到 QFN48 coupon 的 2.4 mm die 中心：

- QFN48 7×7 mm body，2.4 mm die，48 pad，pin 1 在 W11。
- 数字 top 645.6 × 664.3 µm，占 die 约 7.5% 面积。
- 版图预览：`results/ihp130/ddr1_qfn48_assembly.png`
- 标注版：`results/ihp130/ddr1_qfn48_layout_sheet.png`
- GDS：`results/ihp130/ddr1_qfn48_assembly.gds`

这不是 connected padring：coupon 只有 bond pad，没有 SSTL-2 signal route、没有 bondwire、没有 package 3D EM。装配图只表达“封装占位 + 数字 top 落点”，不是可流片的 full-chip GDS。

## 4. DQ write eye

生成器：`generator/eye_ddr1_ihp130.py`
绘图：`sim/plot_ddr1_eye.py`

模型链：

- 晶体管级 `sch/pads/ihp130/sstl2_dq.spice`（IHP130 2.5 V SSTL-2 pad，TT/SS real models）。
- QFN48 package：`spice/package/qfn48_pkg.spice`，取最差 pin N48 的 `L=3.037 nH, R=0.142 Ω, C=0.1 pF`。
- 50 Ω 到 VTT，5 pF 负载。
- 数据：`tb_ddr1_ihp130_loop` 的 16-word `pattern(i)`，每 lane 64 bit；DQ0。
- UI = 5 ns（DDR1 CK=10 ns 的半周期），64 UI 折叠。

结果：

| case | VDD / VDDIO / temp | VOH_min | VOL_max | central eye height |
|---|---|---|---|---|
| TT | 1.20 V / 2.50 V / 27 °C | 1.805 V | 0.666 V | **1,138 mV** |
| SS | 1.08 V / 2.30 V / 125 °C | 1.451 V | 0.920 V | **530 mV** |

产物：

- `results/ihp130/ddr1_eye_tt.png`
- `results/ihp130/ddr1_eye_ss.png`
- `results/ihp130/ddr1_eye_tt_ss.png`（并排对比）
- `results/ihp130/ddr1_eye_tt.csv` / `ddr1_eye_ss.csv`（原始波形）
- `results/ihp130/ddr1_eye_tt.spice` / `ddr1_eye_ss.spice`（可复跑 deck）

边界：

- 这是 **write eye**，只测 DQ 从 PHY 经 pad、封装到 50 Ω 负载的电压开口；不是读眼，也没有 DQS 抖动、SSO、串扰或 PCB。
- 眼图只有一条 lane、一个 package pin 的最差 RLC，不是 8 lane 同时翻转。
- 没有 jitter 叠加，TT/SS 曲线基本是单条轨迹；不能当 JEDEC 眼模板余量。

## 5. 复跑

```sh
cd /grid/ddr-phy

PYTHON=/tmp/litedram-venv/bin/python sh flow/prep_ddr1_top.sh
PATH=/nix/var/nix/profiles/default/bin:$PATH TOP=ddr1_top sh flow/run.sh ihp130

python3 generator/compose_ddr1_layout.py
python3 generator/render_gds.py --gds results/ihp130/ddr1_qfn48_assembly.gds \
  --png results/ihp130/ddr1_qfn48_assembly.png --width 2200 --height 2200 --tech sg13g2

/tmp/pkgvenv/bin/python generator/eye_ddr1_ihp130.py --case tt \
  --output results/ihp130/ddr1_eye_tt.csv --deck results/ihp130/ddr1_eye_tt.spice
/tmp/pkgvenv/bin/python generator/eye_ddr1_ihp130.py --case ss_low \
  --output results/ihp130/ddr1_eye_ss.csv --deck results/ihp130/ddr1_eye_ss.spice

python3 sim/plot_ddr1_eye.py --csv results/ihp130/ddr1_eye_tt.csv \
  --png results/ihp130/ddr1_eye_tt.png --vref 1.25 --ui-count 64 \
  --folded results/ihp130/ddr1_eye_tt_folded.csv
python3 sim/plot_ddr1_eye.py --csv results/ihp130/ddr1_eye_ss.csv \
  --png results/ihp130/ddr1_eye_ss.png --vref 1.15 --ui-count 64 \
  --folded results/ihp130/ddr1_eye_ss_folded.csv
```

`generator/eye_ddr1_ihp130.py` 依赖 IHP PDK 的 ngspice 模型和 OSDI；当前环境用 `/tmp/pkgvenv/bin/python`（PyYAML + pya）和 Ciel 的 SG13G2 安装。

状态：`signoff=false`。版图是装配/预览 GDS，眼图是 pad+package witness，不是 DDR1 签核。
