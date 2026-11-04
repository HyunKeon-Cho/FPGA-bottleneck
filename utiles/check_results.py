"""Check actual HDL output, never substitute Python predictions for simulation."""
from pathlib import Path
import json
import numpy as np
from generate_reference import snr

ROOT=Path(__file__).resolve().parent
RUN=ROOT.parent/'bottleneck/bench/tb_core/.log'
manifest=json.loads((ROOT/'reference_manifest.json').read_text())

def read_hex(path):
    values=np.array([int(s,16) for s in path.read_text().split()],dtype=np.int64)
    return np.where(values>=32768,values-65536,values)

def main():
    report=[]
    for case in manifest['cases']:
        case_id=case['case']
        for stage in case['stages_snr_db']:
            actual=read_hex(RUN/f'case{case_id}_{stage}_actual.txt')
            reference=read_hex(ROOT/'data'/f'case{case_id}_{stage}.txt')
            real_reference=np.loadtxt(ROOT/'data'/f'case{case_id}_{stage}_float.txt')
            np.testing.assert_array_equal(actual,reference,err_msg=f'case{case_id} {stage}')
            value=snr(real_reference,actual/256)
            assert value>30, (case_id,stage,value)
            report.append(dict(case=case_id,stage=stage,samples=len(actual),bit_mismatches=0,
                               snr_db=float(value),max_abs_error=float(np.max(np.abs(actual/256-real_reference)))))
    (RUN/'results.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    for row in report:
        print(f"case{row['case']} {row['stage']:9s}: {row['snr_db']:.2f} dB, {row['samples']} samples, exact Q7.8 match")
    print('PASS: all HDL stages match integer oracle; SNR > 30 dB against unquantized float64 oracle')

if __name__=='__main__':
    main()
