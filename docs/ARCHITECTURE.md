# LiteDRAM 外部 DRAM PHY：四开源 PDK 整体设计

状态：架构决策，含手工 I/O 的电路分工。不是尺寸，不是驱动电流，也不是签核。数字只来自下文引用的文件或仓库；标成“常规”的条目是教科书级的源同步约定，不是某份 JEDEC 表格的摘录。JEDEC 正文不在本仓库，不抄。晶体管宽、串联电阻、抽头延迟都还没有选，下文不编这些数。

## 1. 结论

控制器用 LiteDRAM，不改它的调度、刷新和交叉。我们做 ASIC PHY，并且自己画 I/O。现成 GPIO 只当结构参考，不当本设计的 pad。四套工艺共用同一套数字 PHY 和同一套 pad 拓扑，换的是器件名和电源，不是四套架构。

| 类 | 存储器 | 接口 | 工艺 | 电源 |
|---|---|---|---|---|
| S | SDR SDRAM | 与 `GENSDRPHY` 相同的 DFI，1:1 | sky130、gf180mcu、IHP SG13G2（130 nm）、ICsprout 55，全部自研 CMOS pad | VDDIO = 3.3 V |
| D | DDR SDRAM（DDR1） | 新的 1:2 DFI。LiteDRAM 有 DDR 模块类和仿真模型，没有能搬上 ASIC 的 PHY | sky130、IHP、ICsprout 55 | VDDIO = 2.5 V。不要用 3.3 V CMOS 去推 |
| D 远期 | 同上 | 同上 | gf180mcu | 远期计划，本期不做 DDR1 |
| D2 | DDR2 | LiteDRAM DDR2 DFI，1:2，带 ODT | 以后再看，仍然只有 55 nm 值得做 | 要另一套 1.8 V SSTL IO，不在本期 |

第一版硅目标仍然是一颗点对点 x8。SDR 的 CK = 100 MHz，控制器同频。DDR1 的第一个电气目标也是 CK = 100 MHz（两沿都工作时接口是 200 MT/s），控制器为 CK/2。这不是颗粒的速度档，只是现有 I/O 证据能支撑的起点：IHP 库单元的输入仿真只回答过“100 MHz 值得验，该 corner 下 200 MHz 没看到问题”，而且那是现成 pad，不是我们还没画尺寸的单元。DDR2 仍然排在自研 SSTL_18 之后，第一个数字目标仍是 DDR2-400，只在 55 nm。

不要用 3.3 V 的驱动去接 2.5 V 的 DDR 颗粒。两种存储器不共用一条 VDDIO。

## 2. 依据

控制器契约来自 LiteDRAM 源码和手册，不是来自完整的 DFI 规范：

- PHY 合同：<https://github.com/enjoy-digital/litedram/blob/master/doc/manual/08_phys.md>
- 核架构：<https://github.com/enjoy-digital/litedram/blob/master/doc/manual/04_architecture.md>
- 仿真模型怎么按存储器类型取 phase：<https://github.com/enjoy-digital/litedram/blob/master/doc/manual/15_simulation.md>
- 生成器接受的 `memtype`：<https://github.com/enjoy-digital/litedram/blob/master/doc/gen.md>
- DFI 记录：`litedram/phy/dfi.py` 的 `phase_description`
- SDR 参考实现：`litedram/phy/gensdrphy.py` 的 `GENSDRPHY`
- DDR1 只有的实现：`litedram/phy/s6ddrphy.py` 的 `S6HalfRateDDRPHY`。它用 Spartan-6 的 OSERDES2 / ISERDES2，手册写明没有硬件结果，也没有运行时校准
- DDR2 参考实现：`litedram/phy/s7ddrphy.py` 的 `S7DDRPHY`（它对 DDR2 关掉了 write leveling 和 write-latency calibration）
- 软件命令注入：`litedram/dfii.py`

手册里和 DDR1 直接相关的三句话：

- 仿真模型对 DDR 和 LPDDR 使用 2 个 DFI phase，设置从 `s6ddrphy.py` 抄。
- `S6HalfRateDDRPHY` 的比率是 1:2、每个控制器周期 4 拍，存储器类型包括 DDR。这是 FPGA 原语，不能例化到这四套工艺上。
- `litedram_gen` 文档列出的 `memtype` 是 SDR、DDR2、DDR3、DDR4。DDR1 不是生成器的一条现成路径。模块层有 DDR 类（`modules.py` 里的 DDR 颗粒，`memtype="DDR"`，例如 `MT46V32M16`）。控制器用 Python 核加我们自己的 PHY，不要在生成器里选一个不存在的 DDR PHY。

工艺事实来自本机库：

- ICsprout 55 现成 IO：`/grid/icsprout55-pdk/libs.ref/ICsprout_55LLULP1233_IO_251013`。Liberty 角落是核心 1.08/1.2/1.32 V、IO 2.97/3.3/3.63 V。单元是 `P65_1233_*`：GPIO `PBMUX`（PU/PD、四档驱动、开漏）、模拟 `PAR`/`PAR_5`、电源切割。没有 SSTL、差分、VREF 接收器或 ODT 单元。
- ICsprout 55 器件：`libs.tech/spice/README.md` 和 `foundry/ngspice/mos/`。`nm2p5_lp` / `pm2p5_lp` 是 2.5 V IO MOS。`nmod3p3_lp` / `pmod3p3_lp` 的模型头写的是“2.5 V，过驱 3.3 V”。版图和 LVS 把同一类器件叫 `nm3p3_lp` / `pm3p3_lp`（`libs.tech/lvs/README.md`，`libs.tech/xschem/symbols/ics55_mos_3p3.sym`）。符号注释里的绘制沟道长是 0.4–0.65 µm，典型 0.5 µm；这是符号约束，不是我们的宽度。二极管：SPICE 读明只有 1.2 V 和 2.5 V 二极管（`dio_2p5_np_pw_lp`、`dio_2p5_pp_nw_lp`）；LVS 另有 `dio_3p3_pp_nw_lp`，但 foundry SPICE 清单里没有 3.3 V 二极管卡。
- ICsprout 55 SPICE 许可：`libs.tech/spice/README.md` 写明 `foundry/` 是厂商数据，不在本仓库的 Apache-2.0 之内，只供教学和研究评估。用它做 pad 仿真不等于签核，也不能当成可再发布的 PDK 附件。
- ICsprout 55 PLL：`libs.ref/ics55_ecos_pll/README.md`。VCO 500–1200 MHz，输出分频 1/2/4/8，典型周期抖动 30 ps，宏已随 SoC 流片并在板级跑通。两路输出没有文档说明正交。Liberty 没有时序弧。许可证仍未定。
- ICsprout 55 DDR PHY：`libs.ref/55nm-ddr3-ddr2-phy/`。目标是 DFI、DDR2-667–1066 和 DDR3-800–1600。本地没有宏、时序模型、RTL 和许可证，`silicon_validated` 为假。不能例化。
- IHP SG13G2 现成 IO：`~/.ciel/ihp-sg13g2/libs.ref/sg13g2_io`。核心 1.2 V，IO 3.3 V；输入、输出、三态、双向，4/16/30 mA；另有模拟 pad。`doc/InputPerformance.html` 写明仿真用来确认 100 MHz 输入可行，并认为该 corner 下 200 MHz 不是问题，但阈值不在 VDDIO/2，占空比随沿率变化。没有 SSTL/LVDS/ODT。这些电流和频率是库单元的，不搬到自研 pad 上。
- IHP 厚氧管：`libs.tech/ngspice/models/sg13g2_moshv_parm.lib`。器件是 `sg13_hv_nmos` / `sg13_hv_pmos`（PSP 子电路 `sg13_hv_nmos` / `sg13_hv_pmos`）。模型头写“Maximum drain-source voltage: 3.3”。有效范围：NMOS L = 0.45–10 µm，PMOS L = 0.40–10 µm，W = 0.30–10 µm。没有另一个 2.5 V 器件。现成 pad 的 SPICE（`sg13g2_io.spice`）用多指 `sg13_hv_nmos`，单指 W = 4.4 µm、L = 0.6 µm。这只说明库单元用的就是这个管子，不是我们的指条数目标。
- IHP ESD：`sg13g2_esd.lib` 有 `diodevdd_2kv` / `diodevdd_4kv` / `diodevss_2kv` / `diodevss_4kv`。模型卡上 `diodevdd_mod` 的 `bv=11.81`，`diodevss_mod` 的 `bv=11.28`。这是 SPICE 击穿参数，不是 HBM 等级。
- gf180mcu 现成 IO 数据手册：<https://gf180mcu-pdk.readthedocs.io/en/latest/IPs/IO/gf180mcu_fd_io/datasheet.html>。工作电压 4.5–5.5 V，标称 5 V。`gf180mcu_ocd_io` 仍是 5 V pad、3.3 V 核心，解决不了颗粒电压。因不能用来接 3.3 V SDRAM。
- gf180mcu 器件：`sm141064.ngspice`，工艺头是 0.18 µm 3.3 V/6 V。`nfet_03v3` / `pfet_03v3` 是 3.3 V MOS，`nfet_06v0` / `pfet_06v0` 是 6 V MOS。3.3 V 二极管是 `diode_nd2ps_03v3`（N+/Psub）和 `diode_pd2nw_03v3`（P+/Nwell）；另有 6 V 对应项。SDR 用 3.3 V 器件，不用 6 V 管，也不用 5 V GPIO。
- sky130：核心 1.8 V。厚氧管是 `sky130_fd_pr__nfet_g5v0d10v5` / `pfet_g5v0d10v5`，另有 `esd_nfet_g5v0d10v5` / `esd_pfet_g5v0d10v5`。二极管类名带 `diode_pd2nw_11v0`、`diode_pw2nd_11v0` 及其 ESD 变体。名字里的 5 V / 11 V 是器件类，不是本设计的工作电压。3.3 V 和 2.5 V 都落在 5 V 栅的额定之内，但库里没有单独的 2.5 V IO 模型，也没有 SSTL 单元。现成 GPIO 是 `sky130_ef_io` GPIOv2。
- 本地时钟：`/grid/adpll_gen/flow/PDK_ESTIMATES.md`。这是数字控制域的估算，不是 DCO 相位噪声签核；没有 DCO 表时生成器返回 `FAIL_UNCHARACTERIZED`。
- 本地 SerDes：`/grid/OpenSERDES`。位串行链路（comma、过采样 CDR）。文档写明 DDR/两相采样还没有物理时钟，生成器对此 fail-closed。

存储器侧电气只用公开二次资料做边界，不抄 JEDEC：

- DDR 器件目录把 I/O 标成 2.5 V：<https://www.micron.com/products/memory/dram-components/ddr-sdram>
- DDR2 编号把接口标成 1.8 V SSTL_18：Micron 旧料号指南（“A = 1.8V, SSTL_18”）
- DDR2 单端 DQS、ODT 功耗、低于数据手册频率：<https://www.micron.com/sales-support/sales/faqs> 的 DDR2 条目
- 源同步对齐的工程写法以 Xilinx 7 系 PHY 为代表：写侧用与 DQ 相差约 90° 的 DQS 时钟，读侧用可扫描延迟加 bitslip（`s7ddrphy.py`）。本设计只借这个相位关系，不借它的抽头数。

## 3. LiteDRAM 要求 PHY 交出什么

每个 PHY 交三样东西：DFI、`PhySettings`、可选的校准 CSR。控制器只读设置来排命令；校准标志只被 BIOS 使用。标志为假时，对应步骤不会跑。

一个 phase 的信号（`dfi.py`）：

```text
命令  address, bank, ras_n, cas_n, we_n, cs_n, cke, odt, reset_n, act_n
写    wrdata, wrdata_en, wrdata_mask
读    rddata_en, rddata, rddata_valid
```

| 项 | `GENSDRPHY` | 本设计的 DDR1 | DDR2 的 `S7DDRPHY`（以后） |
|---|---|---|---|
| `memtype` | SDR | DDR | DDR2 |
| `nphases` | 1（半速版本为 2） | 2 | 2 或 4 |
| `dfi_databits` | 等于 DQ | 2 × DQ（一个 DRAM 时钟的两沿） | 同左 |
| 控制器字 | 1 × DQ | 4 × DQ | `dfi_databits × nphases` |
| 时钟 | `sys` = CK | CK = 2 × `sys` | CK = `nphases × sys` |
| 读延迟 | `read_latency = CL + 1` 个 sys 周期 | 等 RTL 流水线定下来再填，不从 S6/S7 抄 | 由 CL、比率和 SERDES 流水线推出 |
| 写延迟 | 0 | 同上。DDR1 没有 DDR2 那样的 CWL | 由 CWL 推出 |
| 校准 | 全假 | 第一版全假：静态约 90°，不做运行时扫描 | 读电平：有。DDR2 的写电平和写延迟校准：关 |
| 不接的脚 | `odt`、`reset_n`、`dqs` | `odt`、`reset_n`。DDR1 没有这两个脚 | `reset_n` 不接 DDR2 颗粒 |

`DFIInjector` 让 BIOS 在每个 phase 上打命令并读回数据。SDR 初始化沿用这条路径。DDR1 也用这条路径，不仿造 Spartan-6 或 Artix-7 的 CSR 地址。S6 PHY 的对齐是编译期常数，而且绑在 FPGA 原语上；我们不把那些常数当成 ASIC 的时序。

## 4. 三类 PHY

### 4.1 Class S：CMOS SDR，四套工艺

这是 `GENSDRPHY` 的可综合翻译。pad 是第 5 节的自研单元，不是库里的 GPIO 例化。数字部分没有模拟时序电路。

```text
sys/CK
  |
  +--> 命令寄存器 --> CMOS pad --> A, BA, RAS#, CAS#, WE#, CS#, CKE
  |
  +--> DQ 输出寄存器 -- OE=wrdata_en --> 双向 pad --> DQ
  |
  +--> DQ 输入寄存器 <-- 同一 pad
  |
  +--> DQM 寄存器（与 wrdata_en 相与）
  |
  +--> 同一沿发出的 CK pad（不要用另一个未配平的时钟树）

rddata_en 经过 CL+1 级寄存器后成为 rddata_valid
```

行为约定，与 `GENSDRPHY.__init__` 一致：

- `memtype=SDR`，`nphases=1`，`dfi_databits=databits`
- `rdphase=wrphase=0`，`write_latency=0`，`read_latency=CL+1`
- 不连 `odt`、`reset_n`、`dqs`。有 DM 则 `with_dm=True`
- 所有校准标志为假，`delays=0`，`bitslips=0`

目标时序：CK 100 MHz，CL 2 或 3，由颗粒数据手册在该 tCK 下的允许值决定。命令、DQ 和 CK 使用同一个时钟沿，使片外 tCO 主要变成 pad 延迟差。这个差要进 SDC，不能靠仿真“看着差不多”。

半速可选项（Class S2）只在核心在 100 MHz 合不上时启用：控制器跑在 CK/2，两个 DFI phase，对应 `HalfRateGENSDRPHY`。默认不做。gf180 的 5 V 标准单元 post-route 大约只有 40–50 MHz（`PDK_ESTIMATES.md`），所以 gf180 的控制器必须映到 3.3 V 标准单元。那一档的数字侧证据是 ADPLL 的 post-route 约 196 MHz SS、规划上限 150 MHz，不是本 PHY 的时序。100 MHz 仍是目标；合不上就降到 S2，而不是改用 5 V 单元。

引脚，一颗 x8：CK、CKE、CS#、RAS#、CAS#、WE#、A[12:0]、BA[1:0]、DQ[7:0]、DQM。大密度颗粒再加地址位。约 30 个信号加电源。第一版仍用 x8。

### 4.2 Class D：DDR1，sky130 / IHP / ics55

数字部分是新写的 1:2 PHY，不是 `S6HalfRateDDRPHY` 的翻译。那个 PHY 的串行器、输入延迟和时钟都是 Spartan-6 硬核。本 PHY 只保留它对控制器的几何：两个 phase，每个 phase 两拍，一个控制器周期携带四个 DQ 宽度的字。

点对点、一颗 x8、短走线。不做 DIMM，不做 fly-by，不做写电平。DDR1 没有 ODT，也没有 DDR3 的 RESET#。

```text
        控制器 sys = CK/2
              |  两个 DFI phase，每个 phase 2×DQ
              v
        +--------------+
        | 命令 2:1     |--> 单沿命令，与 CK 同沿
        | DQ   4:1     |--> 两沿，时钟 = CK
        | DQS  4:1     |--> 两沿，时钟 = ck90，写窗口外三态
        | 读捕获       |<-- 被门控的 DQS 采 DQ，再跨回 sys
        +--------------+
              |
     2.5 V 推挽驱动 / 差分 CK,CK# / 单端 DQS / DM
     接收端比较的是板上 VREF，不是一个 CMOS 反相器
              |
           一颗 DDR
```

`ck90` 是时钟块对本 PHY 的义务：与 CK 同频，相位差约为四分之一周期，用来把写 DQS 的沿放到 DQ 有效窗中间。它不是 ADPLL 的第二输出，也不是 ECOS PLL 的第二输出。这两个块都没有文档化的正交（见第 7 节）。第一版允许用一条静态延迟，延迟量在仿真里对着这一颗、这一块板调，不写成可编程抽头数。抽头存在之前，`delays=0`。

常规对齐，仍是静态相位，不是每比特训练：

- 写：DQ 用 CK 发出，DQS 用 `ck90` 发出，只在写窗口内打开驱动。短点对点下不做写训练扫描。
- 读：颗粒把 DQ 与 DQS 边沿对齐地送出。PHY 用被门控的 DQS 采 DQ。把采样点移进眼图的那一级小延迟也是全局一条，不是每比特一条；级数和步进未定。
- DQS 门控：用延迟后的 `rddata_en` 打开一个窗口，盖住有效沿，挡住空闲时 DQS 上的毛刺。窗口宽度等读路径的周期数定下来再写，不先假设成一个 CK。
- DM 跟着写数据。`wrdata_mask` 映到 DM，不映到 ODT。
- CK 与 CK# 是一对互补的单端驱动，版图配平。不是 LVDS 单元，四套库也没有 LVDS 单元。
- 读数据从 DQS 域回到 `sys` 要有明确的跨时钟。可以借 OpenSERDES 的复位同步器写法，不借它的采样器。

第一版 `PhySettings` 只固定几何，不填还没有的延迟：

```text
memtype                   DDR
nphases                   2
dfi_databits              2 * DQ
cl                        由所选颗粒在该 tCK 下的允许值决定
read_latency              未定，等于本 PHY 的流水线，不抄 S7
write_latency             未定，同上。不使用 DDR2 的 CL-1
write_leveling            False
write_dq_dqs_training     False
write_latency_calibration False
read_leveling             False
delays                    0
bitslips                  0
with_dm                   True
```

引脚，一颗 x8：CK、CK#、CKE、CS#、RAS#、CAS#、WE#、A、BA、DQ[7:0]、DQS、DM，加一个只进不出的 VREF。没有 ODT，没有 RESET#。VTT 在板上，不进芯片。

LPDDR1 仍然不做。它是 1.8 V，不与这三套 2.5 V DDR1 共用 pad，也没有差分 DQS 的现成路径。

### 4.3 Class D2：DDR2，以后再看

数字部分可以先在任何工艺上仿真；能接真实颗粒的只有将来有 SSTL_18 IO 的那一套。ICsprout 55 的核心是 1.2 V，现成 IO 是 3.3 V，本期的 2.5 V 器件也不是 1.8 V SSTL。SSTL_18 切片仍是新 IP，不在本期。

点对点、一颗 x8、短走线。不做 DIMM，不做 fly-by，因此也不做 DDR3 那种写电平。这与 LiteDRAM 对 DDR2 关掉 write leveling 的做法一致。写侧仍是静态约 90° 的 DQS，读侧仍是 DQS 门控加一条尚未定步进的延迟。ODT 直接跟 DFI 的 `odt`，只在写 burst 打开。`reset_n` 不接到 DDR2 颗粒。目录里的 55 nm DDR PHY 不能用。

速率阶梯不变：仿真不限；硅上第一步 DDR2-400（CK 200 MHz，控制器 100 MHz）；DDR2-533/667 要有签核后的抖动、版图后 IO 和板级 SI；DDR2-800 和该目录里的 DDR3-1600 不做。

## 5. 手工 I/O

四套工艺用同一张原理图。每个工艺换器件、阱极性和两套电源的接法。不在这一节选宽度、指条数、驱动电流或串联电阻。

```text
核心域 VDD                         IO 域 VDDIO / VSSIO
OUT, OE_N                            不与核心共用
   |                                 
   +-- 电平搬移（仅当 VDD ≠ VDDIO）
   |       IO 侧器件必须能承受 VDDIO
   v
 厚氧预驱动（逐级加宽，级数未定）
   |
 三态驱动：PMOS 到 VDDIO，NMOS 到 VSSIO
   |   OE 无效时两管都关。上电期间保持关断，直到两套电源都在
   v
 串联电阻（可以先只放在板上；片上要留器件，阻值未定）
   |
  PAD ---- 主二极管到 VDDIO
   |        主二极管到 VSSIO
   |        VDDIO 到 VSSIO 的电源钳位
   |
 接收
   SDR：厚氧 CMOS 反相器或施密特。不要假设阈值在 VDDIO/2
   DDR1：PAD 与板上 VREF 的差分对，再变成单端
   |
 电平搬移回核心 --> IN
```

保护环围着输出级和 ESD，按该 PDK 的 latch-up 规则接电源。环的宽度和间距不在本文定。核心薄氧管不许直接接到 PAD：即使核心名义电压和 VDDIO 相同，驱动仍然是带 ESD 的 IO 管，不是一个标准单元反相器。

两套电源：

| 用途 | 电压 | 哪些工艺 | 注意 |
|---|---|---|---|
| SDR 的 VDDIO | 3.3 V | 四套都做 | 命令和 DQ 可以共用。每个字节旁边放 VDDIO 和 VSSIO |
| DDR1 的 VDDIO | 2.5 V | sky130、IHP、ics55 | 与 3.3 V 轨分开。gf180 本期不做 |
| VREF | 板上分压，标称为 VDDIO/2 | DDR1 的三套 | 只进芯片。走模拟路径：ESD 二极管加金属，没有输出管。不用 DAC 产生，不用 ADC 采样 |
| 终端 | 板上 | SDR 串联；DDR1 按 SSTL 做到 VTT | 阻值由板级 SI 定，不写进 PHY |

现成 GPIO 只用来对照结构。IHP 的 `sg13g2_io.spice` 说明库里已经用 `sg13_hv_*` 加 `diodevdd` / `diodevss` 搭过一次；我们重画，因为那些单元没有 VREF 接收器，而且用户要求四套工艺都手工完成，不能只在有 GPIO 的工艺上例化库单元、在 gf180 上放弃。

### 5.1 各工艺用哪些器件

| | 核心 | SDR 3.3 V 驱动 / 接收 | DDR1 2.5 V 驱动 / 接收 | ESD | 电平搬移 |
|---|---|---|---|---|---|
| sky130 | 1.8 V | `nfet_g5v0d10v5` / `pfet_g5v0d10v5` | 同一对管，VDDIO 改为 2.5 V。没有单独的 2.5 V 模型 | `diode_pd2nw_11v0`、`diode_pw2nd_11v0` 及其 ESD 变体；次级可以用 `esd_nfet_g5v0d10v5` / `esd_pfet_g5v0d10v5` | 要。IO 侧用 5 V 栅器件 |
| gf180mcu | 3.3 V 标准单元 | `nfet_03v3` / `pfet_03v3` | 不做 | `diode_nd2ps_03v3`、`diode_pd2nw_03v3` | 名义电压相同，不做搬移。预驱动仍要。禁止用 5 V GPIO 和 6 V 管 |
| IHP SG13G2 | 1.2 V | `sg13_hv_nmos` / `sg13_hv_pmos` | 同一对管，VDDIO = 2.5 V。见下文限制 | `diodevdd_*` / `diodevss_*` | 要。IO 侧用 HV 管 |
| ICsprout 55 | 1.2 V | 布局名 `nm3p3_lp` / `pm3p3_lp`，SPICE 名 `nmod3p3_lp` / `pmod3p3_lp` | `nm2p5_lp` / `pm2p5_lp` | DDR1 用 `dio_2p5_np_pw_lp` / `dio_2p5_pp_nw_lp`。SDR 的 3.3 V 二极管见下文缺口 | 要。IO 侧用上面的厚氧管 |

IHP 上的 DDR1 必须单独看：HV 模型的最大 Vds 是 3.3 V，没有 2.5 V 器件。2.5 V 的 VDDIO 落在这个 3.3 V 额定里面，但不是一个被表征过的 2.5 V IO。能不能用，要等这对管在 2.5 V 下做完驱动和接收仿真再说；在此之前不能写成“IHP 支持 SSTL_2”。

ics55 上的 SDR 也要单独看：叫 3.3 V 的那对 MOS，模型头写的是 2.5 V 过驱到 3.3 V，不是另一张 3.3 V 标称卡。现成 `P65_1233` GPIO 说明厂商做过 3.3 V pad，但那个单元的内部不是我们的网表，数据手册里的驱动电流还没抽成文本。自研 3.3 V pad 必须用 `nmod3p3_lp` / `pmod3p3_lp` 在 3.3 V 下仿真之后才能谈额定。LVS 识别 `dio_3p3_pp_nw_lp`，foundry SPICE 清单没有 3.3 V 二极管卡；在找到卡之前，不要把 `dio_2p5_*` 悄悄当成 3.3 V ESD。DDR1 则对得上：`nm2p5_lp` / `pm2p5_lp` 加 `dio_2p5_*`。

sky130 的 5 V 栅器件可以工作在 3.3 V 或 2.5 V，这只说明电压没有超出栅氧化物的类别，不说明存在一个 2.5 V SSTL 的交流参数。驱动能力仍然要仿真。

接收器不要共用：

- SDR 是满幅 CMOS。反相器的阈值要在该工艺的厚氧管上仿真。IHP 现成输入的阈值就不在 VDDIO/2，所以不能把“反相器阈值 = VDDIO/2”写进时序约束。
- DDR1 是 PAD 对 VREF。输入对和尾电流管都要用上表的 IO 器件，因为两个输入都在 VDDIO 域里。共模范围、失调和滞后都还没有数，不在本文给。
- VREF pad 不例化数字三态单元。

## 6. 工艺怎么落

|  | SDR，3.3 V CMOS，CK 100 MHz | DDR1，2.5 V，CK 100 MHz | DDR2，1.8 V SSTL |
|---|---|---|---|
| sky130 | 做。自研 pad，5 V 栅器件，核心 1.8 V，要搬移 | 做。同一对管，VDDIO 改为 2.5 V。不是被表征过的 2.5 V IO 库 | 以后。不要把 1.8 V GPIO 当成 SSTL |
| gf180mcu | 做。自研 pad，`nfet_03v3` / `pfet_03v3`，数字用 3.3 V 标准单元。现成 5 V GPIO 不用 | 远期 | 不做 |
| IHP SG13G2 | 做。HV 管的 Vds 额定就是 3.3 V。现成 GPIO 的 100 MHz 结论不能当成自研单元的 Fmax | 电路上做，但要标成未表征。没有 2.5 V 器件，2.5 V 只是落在 3.3 V 额定内 | 不做 |
| ICsprout 55 | 做。用过驱 3.3 V 的那对管，先仿真再谈额定。3.3 V 二极管卡还缺 | 做。这是四套里唯一器件名就是 2.5 V 的一档 | 以后。目录中的 DDR PHY 不能用 |

不再按现成单元的 4/16/30 mA 或 `PBMUX` 的 DS0/DS1 来选驱动。那些档位属于库单元。自研驱动的电流等负载仿真。

## 7. 本地 IP 与缺口

`/grid` 里已有的块，能进 PHY 的都很窄：

| 仓库 | 进 PHY 的部分 | 不进 PHY 的部分 |
|---|---|---|
| LiteDRAM（将作为 submodule） | 控制器、交叉、刷新、BIST、DFI 模型、SDR 初始化序列、DDR 模块类 | 任何 FPGA SERDES 原语。S6 PHY 不例化 |
| `/grid/adpll_gen` | 可选的片上 CK 源，仅限已有数字估算能盖住的频率 | 不当 90° 时钟，不当抖动参考。没有 DCO 表就是 `FAIL_UNCHARACTERIZED`。sky130 环振在已建网表里不起振 |
| `ics55_ecos_pll` | 55 nm 上将来 DDR2-400 的候选时钟：VCO 500–1200 MHz，再分频 | 不要假设 CKOUT1/CKOUT2 是 0°/90°。许可证仍未定。没有时序弧 |
| `/grid/OpenSERDES` | 复位同步器、跨时钟 FIFO 的写法、PRBS 图案 | 数据通路。它的 DDR 采样没有物理正交时钟，而且是位串行 CDR，不是 DQS 采样 |
| `/grid/OpenRAM`、`/grid/DFFRAM`、IHP SRAM、55 nm SRAM/ROM 编译器 | SoC 自己的存储器，与外部 DRAM 并列 | 不放进 PHY。训练图案用寄存器 |
| `/grid/saradc_auto`、`/grid/dac-generator` | 无 | 不参与 DQ、VREF 或眼图扫描 |

### 外部控制器，只作命令顺序参考

控制器仍然是 LiteDRAM。下面这些仓库不做 submodule，源码不抄进本仓库。看的是命令顺序：初始化、激活、读、写、预充电、刷新。不看它们的总线、FPGA 原语和时序常数。许可只写本次对到原文的；没对到的不写成已核实。

| 仓库 | 拿来看什么 | 不拿来做什么 |
|---|---|---|
| SDR：<https://github.com/stffrdhrn/sdram-controller> | README 写的是 100 MHz、CAS 3、单次读写带自动预充电。仓库自述许可是 BSD。 | 不替换 LiteDRAM |
| SDR：<https://github.com/ultraembedded/core_sdram_axi4> | AXI4 从接口，行打开后留着，直到刷新或换行。仓库根上的 `LICENSE` 是 GPL-3.0。 | GPL 代码不进本仓库 |
| SDR：<https://github.com/hdl-util/sdram-controller> | 通用 SDR 控制器。仓库带 `LICENSE-MIT` 和 `LICENSE-APACHE`。 | 不替换 LiteDRAM |
| SDR：<https://github.com/yigitbektasgursoy/SDRAM_Verilog> | 命令顺序的另一份写法。许可未核对。 | 不抄源码 |
| DDR1 备选：<https://github.com/wangxuan95/fpga-ddr-sdram> | README：CL 固定为 2；`drv_clk` 是用户时钟的 4 倍，再四分频得到 CK 和 AXI 时钟；IO 按 SSTL-2，与 2.5 V LVTTL/LVCMOS 兼容；接口频率下限 75 MHz。GitHub 许可栏是 GPL-3.0。 | 不是本设计的 PHY，也不例化。README 指向 Micron 的仿真模型，本仓库不保存那份模型 |
| DDR2：<https://github.com/adibis/DDR2_Controller> | 命令顺序参考。许可未核对。 | 不抄。DDR2 仍在以后 |
| DDR2：<https://github.com/freecores/ddr2_sdram> | 命令顺序参考。公开索引里没有读到许可原文。 | 不引进。抄任何文件之前先读仓库自己的声明 |
| DDR2：<https://github.com/avichalkaria/DDR2_Controller_Design> | 命令顺序参考。许可未核对。 | 不抄。DDR2 仍在以后 |

缺口，就是上面这些仓库和四套 PDK 都交不出来的东西：

1. 没有 SSTL 驱动，也没有 VREF 接收器。四套现成 IO 都是 CMOS GPIO（加模拟 pad）。DDR1 的接收器要新画。
2. 没有正交时钟。ADPLL 没有第二相位；ECOS PLL 的两路输出没有相位说明；OpenSERDES 的两相采样在没有物理正交时钟时直接 fail-closed。DDR1 的 `ck90` 是空的。
3. 没有可复用的 DDR1 PHY。唯一驱动 DDR 引脚的是 `S6HalfRateDDRPHY`，绑定 Spartan-6，没有记录在案的硬件结果，也不在 `litedram_gen` 的 PHY 列表里。
4. 没有 3.3 V 的 gf180 输出 pad。现成 IO 是 4.5–5.5 V。3.3 V MOS 和 3.3 V 二极管在器件库里，不在 pad 库里。SDR 靠自研单元，不靠等一个新 GPIO。
5. ics55 的 `55nm-ddr3-ddr2-phy` 没有宏、时序模型、RTL 和许可证，硅验证为假。它也不覆盖 DDR1。
6. ADPLL 没有相位噪声表征。数字 Fmax 不是 DRAM 时钟指标。各工艺数字侧上限仍是 `PDK_ESTIMATES.md` 里那些：ics55 H7CR post-route OUT 836 MHz TT / 479 MHz SS；IHP 525 MHz TT、SS 低于 400 MHz；sky130 HD 只有约 0.57 GHz 的 pre-layout；gf180 AS 3.3 V post-route 约 196 MHz SS，规划上限 150 MHz；gf180 FD 5 V 约 50 MHz TT / 41 MHz SS，50 MHz 未闭合。
7. OpenSERDES 不是 DQS 采样器。读数据的选通是 DQS，不是过采样 CDR。
8. SAR ADC 和 DAC 不是 pad、VREF 或眼图仪。
9. OpenRAM 和 DFFRAM 是片上 SRAM，不是外部 DRAM 的 PHY。
10. ics55 foundry SPICE 不是 Apache-2.0，只能用于评估。用这套模型选出的宽度不能写成可流片的签核。
11. 还没有的数：驱动管宽度、指条数、串联电阻、ESD 面积、保护环间距、`ck90` 的延迟、读采样延迟的级数和步进。本文故意不填。

时钟怎么选，按已有数字域估算而不是按宣传中的 VCO 上限。SDR 的默认时钟是片外输入的 100 MHz，走与命令寄存器同一个时钟网络。ADPLL 和 ECOS PLL 是可替换的片上源，不是第一版的依赖。DDR1 的 90° 也不从这两个 PLL 的第二输出上取。sky130 在有布线后证据之前，不要用这个 ADPLL 当片上 DRAM 时钟。gf180 的 5 V 单元跑不了本设计的基线。

## 8. 怎么接进芯片

```text
用户逻辑  Wishbone 或 AXI
    |
LiteDRAM 交叉 / 控制器 / DFI 注入器     全部在 sys
    |
Class S 或 Class D 数字 PHY                本仓库
    |
自研 pad（每个 PDK 一套器件，同一张原理图）
    |
一颗外部 SDR 或 DDR
```

仓库划分。仓库根下的 `PLAN` 被忽略，设计记录在本文件：

```text
third_party/litedram     submodule，不改。控制器仍是它
rtl/sdr_phy.sv           Class S，1:1，已综合
rtl/sdr_ctrl.sv          闭环用的 1:1 控制器。不是 LiteDRAM 网表
sim/sdram_model.sv       引脚级 SDR 行为模型。不是时序检查器
sim/sdram_checker.sv     命令间隔检查器。数时钟，不存数据，也不驱动 DQ
sim/gate.sh              sky130 HD 功能门级。无 SDF，不是时序，也不是 pad
sim/sdr_phy_gate.v       门级网表的参数壳。只接受 x8、CL 2、一个 rank
tb/tb_sdr_phy.sv         DFI 到 pad 端口
tb/tb_sdram_model.sv     PHY 加上面那个模型
tb/tb_sdram_checker.sv   间隔检查器。每条规则一个实例
tb/tb_sdr_loop.sv        控制器、PHY、模型闭环
rtl/ddr1_phy.sv          Class D，还没写
rtl/ddr2_phy.sv          Class D2，更晚
sch/pads/                生成器产出的拓扑模板；gf180mcuD / sky130 / IHP 已绑定并生成，ics55 缺 3.3 V ESD 二极管卡；通用拓扑尺寸仍空着（第一版 sizing fixture 在 specs/pads/sizing/）；layout/profiles/ 存封装 profile 的闭合产物
flow/                    LibreLane；sky130 控制组已 80/80 跑通，草稿 SDC 故意未接入（见 docs/STA_PLAN.md §5）
docs/                    本文件
```

已经跑通的闭环是 `rtl/sdr_ctrl.sv`，不是 `litedram_gen` 出来的网表，也没有例化 LiteDRAM。它抄的是 `GENSDRPHY` 的 DFI 时序（写延迟 0，读延迟 CL+1，`rddata_en` 和 READ 同一拍）和 `get_sdr_phy_init_sequence` 在 nphases=1 下的命令顺序（BL=1，MR = CL<<4）。CKE 后的空拍是 8，MRS 后的空拍是 4，不是 20000 和 200。初始化之后默认不刷新（`T_REFI = 0`，保持闭环测试可复现）；设置 `T_REFI > 0` 后按 tREFI 发 AUTO REFRESH，刷新前先预充所有 bank。LiteDRAM 本身不改。以后若要完整控制器，仍用 `litedram_gen` 配 `GENSDRPHY` 的几何，再用 `sdr_phy` 换掉 FPGA IO；这一步还没做。DDR1 不走生成器的 PHY 选项：用 LiteDRAM 的 Python 核和 DDR 模块类，PHY 换成 `ddr1_phy`。不要为了 ASIC 去改 bank machine。

带 CPU 的芯片通过 Wishbone 访问 DFI 注入器完成初始化，然后打开硬件路径。没有 CPU 的测试芯片用 LiteDRAM 自带的 BIST。

SPD 不在 PHY 里。DIMM / SODIMM 上的 SPD 是模块 EEPROM。SDR、DDR、DDR2 的 SPD 走 I2C（SMBus，地址脚 SA0–SA2）。若板级把同样的几何放在 SPI 器件上，用 PHY 外面的 SPI 主设备读。两种都不是 `sdr_phy` 的状态机，也不是一种 pad。第一版硅是点对点，没有 DIMM，几何由板级给定，不在初始化时去读 SPD。

ECC 也不在 PHY 里。它是数据通路上的额外处理：要么 DQ 更宽，要么在控制器旁边做校验。不是一种 pad，也不进命令寄存器。第一版是无 ECC 的 x8。

## 9. 验证

按层说明证据，不把下一层的通过说成上一层，也不把现成 GPIO 的仿真说成自研 pad 的仿真：

1. DFI 行为。`tb/tb_sdr_phy.sv` 检查 `sdr_phy` 对 `GENSDRPHY` 的翻译：`read_latency = CL+1`，复位保持 NOP。已跑过 CL 2/3、x8/x16。这一步还没有接上 LiteDRAM 的 Python DFI 模型。DDR1 以后先只检查命令、两沿数据和 `rddata_valid` 的周期，不报告建立保持。
2. 引脚级 SDR 模型。`sim/sdram_model.sv` 接在 `sdr_phy` 的端口上，三态在测试台里用 `dq_oe` 接上。PHY 在沿 T 把命令打到端口；模型和 PHY 用同一个时钟，采样的是寄存器输出，所以在 T+1 才接受这条命令。读命令被接受之后，数据在 CL−1 个模型时钟之后驱动到 DQ，PHY 在发出读的那个 DFI 周期之后 CL+1 拍的 `dfi_rddata_valid` 上采到它。`tb/tb_sdram_model.sv` 跑过 CL 2 和 CL 3（x8、BL=1）：写入 `0xA5`，掩码写 `0xFF` 不改该字节，读回 `0xA5`；对已关闭的 bank 再读，`fault_code` 为 `RW_CLOSED`（3）。BL>1 的写被拒（`BAD_MRS`）。模型不测 tRCD、tRP、tRAS、tRFC。它只报四种命令顺序错误：`BAD_MRS`、`ACT_OPEN`、`RW_CLOSED`、`REF_OPEN`。这一步不证明 pad，也不证明 DDR。控制器闭环用的是 `rtl/sdr_ctrl.sv`，不是 LiteDRAM 网表。`tb/tb_sdr_loop.sv` 在 CL 2 和 CL 3 通过：行命中、换 bank、换行（先预充电再激活）、原行仍保持 `0xA5`，`fault` 保持 0。`sim/run.sh` 会跑这一项。它同样不测 tRCD、tRP、tRFC，只要求模型的 `fault` 不起。
3. 命令间隔。`sim/sdram_checker.sv` 只数时钟，不存数组，也不驱动 DQ，所以模型把数据存错也不会让一条过早的命令漏过。默认计数是 Micron 256Mb SDRAM Rev. W（05/15，`256Mb_sdr.pdf`）的 -75 列，Table 12 和 Table 13，按 tCK = 10 ns 取整（这一档 CL = 2 合法，tCK(2) 最小 10 ns，tCK(3) 最小 7.5 ns）：tRCD 2、tRP 2、tRAS 5、tRC 7、tRRD 2、tRFC 7、tWR 2、tMRD 2、tCCD 1。tWR 的原文是“1 CLK + 7.5 ns”（注 13，自动预充电）和 15 ns（注 14，预充电）；Table 13 的 tDPL 是 2 tCK，检查器用 2。tMRD 表上是 2 tCK，注 21 写 JEDEC 和 PC100 要求 3，默认仍是 2。参数为 0 的那一项不检查。IS42/45S16160J Rev. C4（09/17/2020）速度 -7 是另一张纳秒表：tRCD/tRP 15 ns，tRAS 最小 37 ns，刷新恢复是 trc = 60 ns，没有单独的 tRFC。两张表不混用。检查器不看 tAC、tOH、tHZ、tLZ、建立保持、DQM 延迟，pad、封装和 PCB。`tb/tb_sdram_checker.sv` 每条规则单独一个实例，早一拍要保留对应的故障码，满足间隔的那一拍不要求把已经粘住的故障清掉。这一步不是时序仿真，也不是电气签核。
4. 映到标准单元之后的功能仿真。`sim/gate.sh` 把 `sdr_phy` 映到 sky130 HD（`sky130_fd_sc_hd__tt_025C_1v80.lib`），再用单元的功能视图（`-DFUNCTIONAL`）跑 `tb/tb_sdr_phy.sv`。网表固定为 x8、CL 2、一个 rank；别的参数在 `sim/sdr_phy_gate.v` 里直接编译失败。`dfxtp` 的功能模型只有一级 `UNIT_DELAY`，输出就是触发器的 Q。`lpflow_isobufsrc` 用在 D 端做复位隔离，功能模型是组合的，不再加一级延迟。脚本把这个延迟定成 `#0.1`，测试台仍在沿后 `#1` 采样，两者不会落在同一时刻。没有 SDF，没有线延迟，没有 pad。这一步不是时序仿真，也不是签核。已跑出 `PASS CL=2 DATA_BITS=8` 和 `GATE_DONE`。带 SDF 的时序注解还没有做。`dfflibmap` 没有 `$_SDFF_PP0_` / `$_SDFF_PP1_` 的直接单元，`DFFLEGALIZE` 先把它们改成普通 `$_DFF_P_` 再映到 `dfxtp`。门级网表本身不证明同步置位的编码。
5. 单管 pad。每个工艺先仿真一个双向单元：空载、短走线的集总参数、三态、上电时输出为关。DDR1 再加一个 VREF 接收器，输入是 PAD 和 VREF。通过标准是所选颗粒数据手册上的电压和时间，不是波形“看起来像”。没有这一步之前，不报告 tDS/tDH/tAC/tOH。当前只有三套 PDK 的**预驱动+输出级/接收器切片**和 ESD 反向泄漏（`docs/PAD_GENERATOR.md` §4.1，`design_assumption`，无 ESD 应力/资格、无电平搬移/PVT），不是这一整步。
6. 含封装的一条命令、一条 DQ 和 CK。仍然对数据手册，不对库 GPIO 的旧仿真。
7. 硅。先跑 BIST，再跑带刷新的随机访问。失败时记录失败地址和刷新是否打开。

IHP 现成 IO 的 100 MHz 输入仿真、sky130 公开板对库 GPIO 的频率说法，都只证明那些库单元。不能用来签自研 pad。

## 10. 分期

1. P0。架构在本文件。Class S 数字核 `rtl/sdr_phy.sv`、引脚级模型、命令间隔检查器、`sdr_ctrl` 闭环，以及 sky130 HD 功能门级仿真已经有。行为仿真、间隔检查和这一层门级功能仿真通过。pad 原理图还没有可签核的尺寸；sch/pads/ 已有生成器产出的拓扑模板（见 docs/PAD_GENERATOR.md），gf180mcuD / sky130 / IHP 三套 device map 已绑定并生成拓扑，ics55 缺 3.3 V ESD 二极管 SPICE 卡。DDR1 RTL 还没开始；LibreLane 已在 P0-5 实跑（原始配置 80/80 完成，草稿 SDC 接上会在 PostCTS 失败，见 `docs/STA_PLAN.md` §5）。已有三套 `design_assumption` sizing fixture 和 ngspice 输出级/接收器切片（docs/PAD_GENERATOR.md §4.1）；下一步是把它们变成签核尺寸：补 ESD、预驱动、电平搬移、PVT、PEX/IBIS/SI-PI，并为 ics55 解决 3.3 V ESD（docs/ICS55_ESD_3V3.md）。
2. P1。`sdr_phy` 加四套 pad。x8、100 MHz。第 9 节第 1、2、3 步已经过，第 4 步的 sky130 HD 功能门级也已经过。没有 SDF。pad 和第 5 步还没有。gf180 用 3.3 V 标准单元，不用 5 V GPIO。LibreLane 的 `gf180-as-7t3v3` 要先在 `./pdks/gf180mcuD` 组好 3.3 V 视图；5 V 标准单元不是一条规格。这一步之前不开 DDR1 RTL。
3. P2。`ddr1_phy` 加行为级 DDR 模型。那是另一个模型，不是现在这个 SDR 模型。仍不接 pad 延迟。`ck90` 在仿真里用理想时钟源。
4. P3。把 DDR1 pad 和一条尚未定实现的 `ck90` 接上 P2。只在 sky130、IHP、ics55。IHP 必须先有 2.5 V 下的器件仿真，否则停在这一步前面。
5. P4。DDR2。只在 55 nm，而且要另一套 1.8 V IO。目标仍是 DDR2-400。若目录中的硬宏交付了可用许可和时序模型，再写对照用的 DFI 适配器，不把前面的 PHY 掀掉。

## 11. 不这样做

- 不用 3.3 V CMOS 去推 2.5 V 的 DDR 颗粒，也不把两种 VDDIO 并在一条轨上。
- 不把现成 GPIO 当成本设计的 pad。gf180 的 5 V GPIO 特别不能接 3.3 V SDRAM。
- 不把 IHP 的 2.5 V 工作点写成已经表征的 SSTL IO。模型只给了 3.3 V 的 Vds 上限。
- 不把库单元的指宽（包括 IHP 现成 pad 的 4.4 µm / 0.6 µm）抄成我们的尺寸。
- 不把四套 PDK 都做成 DDR2。电压就不成立。
- 不等 55 nm DDR PHY 宏。本地目录写明交付物缺失，许可未定，硅验证为假。
- 不把 OpenSERDES 的 CDR 放到 DQ 上。
- 不把 SAR ADC 当成眼图仪，也不把音频 DAC 当成 VTT 或 VREF。
- 不在 ADPLL 还会返回 `FAIL_UNCHARACTERIZED` 的时候，把它的数字 Fmax 写成 DRAM 时钟指标。
- 不仿造 A7DDRPHY 或 S6DDRPHY 的 CSR 地图。
- 不做多一颗、多 rank、注册缓冲或 fly-by。
- 不把 ics55 厂商 SPICE 当成可再发布或可签核的模型。
- 不把第 7 节那些参考控制器做成 submodule。GPL-3.0 的核（`core_sdram_axi4`、`fpga-ddr-sdram`）不抄进本仓库的 Apache 源码。
- 不把 SDR 行为模型或命令间隔检查器的通过说成 tAC、tOH、tHZ、建立保持或 pad 时序已经满足。检查器只数时钟。
- 不把 `sim/gate.sh` 的 sky130 HD 功能仿真说成 SDF 时序仿真或 pad 签核。
- 不把 SPD 读进 PHY，也不把 ECC 做成一种 pad。

## 12. 还没有答案的问题

- 驱动管的宽度、指条数和预驱动级数。要等负载仿真，不能从库 GPIO 的毫安档推回来。
- `ck90` 用什么电路。现有 PLL 都不提供已知的 90°。
- IHP 的 HV 管在 2.5 V 下能否当驱动和 VREF 接收器。模型只保证了 Vds 不超过 3.3 V。
- ics55 的 3.3 V 过驱管在 3.3 V 下的寿命和阈值，以及 3.3 V ESD 二极管用哪张 SPICE 卡。LVS 有 `dio_3p3_pp_nw_lp`，foundry 清单没有。自绘 GGNMOS/GGPMOS 钳位只是 STUDY_ONLY，见 `docs/ICS55_ESD_3V3.md`；没有 TLP/HBM 数据前不改 ics55 的 `NO_GO`。
- 55 nm IO 数据手册 PDF 还没有抽成文本。现成 GPIO 的驱动电流、输入阈值和翻转时间未知，而且即使知道也不替代自研单元。
- ECOS PLL 的许可，以及两路输出能不能用作同频不同相。
- 目录中 DDR PHY 的许可与交付时间。在此之前不做适配器。
- 实际流片的 pad 数。本设计按一颗 x8 加电源来算；若某次 MPW 少于约 40 个信号 pad，先减地址并行位，不要改成串行协议。
- ~~BL>1 的写节拍~~ 已解决：`sim/sdram_model.sv` 的写突发流水线支持 BL 2/4/8（`tb/tb_burst.sv`）。
