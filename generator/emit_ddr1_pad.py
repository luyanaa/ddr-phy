#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Materialize a native-ngspice or Xyce DDR1 pad from an existing backend YAML."""

import argparse
import json
from pathlib import Path
import runpy

import yaml

from char_ddr1_sstl2 import ROOT, native_corner, pdk_root_for, simulator_for, temperature_line
from ddr1_xyce import BinnedPad
from tune_ddr1 import _load_adapter, _load_config, _search_space


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', type=Path, required=True)
    parser.add_argument('--pdk-root')
    parser.add_argument('--out-dir', type=Path, required=True)
    parser.add_argument('--case', action='append', help='repeat to select cases; default: all')
    args = parser.parse_args()
    try:
        config = _load_config(args.backend)
        adapter = _load_adapter(ROOT / config['adapter'])
        adapter.validate_config(config, ROOT)
        _, knobs, _ = _search_space(config)
        path = adapter.source_path(config, ROOT)
        source = adapter.render_netlist(config, ROOT, path.read_text(), knobs)
        profile_override = config['characterization'].get('profile')
        profile_path = ROOT / profile_override if profile_override else adapter.characterizer_path(config, ROOT)
        profile = runpy.run_path(str(profile_path))['PROFILE']
        devices = yaml.safe_load((ROOT / profile['device_yaml']).read_text())
        pdk = pdk_root_for(profile, devices, args.pdk_root)
        simulator = simulator_for(devices)
        cases = {name:profile['cases'][name] for name in dict.fromkeys(args.case or profile['cases'])}
        pad = BinnedPad(pdk, devices, source, profile['subckt']) if simulator == 'xyce' else None
        corners = {name: (pad.corner(mos) if pad else native_corner(profile, devices, pdk, mos, res))
                         + f'\n{temperature_line(simulator, temp)}\n'
                   for name, (mos, res, temp, _, _) in cases.items()}
    except (KeyError, OSError, ValueError) as error:
        parser.error(str(error))
    out = args.out_dir
    out.mkdir(parents=True)
    (out / 'corners').mkdir()
    (out / 'sstl2_dq.spice').write_text(pad.netlist if pad else source)
    for name, text in corners.items():
        (out / 'corners' / f'{name}.inc').write_text('* DDR1 witness model include; signoff=false\n' + text)
    if simulator == 'ngspice':
        init = profile.get('spiceinit','').replace('@root@',str(pdk))
        (out / '.spiceinit').write_text('set num_threads=1\n' + init)
    info = dict(signoff=False, process=profile['name'], simulator=simulator, subckt=profile['subckt'],
                pdk=str(pdk), license=profile.get('license',''), cell_source=str(path.relative_to(ROOT)),
                knobs=knobs, cases={name:dict(mos=m,res=r,temp_c=t,vdd=v,vddio=i,
                                            include=f'corners/{name}.inc')
                                   for name,(m,r,t,v,i) in cases.items()})
    if pad:
        info['devices'] = pad.parameters
        info['passives'] = 'Nominal linear high-poly; level-1 ESD diodes without sidewall or high-injection model.'
    (out / 'parameters.json').write_text(json.dumps(info,indent=2) + '\n')
    print(f'{out}: {profile["name"]} {simulator}, {len(corners)} cases, signoff=false')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
