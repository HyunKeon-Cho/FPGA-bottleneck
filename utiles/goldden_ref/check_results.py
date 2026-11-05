"""Independently verify only the three phase outputs and the TB-computed SNR."""
import argparse
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'bottleneck/bench/tb_core/data'
MANIFEST = Path(__file__).with_name('reference_manifest.json')
PHASE_REFERENCES = ('ref_2_relu1', 'ref_4_relu2', 'ref_ouptut')


def require(ok, message):
    if not ok:
        raise ValueError(message)


def read_hex(path):
    tokens = path.read_text(encoding='ascii').split()
    require(all(re.fullmatch(r'[0-9a-fA-F]{4}', t) for t in tokens), f'Invalid 16-bit hex: {path}')
    values = [int(t, 16) for t in tokens]
    return [v - 65536 if v >= 32768 else v for v in values]


def clip(value):
    return max(-32768, min(32767, value))


def rounded(value, divisor):
    return (-1 if value < 0 else 1) * ((abs(value) + divisor//2)//divisor)


def calculate():
    """Compute phase outputs from the TB inputs without importing the generator."""
    source = read_hex(DATA / 'ref_input.txt')
    weights = read_hex(DATA / 'ref_kernel.txt')
    require(len(source) == 288 and len(weights) == 68, 'Wrong case1 input/weight count')
    skip = source[:]
    result = {}
    for layer, (cin, cout, k, offset) in enumerate(((8, 2, 1, 0), (2, 2, 3, 16), (2, 8, 1, 52)), 1):
        conv = []
        for pixel in range(36):
            y, x = divmod(pixel, 6)
            for oc in range(cout):
                acc = 0
                for term in range(k*k*cin):
                    kp, ic = divmod(term, cin)
                    ky, kx = divmod(kp, k)
                    iy, ix = y + ky - k//2, x + kx - k//2
                    if 0 <= iy < 6 and 0 <= ix < 6:
                        acc += source[(iy*6+ix)*cin+ic] * weights[offset+oc*k*k*cin+term]
                conv.append(clip(rounded(acc, 256)))
        source = conv
        if layer < 3:
            source = [max(0, v) for v in source]
            result[f'relu{layer}'] = source
    source = [clip(a+b) for a, b in zip(source, skip)]
    source = [max(0, v) for v in source]
    pooled = []
    for pixel in range(9):
        y, x = divmod(pixel, 3)
        for c in range(8):
            pooled.append(max(source[((2*y+dy)*6+2*x+dx)*8+c] for dy, dx in ((0,0),(0,1),(1,0),(1,1))))
    result['gap'] = [clip(rounded(sum(pooled[c::8]), 9)) for c in range(8)]
    return [result['relu1'], result['relu2'], result['gap']]


def verify(run):
    expected = calculate()
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    entries = [dict(phase=i, samples=len(values), reference=f'{name}.txt',
                    float_reference=f'{name}_float.txt', actual=f'phase{i}_actual.txt')
               for i, (values, name) in enumerate(zip(expected, PHASE_REFERENCES), 1)]
    require(manifest['case'] == 1 and manifest['phases'] == entries, 'Phase manifest mismatch')
    require(manifest['files'] == dict(input='ref_input.txt', kernel='ref_kernel.txt', output='ref_ouptut.txt'), 'I/O filenames mismatch')
    log = (run / 'simulate.log').read_text(encoding='utf-8', errors='replace')
    require('[ PASS ] ALL TESTS PASSED' in log and 'Fatal:' not in log, 'TB did not complete successfully')
    observed = re.findall(r'\[ PASS \] phase(\d) \((\d+) values\), SNR=', log)
    require(observed == [('1', '72'), ('2', '72'), ('3', '8')], 'Scoreboard must run exactly once after each phase')
    tb_rows = [line.split() for line in (run / 'scoreboard_results.txt').read_text(encoding='ascii').splitlines()]
    require(len(tb_rows) == 3, 'Expected exactly three TB SNR rows')
    report = []
    for entry, oracle, tb_row in zip(entries, expected, tb_rows):
        phase = entry['phase']
        actual = read_hex(run / entry['actual'])
        stored = read_hex(DATA / entry['reference'])
        require(actual == stored == oracle, f'phase{phase}: HDL/reference/independent oracle mismatch')
        floats = [float(t) for t in (DATA / entry['float_reference']).read_text(encoding='ascii').split()]
        require(len(floats) == len(actual) and all(math.isfinite(v) for v in floats), f'phase{phase}: invalid float reference')
        noise = sum((a/256-f)**2 for a, f in zip(actual, floats))
        power = sum(f*f for f in floats)
        snr = 10*math.log10(power/noise) if noise else 1.0e300
        require(snr > 30, f'phase{phase}: SNR {snr} <= 30 dB')
        require(len(tb_row) == 3 and int(tb_row[0]) == phase and int(tb_row[1]) == len(actual), 'TB SNR row mismatch')
        tb_snr = float(tb_row[2])
        require(math.isclose(snr, tb_snr, rel_tol=1e-12, abs_tol=1e-8), f'phase{phase}: TB/Python SNR mismatch')
        report.append(dict(phase=phase, samples=len(actual), bit_mismatches=0, snr_db=snr, tb_snr_db=tb_snr,
                           max_abs_error=max(abs(a/256-f) for a, f in zip(actual, floats))))
        print(f'phase{phase}: {len(actual):2d} samples, exact match, SNR={snr:.8f} dB (TB matches)')
    (run / 'results.json').write_text(json.dumps(report, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print('PASS: 3 phase outputs / 152 values match; all TB SNR values match the independent calculation')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, default=ROOT / 'bottleneck/bench/tb_core/.log')
    verify(parser.parse_args().run)
