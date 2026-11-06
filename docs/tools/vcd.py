"""
vcd.py - a small VCD reader, enough for the waveform figures in docs/media.

    v = VCD('enh.vcd')
    v.value('tb_all_enhancements.fast.dut.PC_E', 215000)   # value at a time (in the file's timescale)
    v.changes('tb_all_enhancements.fast.dut.PC_E')         # [(time, value or None for x/z), ...]
"""
import bisect


class VCD:
    def __init__(self, path):
        self.ids = {}         # id code -> [full names]
        self.width = {}       # full name -> bits
        self.sig = {}         # full name -> [(time, value)]
        self.timescale_ps = 1
        self._parse(path)

    def _parse(self, path):
        scope, t = [], 0
        data = {}
        with open(path) as f:
            tokens = iter(f.read().split())
        for tok in tokens:
            if tok == '$scope':
                next(tokens)
                scope.append(next(tokens))
                next(tokens)
            elif tok == '$upscope':
                scope.pop()
                next(tokens)
            elif tok == '$var':
                _kind, width, code, name = next(tokens), int(next(tokens)), next(tokens), next(tokens)
                tok = next(tokens)
                while tok != '$end':
                    tok = next(tokens)
                full = '.'.join(scope + [name])
                self.ids.setdefault(code, []).append(full)
                self.width[full] = width
                data.setdefault(code, [])
            elif tok == '$timescale':
                spec = ''
                tok = next(tokens)
                while tok != '$end':
                    spec += tok
                    tok = next(tokens)
                num = int(''.join(c for c in spec if c.isdigit()) or 1)
                unit = spec.lstrip('0123456789')
                self.timescale_ps = num * {'s': 10**12, 'ms': 10**9, 'us': 10**6, 'ns': 1000, 'ps': 1, 'fs': 1e-3}[unit]
            elif tok.startswith('$'):
                if tok in ('$dumpvars', '$dumpall', '$dumpon', '$dumpoff', '$end'):
                    continue
                while tok != '$end':
                    tok = next(tokens)
            elif tok[0] == '#':
                t = int(tok[1:])
            elif tok[0] in 'bB':
                code = next(tokens)
                bits = tok[1:]
                val = None if any(c in 'xXzZ' for c in bits) else int(bits, 2)
                if code in data:
                    data[code].append((t, val))
            elif tok[0] in '01xXzZ':
                code = tok[1:]
                val = int(tok[0]) if tok[0] in '01' else None
                if code in data:
                    data[code].append((t, val))
        for code, names in self.ids.items():
            for n in names:
                self.sig[n] = data[code]
        self._times = {n: [c[0] for c in ch] for n, ch in self.sig.items()}

    def find(self, suffix):
        hits = [n for n in self.sig if n == suffix or n.endswith('.' + suffix)]
        if len(hits) != 1:
            raise KeyError('%s: %d matches' % (suffix, len(hits)))
        return hits[0]

    def changes(self, name):
        return self.sig[self.find(name)]

    def value(self, name, t):
        n = self.find(name)
        i = bisect.bisect_right(self._times[n], t) - 1
        return self.sig[n][i][1] if i >= 0 else None

    def ns(self, t):
        return t * self.timescale_ps / 1000.0
