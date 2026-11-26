# SPDX-License-Identifier: Apache-2.0
"""Compile a bounded pad subcircuit with explicit BSIM4 PM3 bins for Xyce."""

import math
import os
import re
import subprocess
from pathlib import Path

from binselect import eval_nominal, parse_bins, select_bin


def _fields(tokens):
    positional, params = [], {}
    for token in tokens:
        if token == 'params:':
            continue
        name, sep, value = token.partition('=')
        if sep:
            if not name or not value or name in params:
                raise ValueError(f'invalid subcircuit parameter {token!r}')
            params[name] = value
        elif params:
            raise ValueError(f'unexpected token after parameters: {token}')
        else:
            positional.append(token)
    return positional, params


def _subcircuits(source):
    subs = {}
    current = None
    for raw in source.splitlines():
        line = raw.split('$', 1)[0].strip().lower()
        if not line or line.startswith('*'):
            continue
        head, *tail = line.split()
        if head == '.subckt' and current is None and tail:
            name = tail[0]
            pins, defaults = _fields(tail[1:])
            if name in subs or not pins or len(pins) != len(set(pins)):
                raise ValueError(f'invalid subcircuit {line}')
            body = []
            subs[name] = (pins, defaults, body)
            current = name
        elif head == '.ends' and current is not None and tail in ([], [current]):
            current = None
        elif current is not None and head[0] in 'xd':
            connection, params = _fields(tail)
            if len(connection) < 3:
                raise ValueError(f'invalid device {line}')
            body.append((head, connection[:-1], connection[-1], params))
        else:
            raise ValueError(f'unsupported pad netlist line: {raw.strip()}')
    if current is not None:
        raise ValueError(f'unclosed subcircuit: {current}')
    return subs


def _number(value, scope):
    # Sizing netlist grammar: numbers in micrometres or references to formal parameters.
    result = scope[value[1:-1]] if value.startswith('{') and value.endswith('}') else float(value)
    if not math.isfinite(result) or result <= 0:
        raise ValueError(f'non-positive or non-finite geometry: {value}')
    return result


def _resistance(model, w, length):
    weff = w + model['width_offset_um'] - model['narrow_factor'] * max(model['narrow_below_um'] - w, 0)
    leff = length + model['length_offset_um']
    return (model['head_sheet_ohm'] * model['head_length_um'] / (weff + model['head_width_offset_um'])
            + model['body_sheet_ohm'] * leff / weff)


class BinnedPad:
    """Keep the pad boundary, flatten nested devices, and bind a corner on demand."""

    def __init__(self, pdk, device_map, source, top):
        self.pdk = pdk
        self.spec = device_map['ddr1']['xyce']
        slots = device_map['slots']
        self.mos = {slots[key]['device'].lower(): key.split('_', 1)[0].lower()
                    for key in ('NMOS_IO', 'PMOS_IO', 'NMOS_CORE', 'PMOS_CORE')}
        self.diodes = {slots[key]['device'].lower(): params
                       for key, params in self.spec['diodes'].items()}
        self.resistor = slots['RES_SERIES']['device'].lower()
        self.geometry = {}
        self.parameters = []
        self._corners = {}
        subs = _subcircuits(source)
        top = top.lower()
        pins, defaults, _ = subs[top]
        lines = ['* SSTL-2 Xyce pad; signoff=false', f'.subckt {top} {" ".join(pins)}']

        def walk(target, nodes, scope, prefix, stack):
            if target in stack:
                raise ValueError(f'recursive subcircuit {target}')
            _, _, body = subs[target]
            for name, raw_nodes, device, params in body:
                path = prefix + name
                terminals = [nodes.get(n, prefix + n) if n != '0' else '0' for n in raw_nodes]
                if device in subs:
                    ports, declared, _ = subs[device]
                    if len(ports) != len(terminals) or params.keys() - declared.keys():
                        raise ValueError(f'wrong pins or parameters on {path}')
                    child = {k: _number(v, scope) for k, v in (declared | params).items()}
                    walk(device, dict(zip(ports, terminals)), child, path + '/', (*stack, target))
                    continue
                entry = dict(path=path, device=device)
                index = len(self.parameters) + 1
                conn = ' '.join(terminals)
                if device in self.mos and len(terminals) == 4:
                    if params.keys() - {'w','l','nf','mult','m'} or {'m','mult'} <= params.keys():
                        raise ValueError(f'unsupported MOS parameters on {path}: {params}')
                    w, l = (_number(params[k], scope) for k in ('w','l'))
                    nf = _number(params.get('nf','1'),scope)
                    mult = _number(params.get('m',params.get('mult','1')),scope)
                    if not nf.is_integer():
                        raise ValueError(f'non-integer finger count on {path}')
                    key = (device, w/nf, l)
                    model = self.geometry.setdefault(key, f'sstl2_m{len(self.geometry)+1}')
                    lines.append(f'M{index} {conn} {model} w={w*1e-6:.12g} l={l*1e-6:.12g} nf={nf:g} m={mult:g}')
                    entry.update(w_um=w, l_um=l, nf=int(nf), mult=mult, model=model)
                elif device == self.resistor and len(terminals) == 3 and params.keys() == {'w','l'}:
                    w, l = (_number(params[k], scope) for k in ('w','l'))
                    ohm = _resistance(self.spec['resistor'], w, l)
                    lines.append(f'R{index} {terminals[0]} {terminals[1]} {ohm:.12g}')
                    entry.update(w_um=w, l_um=l, nominal_ohm=ohm)
                elif device in self.diodes and len(terminals) == 2 and params.keys() <= {'area'}:
                    area = _number(params.get('area','1'),scope)
                    lines.append(f'D{index} {conn} {device} area={area:g}')
                    entry.update(area_um2=area)
                else:
                    raise ValueError(f'unsupported pad device {path}: {device}')
                self.parameters.append(entry)

        walk(top, {p:p for p in pins}, {k:_number(v,{}) for k,v in defaults.items()}, '', ())
        lines.append(f'.ends {top}')
        self.netlist = '\n'.join(lines) + '\n'

    def corner(self, corner):
        if corner in self._corners:
            return self._corners[corner]
        lines = [f'* Explicit {corner} PM3 bins; linear poly and level-1 diode approximations; signoff=false']
        families = {}
        for (device, wpf, l), model in self.geometry.items():
            if device not in families:
                path = self.pdk / self.spec['pm3'].format(device=device, corner=corner)
                families[device], _ = parse_bins(path.read_text())
            chosen = select_bin(families[device], wpf*1e-6, l*1e-6)
            if chosen is None:
                raise ValueError(f'{device} {corner}: no bin for w/finger={wpf:g} um, l={l:g} um')
            params, residual, _ = eval_nominal(chosen.body)
            if not params or residual:
                raise ValueError(f'{chosen.name}: unsupported nominal parameter expression')
            lines.extend((f'* {chosen.name} w/finger={wpf:g} um l={l:g} um',
                          f'.model {model} {self.mos[device]}', *params[1:]))
        for device, params in self.diodes.items():
            values = ' '.join(f'{k}={v}' for k,v in params.items())
            lines.append(f'.model {device} d level=1 {values}')
        result = '\n'.join(lines) + '\n'
        self._corners[corner] = result
        return result


def run_xyce(deck, bench, body, expected):
    try:
        proc = subprocess.run([os.environ.get('XYCE', 'Xyce'), deck.name], cwd=deck.parent,
                              capture_output=True, text=True, timeout=600)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f'{deck.name}: cannot run Xyce: {error}') from error
    log = proc.stdout + '\n' + proc.stderr
    if proc.returncode:
        raise SystemExit(f'{deck.name}: Xyce exit {proc.returncode}\n{log[-6000:]}')
    if 'Unrecognized dot line will be ignored' in log:
        warning = re.search(r'(?m)^.*\n\s*Unrecognized dot line will be ignored[^\n]*', log)
        raise SystemExit(f'{deck.name}: unsupported Xyce directive\n{warning[0] if warning else log}')
    suffix = '.ms0' if bench == 'dc' else '.mt0'
    output = Path(str(deck) + suffix)
    if not output.is_file():
        raise SystemExit(f'{deck.name}: missing Xyce measurements\n{log[-6000:]}')
    fields = dict((k.strip().lower(), v.strip()) for k,v in
                  (line.split('=',1) for line in output.read_text().splitlines() if '=' in line))
    crossings = {line.split()[2] for line in body.splitlines()
                 if line.startswith('.meas ') and re.search(r'\b(?:TRIG|WHEN)\b',line)}
    measures = {}
    for name in expected:
        value = fields.get(name)
        if value == 'FAILED' and name in crossings:
            measures[name] = None
            continue
        try:
            parsed = float(value)
        except (TypeError, ValueError) as error:
            raise SystemExit(f'{deck.name}: invalid Xyce measurement {name}: {value!r}') from error
        if not math.isfinite(parsed):
            raise SystemExit(f'{deck.name}: non-finite Xyce measurement {name}: {value!r}')
        measures[name] = parsed
    elapsed = re.search(r'Total Elapsed Run Time:\s+([0-9.eE+-]+) seconds', log)
    if not elapsed:
        raise SystemExit(f'{deck.name}: missing Xyce completion summary\n{log[-6000:]}')
    return measures, float(elapsed[1])
