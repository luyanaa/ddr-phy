#!/usr/bin/env python3
"""Rank parasitic R/C by net for a flat Spectre/SPICE PEX netlist.

Supports the subset emitted by KLayout: Rxxx n1 n2 value and Cxxx n1 n2 value.
Net names carry terminal suffixes (.Tn/.Nn); they are collapsed to the base net.
"""
import argparse, collections, heapq, re, sys

SUPPLY = re.compile(r'^(VDD|VDDIO|VSS|VSSIO|DH_VDDIO|DL_VDDIO|DH_VSSIO|DL_VSSIO|0)(\.|$)')

def base(n):
    return n.split('.')[0] if n not in ('0',) else n

def read(path):
    R, C = [], []
    for line in open(path):
        t = line.split()
        if len(t) < 4 or t[0][0] not in 'RC':
            continue
        try: v = float(t[3])
        except ValueError: continue
        (R if t[0][0] == 'R' else C).append((t[1], t[2], v))
    return R, C

def diameter(edges, nodes):
    if len(nodes) < 2: return 0.0
    g = collections.defaultdict(list)
    for a, b, v in edges:
        g[a].append((b, v)); g[b].append((a, v))
    worst = 0.0
    for s in nodes:
        dist = {s: 0.0}; pq = [(0.0, s)]
        while pq:
            d, u = heapq.heappop(pq)
            if d != dist[u]: continue
            for v, w in g[u]:
                nd = d + w
                if nd < dist.get(v, 1e30):
                    dist[v] = nd; heapq.heappush(pq, (nd, v))
        worst = max(worst, max(dist.get(n, 0.0) for n in nodes))
    return worst

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('pex'); ap.add_argument('--top', type=int, default=20)
    a = ap.parse_args()
    R, C = read(a.pex)
    rsum = collections.defaultdict(float); redges = collections.defaultdict(list)
    rnodes = collections.defaultdict(set); cgnd = collections.defaultdict(float)
    ccpl = collections.defaultdict(float)
    for x, y, v in R:
        bx, by = base(x), base(y)
        if bx == by:
            redges[bx].append((x, y, v)); rnodes[bx] |= {x, y}
        else:  # shouldn't happen in a single-net resistor, keep both
            redges[bx].append((x, y, v)); redges[by].append((x, y, v))
            rnodes[bx] |= {x, y}; rnodes[by] |= {x, y}
        rsum[bx] += v; rsum[by] += v
    for x, y, v in C:
        bx, by = base(x), base(y)
        if SUPPLY.match(bx) and not SUPPLY.match(by):
            cgnd[by] += v
        elif SUPPLY.match(by) and not SUPPLY.match(bx):
            cgnd[bx] += v
        elif not SUPPLY.match(bx) and not SUPPLY.match(by):
            ccpl[bx] += v; ccpl[by] += v
    names = set(rsum) | set(cgnd) | set(ccpl)
    print(f'{len(R)} R, {len(C)} C, {len(names)} base nets')
    print('\n=== top series R ===')
    for n in sorted(names, key=lambda n: -rsum[n])[:a.top]:
        d = diameter(redges[n], rnodes[n])
        print(f'{n:28s} sum={rsum[n]:9.1f} ohm  diam={d:9.1f} ohm  nodes={len(rnodes[n])}')
    print('\n=== top total C ===')
    for n in sorted(names, key=lambda n: -(cgnd[n]+ccpl[n]))[:a.top]:
        print(f'{n:28s} gnd={cgnd[n]*1e15:8.1f} fF  cpl={ccpl[n]*1e15:8.1f} fF  total={(cgnd[n]+ccpl[n])*1e15:8.1f} fF')
    for n in ('SENSE','MIRROR','DEC_B','RX_LEVEL','A_4924_3776','A_3700_3776','A_8876_3776'):
        if n in names:
            print(f'\n[{n}] sumR={rsum[n]:.1f} diamR={diameter(redges[n],rnodes[n]):.1f} '
                  f'Cgnd={cgnd[n]*1e15:.1f}fF Ccpl={ccpl[n]*1e15:.1f}fF')

if __name__ == '__main__':
    main()
