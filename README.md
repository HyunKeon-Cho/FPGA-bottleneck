# 3-phase bottleneck behavioral simulation

case1(6×6×8 입력, signed 16-bit Q7.8)을 다음 고정 파이프라인으로 한 번 실행합니다.
각 모듈은 task 기반 동작 모델이며 실제 FPGA 자원·타이밍을 모델링하지 않습니다.

```text
MAC → Residual → ReLU → Pooling → GAP
```

## 실행

Vivado `xvlog`, `xelab`, `xsim`을 PATH에 등록한 뒤 실행합니다. 저장된 데이터로 바로 실행할 수 있습니다.

```powershell
.\behav_sim.bat
```

Linux / Git Bash에서는 `bash behav_sim.sh`를 사용합니다. 기존 `tb_core` 인자와 `--gui` 옵션도 유지합니다.
GUI 옵션은 GUI에서 한 번 실행하며, 기본 실행 후 다시 실행하는 중복 절차는 없습니다.

## phase와 task

| 항목 | Phase1 | Phase2 | Phase3 |
|---|---|---|---|
| 활성 연산 | Conv1→ReLU1 | Conv2→ReLU2 | Conv3→Residual→ReLU3→Pool→GAP |
| MAC iteration | 8 | 18 | 2 |
| Pool / GAP iteration | 4 / 9 | 4 / 9 | 4 / 9 |
| activation·kernel 쌍 | 576 | 1296 | 576 |
| phase 출력 | 6×6×2, 72개 | 6×6×2, 72개 | 8개 |

`tb_core.v`에 다음 세 task가 있습니다.

- `data_schedule(phase)`: 입력·가중치·이전 phase의 실제 출력으로 전역 arrange 배열을 채웁니다.
- `controller()`: 초기 reset과 파일 로딩, phase 설정, 전송·수집, phase 전환을 제어합니다.
- `scoreboard(phase)`: phase 경계에서만 정수 일치·SNR을 판정하고 실제 출력을 저장합니다.

Scoreboard는 Phase1 종료, Phase2 종료, 최종 종료에 **총 3회** 수행합니다.
개별 레이어 출력은 감시·수집·비교하지 않습니다. 마지막 GAP 출력 포트에서만 결과를 받습니다.
성공 표시는 `[ PASS ] ALL TESTS PASSED`입니다.

모든 모듈에 enable이 있습니다. MAC·Pool·GAP은 5비트 iteration(1~31)개를 모아 task를 수행합니다.
비활성화 상태에서도 iteration개를 모은 뒤 입력 묶음 전체를 순서대로 출력합니다.
MAC의 activation·kernel은 공통 handshake로 동시에 받습니다. Residual은 iteration 없이 main·skip을 독립적으로 받습니다.

## 데이터와 결과

참조 데이터는 `bottleneck/bench/tb_core/data/`의 아래 **8개 파일**만 사용합니다.

| 용도 | 정수 파일 | SNR용 실수 파일 |
|---|---|---|
| 입력 288개 | `ref_input.txt` | — |
| 가중치 68개 | `ref_kernel.txt` | — |
| Phase1 출력 72개 | `ref_2_relu1.txt` | `ref_2_relu1_float.txt` |
| Phase2 출력 72개 | `ref_4_relu2.txt` | `ref_4_relu2_float.txt` |
| 최종 출력 8개 | `ref_ouptut.txt` | `ref_ouptut_float.txt` |

요청한 `ref_ouptut` 철자를 유지합니다. 입력·정수 정답은 4자리 known hex입니다.
Phase1·2는 NHWC, Phase3 최종 결과는 채널 순서입니다. 미사용 중간 레이어 데이터는 생성하지 않습니다.

실행 산출물은 TB의 `.log/` 아래에만 생성합니다.

- `phase1_actual.txt`, `phase2_actual.txt`, `phase3_actual.txt`: 실제 phase 출력
- `scoreboard_results.txt`: TB가 계산한 phase별 원소 수와 SNR
- `compile.log`, `elaborate.log`, `simulate.log`: 실행 로그
- `results.json`: 선택적 독립 Python 검증 결과

```powershell
python utiles/check_results.py
```

Python 표준 라이브러리만 사용합니다. 원본 입력부터 별도로 계산한 152개 값과 실제 출력·정답을 비교하고,
TB의 SNR 계산도 대조합니다. 기준값은 Phase1 약 49.52 dB, Phase2 약 44.63 dB, 최종 약 59.15 dB입니다.

## 데이터 재생성 (선택)

일반 시뮬레이션에는 Python이나 NumPy가 필요하지 않습니다. 데이터를 다시 만들 때만 다음을 실행합니다.

```powershell
python -m pip install -r utiles/requirements.txt
python utiles/generate_reference.py
```

기존 case1 시작 시점의 PCG64 상태를 고정하여 입력·가중치·phase 정답을 그대로 재현합니다.
`reference_manifest.json`에는 입력·가중치와 phase 출력 3개의 파일·크기를 기록합니다.

파일 누락·형식·개수·읽기/쓰기 실패는 즉시 실패 처리합니다. 정답 일치와 SNR은 테스트 판정입니다.
설정값·용량·timeout 방어 검사는 추가하지 않습니다.

상세 데이터 순서와 인터페이스 규칙은 [부록](docs/appendix.md)을 참고하세요.
