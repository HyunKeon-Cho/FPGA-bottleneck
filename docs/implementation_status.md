# 3-phase TB 구현 현황 및 재개 메모

기록일: 2026-11-05 (Asia/Seoul)

**현재 상태: 핵심 구현과 정상 실행 검증은 완료. 오류 주입·controller 재시작·최종 파일 정리는 미완료.**
사용자 요청으로 이 지점에서 작업을 멈췄다. 구현 완료로 보고하지 않았으며, 다음 작업은 아래 미완료 항목부터 이어간다.

## 확정 요구사항

- 물리 연결: `MAC → Residual → ReLU → Pooling → GAP`.
- `tb_core`의 `data_schedule(phase)`, `controller()`, `scoreboard(phase)` task로 구성한다.
- Scoreboard는 Phase1 종료, Phase2 종료, Phase3 최종 종료에 정확히 3회만 실행한다.
- MAC은 activation·kernel을 공통 valid/ready로 동시에 받는다.
- Residual은 iteration 없이 main·skip을 독립 valid/ready로 각각 하나씩 받아 둘 다 준비되면 합산한다.
- 모든 모듈에 enable을 두고, iteration이 있는 모듈은 disable 상태에서도 N개를 모은 뒤 N개를 그대로 출력한다.
- MAC·Pool·GAP iteration은 5비트(사용 범위 1~31), 버퍼 최대 31개다. 출력 묶음이 모두 전달되기 전에는 다음 묶음을 받지 않는다.
- Arrange 결과와 phase 실제 출력은 TB 모듈 범위의 전역 배열에 보관한다.
- Phase1·2 결과는 NHWC, Phase3 최종 결과는 채널 순서다.
- 예외 방어 코드는 파일 읽기·쓰기·형식·개수 오류에 한정한다. 용량·설정값·timeout 방어 검사는 추가하지 않는다.

| 설정 | Phase1 | Phase2 | Phase3 |
|---|---|---|---|
| enable: MAC/Residual/ReLU/Pool/GAP | 1/0/1/0/0 | 1/0/1/0/0 | 1/1/1/1/1 |
| MAC iteration | 8 | 18 | 2 |
| Pool / GAP iteration | 4 / 9 | 4 / 9 | 4 / 9 |
| activation·kernel 쌍 | 576 | 1296 | 576 |
| 최종 포트 출력 수 | 72 | 72 | 8 |

## 구현한 내용

### 모듈 및 TB

- `bottleneck/rtl_dummy/`의 5개 모듈을 위 인터페이스와 task 기반 묶음 처리로 변경했다.
- 기존 `in_last` 및 operand 선택 iteration 비트를 제거했다.
- `tb_core.v`에서 각 모듈을 직접 직렬 연결했다. 중간 ready는 다음 모듈의 in_ready에서 받으며, 마지막 GAP sink에만 고정 seed backpressure를 준다.
- `data_schedule()`은 이전 phase의 실제 출력으로 다음 입력을 만든다. 정답 파일은 schedule에 사용하지 않는다.
- Phase3 순서는 `채널 → pooling window 행·열 → 좌상·우상·좌하·우하`이며 skip도 같은 좌표 순서다.
- 수집 지점은 GAP 출력 포트 하나다. 레이어별 scoreboard 및 stage 통보 인터페이스는 제거했다.
- `scoreboard()`가 정수 정확 일치, float 정답 대비 real SNR 계산, phase actual 저장을 수행한다.
- `controller()`는 phase 출력 수신·파이프라인 출력 valid 해제를 확인하고 scoreboard 후 다음 phase로 간다.
- Reset handler는 진행 중 controller task와 producer를 `disable controller`로 취소한다. 이 구문은 XSim 컴파일/정상 실행을 통과했지만, 실제 중간 reset 후 재시작 검증은 아직 남아 있다.
- `.f`에서 `embedded_controller.v`를 제외했다. **파일 자체는 아직 삭제하지 않았다.**

전역 배열:

```text
global_input[0:287]
global_kernel[0:67]
global_activation_schedule[0:2][0:1295]
global_kernel_schedule[0:2][0:1295]
global_skip_schedule[0:287]
global_phase_output[0:2][0:287]
```

### 생성기·독립 검사기·문서

- `utiles/generate_reference.py`는 입력·가중치와 phase 출력 3개만 저장하도록 수정했다.
- 기존 `ref_9_gap_float.txt`를 복사하여 `ref_ouptut_float.txt`를 준비했다.
- `utiles/reference_manifest.json`은 phase 3개 기준으로 갱신했다.
- `utiles/check_results.py`는 독립 정수 모델의 phase 결과 152개와 TB가 계산한 SNR을 대조한다.
- README와 `docs/appendix.md`를 새 구조로 수정했다.
- **문서는 최종 8개 파일 구성을 설명하지만, 실제 데이터 폴더의 불필요한 파일 삭제는 아직 하지 않았다.**

## 완료한 검증과 근거

### 정상 통합 실행

`bottleneck/bench/tb_core/.log/simulate.log`:

```text
phase1: 72 values, SNR=49.51751614 dB
phase2: 72 values, SNR=44.62567447 dB
phase3:  8 values, SNR=59.14606901 dB
ALL TESTS PASSED
finish: 49720 ns
```

- TB scoreboard 정확히 3회 호출.
- 독립 Python 검사: 152개 정수 출력 모두 일치, TB/Python SNR 일치.
- 재생성 전후 유지할 8개 참조 파일의 SHA256이 모두 동일함을 확인했다.
- `git diff --check`는 통과했다. 줄바꿈 변환 안내만 있다.

### 별도 모듈 계약 시험

임시 소스: `.log/tb_module_contract.v`.

- Icarus Verilog 및 XSim 모두 통과.
- 23개 group 시험, 139개 출력 비교.
- iteration 1/31 및 실제 사용 길이 2/4/8/9/18.
- MAC activation·kernel 동시 수신, signed 포화와 양수·음수 tie 반올림.
- Residual main 선도착·skip 선도착·동시 도착, disable 시 skip 미수신.
- 모든 모듈의 음수 포함 bypass, 출력 정지 중 valid/data 유지와 다음 묶음 입력 차단.
- 부분 입력 및 미수신 출력에 대한 모듈 reset.

XSim 근거: `.log/module_contract.log`.
임시 시험 소스의 timeout은 시험 자체의 중단 장치이며 제품 TB에는 추가하지 않았다.

### 전역 arrange export

- `.log/tb_schedule_probe.v`를 XSim에서 실행해 통합 PASS와 schedule export를 확인했다.
- `.log/schedule_dump.txt`에 3개 phase의 activation·kernel 2448쌍과 skip 288개가 기록되어 있다.
- **이 dump를 독립 모델과 원소별 대조하는 작업은 아직 하지 않았다.**

## 다음 작업: 미완료 항목

1. **Arrange dump 독립 검증**
   - `utiles/check_results.py`의 `calculate()`로 phase 출력 3개를 얻는다.
   - Phase1 source는 ref_input, Phase2 source는 독립 Phase1 결과, Phase3 source는 독립 Phase2 결과를 사용한다.
   - Phase1·2의 NHWC convolution stream, Phase3의 채널·window 순서와 padding·kernel 주소를 재구성한다.
   - `.log/schedule_dump.txt`의 모든 activation/kernel 쌍과 skip을 비교한다.

2. **파일 오류 주입 실행**
   - 임시 소스 `.log/tb_file_fault.v`, XSim snapshot `file_fault`는 생성·컴파일 완료했다.
   - `hex_fault=<파일>` / `float_fault=<파일>` plusarg는 Phase1 정답 파일 경로를 바꾼다.
   - `.log/hex_short.txt`, `hex_extra.txt`, `hex_empty.txt`, `hex_invalid.txt`, `hex_unknown.txt`, `hex_wide.txt`가 있다. `hex_missing.txt`는 의도적으로 없다.
   - float도 short/extra/empty/invalid/trailing/infinite 파일이 있고 `float_missing.txt`는 없다.
   - `-testplusarg write_fault`는 actual 파일 경로를 존재하지 않는 디렉터리로 바꾼다.
   - 각 경우에 해당 파일 오류의 Fatal이 있고 전체 PASS가 없는지 확인한다. XSim은 Fatal에도 종료 코드 0을 줄 수 있으므로 반드시 로그를 검사한다.
   - float `1e999` 등에 대한 검사도 준비했으나 아직 실행하지 않았다.

3. **Controller 중간 reset 후 재시작**
   - 임시 소스 `.log/tb_restart_probe.v`, snapshot `restart_probe`는 생성·컴파일 완료했다.
   - `reset_mode=1`: Phase1 MAC 부분 입력 중 reset.
   - `reset_mode=2`: Phase2 마지막 출력이 막힌 상태에서 reset.
   - `reset_mode=3`: Phase3 Residual 부분 입력 상태에서 reset.
   - 취소된 producer가 다시 움직이지 않는지 확인한 뒤 wrapper가 `dut.controller()`를 호출하여 Phase1부터 재실행한다.
   - abort PASS와 이후 3개 phase 및 전체 PASS를 로그로 확인한다. 이 테스트의 임시 timeout도 제품 TB에는 포함되지 않는다.

4. **승인된 불필요 파일 정리**
   - `bottleneck/bench/tb_core/embedded_controller.v` 삭제.
   - 데이터 폴더에서 아래 8개를 제외한 중간 참조 및 미사용 빈 inner 파일 삭제.
   - 기존 `.log/case1_*_actual.txt` 등 레이어별 실제 출력과 오래된 로그 정리.
   - 임시 테스트 소스와 snapshot은 검증을 마친 뒤 정리하되, 시험 결과 요약은 남긴다.
   - 삭제 전에 실제 현재 파일과 수정 상태를 다시 확인한다. 새 사용자 작업이나 다른 경로를 일괄 삭제하지 않는다.

유지할 데이터 8개:

```text
ref_input.txt
ref_kernel.txt
ref_2_relu1.txt
ref_2_relu1_float.txt
ref_4_relu2.txt
ref_4_relu2_float.txt
ref_ouptut.txt
ref_ouptut_float.txt
```

5. **최종 실행 및 일관성 확인**
   - Windows 배치와 Git Bash 실행 및 독립 검사 통과.
   - 기본 실행의 actual 파일이 phase1/2/3 세 개뿐인지 확인.
   - 참조 파일 8개, scoreboard 3회, 출력 72/72/8, SNR 및 정수 일치 확인.
   - 삭제한 파일·옛 stage 인터페이스를 참조하는 코드/문서가 없는지 검색.
   - 최종 `git diff --check` 확인. commit/push는 요청받지 않았다.

## 재개용 명령과 환경

프로젝트 루트:
`C:\Users\idec\Desktop\chohyunkeon\project\FPGA-bottleneck`

```powershell
$taskPython = 'C:/Users/idec/AppData/Roaming/uv/python/cpython-3.14-windows-x86_64-none/python.exe'
.\behav_sim.bat
& $taskPython utiles/check_results.py
& 'C:/Program Files/Git/bin/bash.exe' --noprofile --norc ./behav_sim.sh
```

Vivado는 `C:/Xilinx/Vivado/2022.2/bin`에 있으며 PATH에 등록되어 있다.
기본 `python` 명령은 WindowsApps 별칭 문제로 사용할 수 없어 위 실제 실행 파일을 사용했다.
검사기는 표준 라이브러리만 사용한다. 생성기 검증은 캐시된 NumPy 2.5.4 환경에서 다음처럼 실행했다.

```powershell
& 'C:/Users/idec/.local/bin/uv.exe' run --no-project --with numpy==2.5.4 --python $taskPython utiles/generate_reference.py
```

임시 snapshot 실행은 TB `.log`에서 한다. Windows batch wrapper에서 `name=value` 인자를 보존하려면 CMD의 인용을 유지한다.

```powershell
Push-Location bottleneck/bench/tb_core/.log
cmd /d /c 'xsim.bat file_fault -runall -testplusarg "hex_fault=hex_short.txt" -log hex_short.log'
cmd /d /c 'xsim.bat restart_probe -runall -testplusarg "reset_mode=1" -log restart_mode1.log'
Pop-Location
```

직전 세션에서 제한된 환경의 Vivado 내부 C 컴파일은 실패하고 승인된 실행에서는 통과했다.
따라서 같은 환경에서 실행 제약으로 실패하면 코드 문제로 단정하지 말고 실행 권한·로그를 함께 확인한다.
`.log`는 Git 제외 경로이므로 다른 PC로 이관할 때 임시 시험 소스·snapshot이 자동 전달되지 않는다.
현재 작업 트리에는 이전 대화부터 이어진 미커밋 변경이 많다. `git reset/clean`으로 기존 작업을 되돌리지 않는다.
