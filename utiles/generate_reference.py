"""Regenerate the single case1 dataset (NumPy is needed only for this step)."""
from pathlib import Path
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'bottleneck/bench/tb_core/data'
MANIFEST = Path(__file__).with_name('reference_manifest.json')
# PCG64 state at the start of the original case1. Preserve its exact vectors
# without generating or storing the retired case0.
RNG_STATE = {
    'bit_generator': 'PCG64',
    'state': {'state': 267194245281758398137576368313602609592,
              'inc': 289872293177636917062427592788219327885},
    'has_uint32': 0, 'uinteger': 0,
}


def quantize(x):
    return np.clip(np.sign(x) * np.floor(np.abs(x) * 256 + 0.5), -32768, 32767).astype(np.int64)


def divide(x, n):
    return np.sign(x) * ((np.abs(x) + n // 2) // n)


def conv_float(x, weights):
    k = weights.shape[1]
    padded = np.pad(x, ((k//2, k//2), (k//2, k//2), (0, 0)))
    patches = np.lib.stride_tricks.sliding_window_view(padded, (k, k), axis=(0, 1))
    return np.einsum('hwcij,oijc->hwo', patches, weights)


def conv_int(x, weights):
    h, width, _ = x.shape
    cout, k, _, cin = weights.shape
    result = np.zeros((h, width, cout), dtype=np.int64)
    for y in range(h):
        for col in range(width):
            for oc in range(cout):
                acc = 0
                for ky in range(k):
                    for kx in range(k):
                        iy, ix = y + ky - k//2, col + kx - k//2
                        if 0 <= iy < h and 0 <= ix < width:
                            for ic in range(cin):
                                acc += int(x[iy, ix, ic]) * int(weights[oc, ky, kx, ic])
                result[y, col, oc] = np.clip(divide(acc, 256), -32768, 32767)
    return result


def pool(x):
    h, width, channels = x.shape
    return x.reshape(h//2, 2, width//2, 2, channels).max(axis=(1, 3))


def write_hex(path, values):
    path.write_text(''.join(f'{int(v) & 65535:04x}\n' for v in np.asarray(values).flat), encoding='ascii')


def generate():
    rng = np.random.default_rng(0)
    rng.bit_generator.state = RNG_STATE
    x = rng.uniform(-1.5, 1.5, (6, 6, 8))
    weights = [rng.normal(0, .38, (2, 1, 1, 8)),
               rng.normal(0, .30, (2, 3, 3, 2)),
               rng.normal(0, .42, (8, 1, 1, 2))]
    qx, qw = quantize(x), [quantize(w) for w in weights]
    floats, integers = {}, {}
    f, q = x, qx
    for i, (w, wi) in enumerate(zip(weights, qw), 1):
        f, q = conv_float(f, w), conv_int(q, wi)
        if i < 3:
            f, q = np.maximum(f, 0), np.maximum(q, 0)
            floats[f'relu{i}'], integers[f'relu{i}'] = f.copy(), q.copy()
    f, q = f + x, np.clip(q + qx, -32768, 32767)
    f, q = np.maximum(f, 0), np.maximum(q, 0)
    f, q = pool(f), pool(q)
    floats['gap'] = f.mean(axis=(0, 1))
    integers['gap'] = divide(q.sum(axis=(0, 1)), 9).astype(np.int64)

    DATA.mkdir(parents=True, exist_ok=True)
    write_hex(DATA / 'ref_input.txt', qx)
    write_hex(DATA / 'ref_kernel.txt', np.concatenate([w.ravel() for w in qw]))
    phase_names = ('relu1', 'relu2', 'gap')
    reference_names = ('ref_2_relu1', 'ref_4_relu2', 'ref_ouptut')
    phases = []
    for phase, (name, reference) in enumerate(zip(phase_names, reference_names), 1):
        write_hex(DATA / f'{reference}.txt', integers[name])
        np.savetxt(DATA / f'{reference}_float.txt', floats[name].ravel(), fmt='%.17g')
        phases.append(dict(phase=phase, samples=int(integers[name].size),
                           reference=f'{reference}.txt', float_reference=f'{reference}_float.txt',
                           actual=f'phase{phase}_actual.txt'))
    manifest = dict(case=1, original_seed=20261103, rng_state=RNG_STATE, format='signed Q7.8',
                    input_shape=[6, 6, 8], output_shape=[8],
                    files=dict(input='ref_input.txt', kernel='ref_kernel.txt', output='ref_ouptut.txt'),
                    phases=phases)
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print('Generated case1: 288 inputs, 68 weights, 3 phase references (8 files)')


if __name__ == '__main__':
    generate()
