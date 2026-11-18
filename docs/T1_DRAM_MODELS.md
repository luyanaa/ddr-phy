# OpenSPARC T1 DDR2/FBDIMM 行为模型 — 研究与继承方案

状态：**已在本机落地评估，不入 git。** 与 `docs/DRAM_MODEL_REFERENCES.md` 中 Micron 模型的处理一致。

## 1. 来源与许可

| 项 | 值 |
|---|---|
| 来源 | `~/t1_dram_models/`（OpenSPARC T1 发布树抽取） |
| 落地 | `third_party/reference/opensparc_t1/`（**`.gitignore` 排除**） |
| 许可 | **GPL-2.0**（每文件头部 Sun 版权块，"License version 2"） |
| 规模 | 9 个文件 / 696 KB |

**许可结论：GPL-2.0 是 copyleft。把这些 `.v` 提交进本 Apache-2.0 仓库会污染下游再分发，与 `ARCHITECTURE.md` §7 "GPL-3.0 代码不进本仓库" 的精神一致，故不入库。** GPL-2.0 与 GPL-3.0 在这一点上同等处理。模型只作本机评估与结构参考；任何移植产出的**新写**文件（见 §4）从需求出发重写，不复制 T1 代码行，保持 Apache-2.0。

## 2. 文件清单与角色

```
model_verilog/
  mem/dram/dimm.v            10 KB   DDR2 UDIMM/RDIMM 行为模型（核心）
  i2c/data/spd_*.data         4 KB   SPD EEPROM 十六进制镜像（单/堆叠 DIMM）
env_cmp/
  ch_mem.v                   27 KB   单通道 DIMM 组装层（含厂商 ifdef 分支）
  cmp_dram.v                160 KB   4 通道顶层：实例化 4×ch_mem + SPD I2C + 故障注入
  cmp_mem.v                  54 KB   DRAM BIST / 比较环境
  cmp_dram_mon.v              6 KB   cmp_dram 的 wrapper 监视器
  dram_mon.v                388 KB   全芯片 DRAM 协议监视器（层次引用，T1 专用）
  dimm_if_mon.v              13 KB   DIMM 接口协议/时序监视器（较通用）
```

## 3. `dimm.v` 结构分析（核心模型）

```verilog
module dimm(clk, cs, ras, cas, we, ba, addr, cs_sel,
            dataq, ecc, dqs, dm_rdqs);
```

- **命令解码**（`{cs_d[0],ras_d,cas_d,we_d}` 在 `posedge clk`）：
  `0101`=Read、`0100`=Write、`0011`=Activate、`0000`=MRS/EMRS。
  注意 `cs` 是**高有效**（T1 习惯），`ras/cas/we` 低有效。
- **MRS 解码**：`ba==0` → `BurstLen=1<<addr[2:0]`、`CasLat=addr[6:4]`；
  `ba==1`（EMRS）→ `AlignLat=addr[5:3]`（posted-CAS AL，DDR2 特性）。
- **延迟管线**：`read_queue`/`write_queue` 是 32 级移位寄存器，在 `posedge`+`negedge`
  双边沿推进（DDR 数据率）；读出位置 `2*ReadLat`，写入 `2*WriteLat+1`，
  `ReadLat = AlignLat+CasLat`，`WriteLat = ReadLat-1`。
- **DQS 生成**：读时 `dqs_oe` 提前 2 级拉高，`dqs_out` 每拍翻转 → 产生 DDR strobe。
- **双向端口**：`dataq/ecc/dqs/dm_rdqs` 全部 `inout`，`z` 态当 OE 拉低 —— 总线争用
  建模正确。
- **参数**：`addr_width=17`、`bank_width` 由 `DRAM_BANK_BITS2` 切换 2/3、`dqs_width=9`；
  `dly=400`(ps) 是命令采样延时。

### 3.1 移植障碍：私有 PLI 存储

**这是关键。** `dimm.v` 不在 RTL 里存数据，而是用 Sun 私有 VCS PLI：

```verilog
$read_mem (datah,   data[3:0],  faddr, cs_sel);   // 每 4 位 nibble 一个句柄
$write_mem(datah,   data[3:0],  faddr, cs_sel);
```

`datah`/`ecch` 是 integer 句柄，指向 C 侧稀疏内存（`cs_sel` 选 die/rank 分区）。
`iverilog`/`verilator` **没有这两个系统任务** —— 实测：

```
$ iverilog -g2005 tb_dimm.v dimm.v
dimm.v:251: Error: System task/function $read_mem() is not defined
```

精化通过（`tb` 例化 OK），**运行期**才报。`iverilog` 可注册 VPI 回调，但那是 C
扩展，不适合本项目轻量 TB。

## 4. 继承方式（建议）

三层，按价值/工作量排序：

### 4.1 首选：本地 PLI 补丁（保留原模型）

在 `opensparc_t1/` 内加一个小 SystemVerilog 包，把 `$read_mem`/`$write_mem`
换成 `reg [3:0] mem [0:DEPTH]` 数组（`sim/sdram_model.sv` 已有的写法）：

- 改 `Read_mem`/`Write_mem`：把 16 个 nibble 循环换成一次 `mem[faddr]` 读写
  （`faddr = {row, col, bank, burst}` 已拼好）。
- `datah/ecch` 句柄删除，`cs_sel` 退化进 `faddr` 高位即可（本项目单 rank）。
- 改动 ~40 行，**仍是 GPL 派生物**，所以只能留在 `reference/` 本机用 —
  但它是**最快的功能验证路径**：命令/延迟/总线争用行为是 Sun 硅前验证过的。

### 4.2 参考重写：自研 DDR2 行为模型

本项目 roadmap 有 DDR2（`docs/DRAM_MODEL_REFERENCES.md` §3.3、item 19）。`dimm.v`
的**结构**（非代码）是干净的模板：

| 需求 | T1 `dimm.v` 的做法 | 自研模型可借鉴 |
|---|---|---|
| DDR 数据率 | 双 `always` 块 @posedge+negedge 推进队列 | 同构（iverilog 支持） |
| Posted-CAS AL | `AlignLat`（EMRS1 解码）加进 `ReadLat` | 必须有，DDR2 特有 |
| DQS 前置 | `dqs_oe` 提前 2 级，`dqs_out` 翻转 | 生成 DDR strobe 的标准做法 |
| 双向总线 | `assign dq = oe ? out : 'z` | 与 `sim/sdram_model.sv` 一致 |
| Bank/行保持 | `RowAddr[bank]` 数组 | 已有同款模式 |

新文件 `sim/ddr2_model.sv` **从需求重写**（命令真值表、延迟管线、inout 建模），
不逐行抄 —— 产出是 Apache-2.0，可进 `sim/` 参与 `run.sh`。这就是"继承"：
继承行为契约与延迟结构，不继承代码行。

### 4.3 协议监视器移植

`dimm_if_mon.v`（13 KB）是 4 个信号组（CK/CKE/RST、CS/BA/ADDR、RAS/CAS/WE、
DQ/CB/DQS）的断言监视器，比 `dram_mon.v`（388 KB、T1 层次引用）通用得多。
可参照其检查项写我们自己的 `sim/ddr2_checker.sv`（对照
`sim/sdram_checker.sv` 的既有模式）。

## 5. 不做的事

- **不提交** `third_party/reference/opensparc_t1/`（GPL-2.0，gitignored）。
- 不把 Denali/Infineon/Micron `ifdef` 分支当可用路径 —— `ch_mem.v` 只有
  `dimm` 分支自包含，其余引用缺失的厂商模型。
- 不移植 `dram_mon.v` / `cmp_mem.v` / `cmp_dram.v`：它们硬编码 T1 四通道拓扑、
  层次引用 `` `DRAM_PATH0 ``、和 BIST 环境，与本项目 PHY-only 范围无关。
- 不用 T1 的 `dly=400ps`/`ReadLat` 推导覆盖 `specs/devices/*.yaml` —— 同
  Micron 模型教训：模型内置参数≠本项目 timing contract。

## 6. 下一步

1. （本机）写 `opensparc_t1/dimm_iverilog.v`：§4.1 的 PLI→数组补丁，配一个
   MRS→ACT→WR→RD 冒烟 TB，确认读回数据 —— 验证模型行为本身可信。
2. （入库）按 §4.2 写 `sim/ddr2_model.sv`（Apache-2.0），挂到 `sim/run.sh` 的
   DDR2 lane（P4 roadmap 项）。
3. （入库）按 §4.3 写 `sim/ddr2_checker.sv`。
