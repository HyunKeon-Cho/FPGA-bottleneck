"""Reproducible learning-sized bottlenecks; numpy float oracle + integer loop oracle."""
from pathlib import Path
import json
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
WORK = Path(__file__).resolve().parent
DATA = WORK / 'data'
BENCH = ROOT / 'bottleneck/bench/tb_core/data'
SCALE = 256

def quantize(x):
    return np.clip(np.sign(x)*np.floor(np.abs(x)*SCALE+0.5), -32768, 32767).astype(np.int64)

def divide(x, n):
    return np.sign(x)*((np.abs(x)+n//2)//n)

def conv_float(x, w):
    k = w.shape[1]
    padded = np.pad(x, ((k//2,k//2),(k//2,k//2),(0,0)))
    patches = np.lib.stride_tricks.sliding_window_view(padded, (k,k), axis=(0,1))
    return np.einsum('hwcij,oijc->hwo', patches, w)

def conv_int(x, w):
    h,width,_ = x.shape
    co,k,_,ci = w.shape
    y = np.zeros((h,width,co), dtype=np.int64)
    for row in range(h):
        for col in range(width):
            for oc in range(co):
                acc = 0
                for ky in range(k):
                    for kx in range(k):
                        iy,ix = row+ky-k//2,col+kx-k//2
                        if 0 <= iy < h and 0 <= ix < width:
                            for ic in range(ci):
                                acc += int(x[iy,ix,ic])*int(w[oc,ky,kx,ic])
                y[row,col,oc] = np.clip(divide(acc,256),-32768,32767)
    return y

def pool(x):
    h,w,c = x.shape
    return x.reshape(h//2,2,w//2,2,c).max(axis=(1,3))

def write_hex(path, values):
    path.write_text(''.join(f'{int(v)&65535:04x}\n' for v in np.asarray(values).flat), encoding='ascii')

def snr(ref, got):
    power = float(np.sum(np.asarray(ref)**2))
    noise = float(np.sum((np.asarray(ref)-np.asarray(got))**2))
    return 10*np.log10(power/noise) if noise else float('inf')

def generate():
    DATA.mkdir(parents=True,exist_ok=True)
    rng = np.random.default_rng(20261103)
    all_x,all_w,all_y = [],[],[]
    cases=[]
    for case,h in enumerate((4,6)):
        x = rng.uniform(-1.5,1.5,(h,h,8))
        weights = [rng.normal(0,.38,(2,1,1,8)),rng.normal(0,.30,(2,3,3,2)),rng.normal(0,.42,(8,1,1,2))]
        qx,qw = quantize(x),[quantize(w) for w in weights]
        f,q = x,qx
        stages_f,stages_q={},{}
        for i,(w,wi) in enumerate(zip(weights,qw)):
            f,q = conv_float(f,w),conv_int(q,wi)
            stages_f[f'conv{i+1}'],stages_q[f'conv{i+1}'] = f.copy(),q.copy()
            if i < 2:
                f,q = np.maximum(f,0),np.maximum(q,0)
                stages_f[f'relu{i+1}'],stages_q[f'relu{i+1}'] = f.copy(),q.copy()
        f,q = f+x,np.clip(q+qx,-32768,32767)
        stages_f['residual'],stages_q['residual'] = f.copy(),q.copy()
        f,q = np.maximum(f,0),np.maximum(q,0)
        stages_f['relu3'],stages_q['relu3'] = f.copy(),q.copy()
        if case:
            f,q=pool(f),pool(q)
            stages_f['pool'],stages_q['pool'] = f.copy(),q.copy()
        stages_f['output'],stages_q['output'] = f.copy(),q.copy()
        fg = f.mean(axis=(0,1))
        qg = divide(q.sum(axis=(0,1)),q.shape[0]*q.shape[1]).astype(np.int64)
        stages_f['gap'],stages_q['gap'] = fg,qg
        write_hex(DATA/f'case{case}_input.txt',qx)
        write_hex(DATA/f'case{case}_kernel.txt',np.concatenate([w.ravel() for w in qw]))
        for name,values in stages_q.items():
            write_hex(DATA/f'case{case}_{name}.txt',values)
            np.savetxt(DATA/f'case{case}_{name}_float.txt',stages_f[name].ravel(),fmt='%.17g')
        cases.append(dict(case=case,input_shape=list(x.shape),output_shape=list(q.shape),pooling=bool(case),
                          stages_snr_db={name:snr(stages_f[name],v/256) for name,v in stages_q.items()}))
        all_x.extend(qx.ravel()); all_w.extend(np.concatenate([w.ravel() for w in qw])); all_y.extend(q.ravel())
    # Existing bench files are the actual concatenated simulation inputs/references.
    for name,values in [('input',all_x),('kernel',all_w),('output',all_y)]:
        write_hex(BENCH/f'{name}.txt',values)
    (WORK/'reference_manifest.json').write_text(json.dumps(dict(seed=20261103,format='signed Q7.8',cases=cases),indent=2),encoding='utf-8')
    print(json.dumps(cases,indent=2))

if __name__ == '__main__':
    generate()
