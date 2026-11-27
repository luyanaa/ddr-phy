#!/usr/bin/env python3
"""Generate a standalone LiteDRAM controller (DFI master) for co-simulation.

The PHY is the hardened `sdram_phy_core`; this wrapper only exposes the
controller's DFI and a single native user port so a Verilog testbench can
issue reads/writes.  `read_latency` MUST match the PHY:
    sdram_phy_core = CL - 2 + CDC_LATENCY  (CDC_LATENCY >= 6)
At CL=2, CDC=6 the measured DFI latency is 7 (the CDC output register adds
one cycle on top of the nominal 6), not LiteDRAM's GENSDRPHY default CL+1=3.

Run:
  PYTHONPATH=third_party/litedram python3 sim/gen_litedram_ctrl.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "third_party" / "litedram"))

from migen import *
from migen.fhdl import verilog

from litedram.common import PhySettings, GeomSettings, TimingSettings
from litedram.core.controller import LiteDRAMController, ControllerSettings

CL = 2
CDC_LATENCY = 6
READ_LATENCY = CL - 2 + CDC_LATENCY + 1  # 7: the CDC output register adds one


class Wrapper(Module):
    def __init__(self):
        self.clock_domains.cd_sys = ClockDomain()
        self.clk = self.cd_sys.clk
        self.rst = self.cd_sys.rst

        phy_settings = PhySettings(
            phytype       = "EXT_SDR_PHY",
            memtype       = "SDR",
            databits      = 8,
            dfi_databits  = 8,
            nphases       = 1,
            rdphase       = 0,
            wrphase       = 0,
            cl            = CL,
            read_latency  = READ_LATENCY,
            write_latency = 0,
            with_dm       = True,
        )
        geom_settings = GeomSettings(bankbits=2, rowbits=13, colbits=9)
        timing_settings = TimingSettings(
            tRP=2, tRCD=2, tWR=2, tWTR=1, tREFI=780, tRFC=7,
            tFAW=4, tCCD=1, tRRD=2, tRC=6, tRAS=5, tZQCS=64,
            nWR=2,
        )
        ctrl_settings = ControllerSettings(
            cmd_buffer_buffered = True,
            with_auto_precharge  = False,
            with_refresh         = False,
            nbankmachines        = 1,
        )
        self.submodules.ctrl = LiteDRAMController(
            phy_settings, geom_settings, timing_settings, clk_freq=100e6,
            controller_settings=ctrl_settings)

        dfi = self.ctrl.dfi.p0
        self.dfi_address = dfi.address
        self.dfi_bank = dfi.bank
        self.dfi_ras_n = dfi.ras_n
        self.dfi_cas_n = dfi.cas_n
        self.dfi_we_n = dfi.we_n
        self.dfi_cs_n = dfi.cs_n
        self.dfi_cke = dfi.cke
        self.dfi_odt = dfi.odt
        self.dfi_reset_n = dfi.reset_n
        self.dfi_act_n = dfi.act_n
        self.dfi_wrdata = dfi.wrdata
        self.dfi_wrdata_en = dfi.wrdata_en
        self.dfi_wrdata_mask = dfi.wrdata_mask
        self.dfi_rddata = dfi.rddata
        self.dfi_rddata_valid = dfi.rddata_valid
        self.dfi_rddata_en = dfi.rddata_en

        # Single native port: expose the pieces a TB needs.
        port = self.ctrl.interface.bank0
        self.user_cmd_valid = port.valid
        self.user_cmd_ready = port.ready
        self.user_cmd_we = port.we
        self.user_cmd_addr = port.addr
        self.user_cmd_lock = port.lock
        self.user_wdata = self.ctrl.interface.wdata
        self.user_wdata_we = self.ctrl.interface.wdata_we
        self.user_wdata_ready = port.wdata_ready
        self.user_rdata = self.ctrl.interface.rdata
        self.user_rdata_valid = port.rdata_valid


def main():
    m = Wrapper()
    ios = {
        m.clk, m.rst,
        m.dfi_address, m.dfi_bank, m.dfi_ras_n, m.dfi_cas_n, m.dfi_we_n,
        m.dfi_cs_n, m.dfi_cke, m.dfi_odt, m.dfi_reset_n, m.dfi_act_n,
        m.dfi_wrdata, m.dfi_wrdata_en, m.dfi_wrdata_mask,
        m.dfi_rddata, m.dfi_rddata_valid, m.dfi_rddata_en,
        m.user_cmd_valid, m.user_cmd_ready, m.user_cmd_we,
        m.user_cmd_addr, m.user_cmd_lock,
        m.user_wdata, m.user_wdata_we, m.user_wdata_ready,
        m.user_rdata, m.user_rdata_valid,
    }
    out = ROOT / "sim" / "litedram_ctrl.v"
    out.write_text(str(verilog.convert(m, ios=ios, name="litedram_ctrl")))
    print("wrote %s (CL=%d read_latency=%d)" % (out, CL, READ_LATENCY))


if __name__ == "__main__":
    main()
