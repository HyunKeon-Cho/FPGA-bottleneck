# Bottleneck dummy 검증

## 실행

Windows 탐색기에서는 `bottleneck/bench/tb_core/run_sim.bat`를 더블클릭하면 됩니다.
완료 후 창이 유지되므로 PASS/FAIL을 확인할 수 있습니다. 상세 SNR은 로그에 저장합니다.
터미널에서 창 대기 없이 실행하려면 `run_sim.bat --nopause`를 사용합니다 (`/nopause`도 지원).
기본값은 `bottleneck/rtl_dummy`이고 `--rtl`을 넣으면 `bottleneck/rtl`의 `.v`, `.sv` 파일을 사용합니다.
현재 `rtl`은 비어 있으므로 실제 모듈을 작성한 후 사용합니다. 빈 폴더이면 실패 이유를 로그에 남기고 종료합니다.
`--gui`는 자동 시뮬레이션과 Python 검증 통과 후 Vivado Simulator(XSim) GUI를 별도로 엽니다.
GUI는 `bottleneck/bench/tb_core/tb_core.wcfg`가 있으면 그 파형 설정을 적용합니다.
없으면 기본 인터페이스 파형을 추가합니다. 선택 결과는 GUI `.log`에 기록합니다.
설정 적용 후 다시 실행하며, `$finish` 후에도 창을 유지합니다.

```bat
run_sim.bat                         rem dummy 검증
run_sim.bat --gui                   rem dummy 검증 후 GUI
run_sim.bat --rtl                   rem rtl 폴더로 검증
run_sim.bat --rtl --gui --nopause    rem rtl 검증 후 GUI, 콘솔 대기 없음
```

모든 실행 단계의 표준 출력과 오류는 `AI_workspace/run/logs/*.log`에 저장합니다.
`run.log`는 실행 요약, `reference.log`는 레퍼런스 생성, `compile.log`/`elaborate.log`는 컴파일,
`simulate.log`/`xsim.log`는 TB 실행, `verify.log`는 Python 비교와 SNR 결과입니다.
GUI는 다음 컴파일과 충돌하지 않도록 `AI_workspace/gui_run_<실행시각>`의 별도 snapshot으로 엽니다.
GUI 메시지는 그 폴더의 `xsim_gui.log`, `gui.stdout.log`, `gui.stderr.log`에 기록하며 정확한 경로를 `run.log`에도 남깁니다.
자동 검증 로그는 실행마다 갱신됩니다. 시뮬레이터 자체의 `.jou`, 파형 등 보조 산출물도 `AI_workspace` 안에 저장됩니다.
배치 파일은 현재 Vivado PATH, `XILINX_VIVADO`, 이 PC의 기본 설치 경로 순으로 Vivado를 찾습니다.
Python과 numpy는 설치되어 있어야 합니다.

프로젝트 루트에서 Vivado 2025.2의 `xvlog`, `xelab`, `xsim`이 PATH에 있고 Python에 numpy가 설치된 상태로 실행합니다.

```powershell
.\AI_workspace\run.ps1
```

레퍼런스 생성 → HDL 컴파일 → 실제 xsim 실행 → 실제 HDL 출력 파일을 Python으로 비교합니다.
스크립트가 작업 디렉터리를 `AI_workspace/run`으로 옮기므로 모든 시뮬레이터 산출물이 그 안에 저장됩니다.
기존 bench의 빈 `input.txt`, `kernel.txt`, `output.txt`는 요청대로 채우며, 나머지 새 파일은 모두 `AI_workspace` 아래에 둡니다.
RTL은 기존 `.v` 파일에 작성했지만 TB의 배열·문자열 task 때문에 SystemVerilog 모드(`xvlog -sv`)로 컴파일합니다.

## 두 입력 구성

둘 다 batch=1, NHWC 메모리, 채널 8→2→2→8, identity skip입니다.

```text
input ─┬─ conv1(1x1) → ReLU → conv2(3x3,pad1) → ReLU → conv3(1x1) ─┐
       └────────────────────── identity skip ────────────────────────┤
                                                                  add → ReLU → [max pool] → output → GAP
```

| 구분 | 입력 | bottleneck 출력 | 선택 max pool | 최종 feature 출력 | GAP |
|---|---|---|---|---|---|
| case0 | 4×4×8 | 4×4×8 | 없음 | 4×4×8 (128개) | 8개 |
| case1 | 6×6×8 | 6×6×8 | 2×2, stride2 | 3×3×8 (72개) | 8개 |

pooling은 두 번째 bottleneck의 마지막 ReLU 뒤에 붙였습니다. skip과 main의 크기를 유지하는 학습용 구성입니다.
GAP은 두 경우 모두 별도로 검증합니다. `output.txt`는 GAP 전 feature 출력입니다.
학습된 모델이 아닌 seed=20261103의 임의 입력과 가중치이며, bias=0, BN은 identity로 생략했습니다.
따라서 실제 ResNet의 정확도나 논문의 성능을 재현하는 검증은 아닙니다.
참고 논문의 streaming compute, ReLU, pooling, residual, GAP 구성을 기초 구조의 방향으로 참고했습니다.

## 수치 규칙

사용자 확인에 따라 IEEE FP16 대신 **signed 16bit Q7.8**로 통일했습니다.

- 값 = signed word / 256, 범위 -128 ~ 127.99609375, LSB=1/256.
- 입력과 가중치 양자화, MAC 결과, residual, GAP: 최근접 반올림, 정확히 절반이면 0에서 멀어지는 방향.
- 모듈 출력에서 signed 16bit 범위로 포화합니다.
- MAC의 내부 누산만 64bit Q*.16으로 확장합니다. 각 곱을 Q7.8로 자르지 않고 dot product 전체가 끝난 뒤 한 번 반올림합니다.
- max pool과 ReLU는 원래 Q7.8 값을 그대로 선택합니다.
- `.txt`는 한 줄당 16bit 2의 보수 hex 하나이며 `$readmemh`로 읽습니다.

## 기존 포트 사용 규칙

포트를 추가하지 않았습니다. `out_valid`, `out_data`만 procedural assignment를 위해 `wire`에서 `reg`로 바꿨습니다.
모든 입력과 출력은 상승 에지에서 `valid && ready`인 경우에만 전달됩니다.
출력 대기 중 `out_valid`, `out_data`를 유지하고, 공간이 없으면 `in_ready=0`으로 입력을 막습니다.
`nrst=0`은 비동기 reset이며 누산 중인 값과 미수신 출력도 버립니다.

| 모듈 | 입력 직렬화와 완료 조건 |
|---|---|
| mac | activation(`iteration=0`) 다음 weight(`iteration=1`)를 보냅니다. 마지막 weight의 `in_last=1`이 dot product를 끝내고 출력 1개를 만듭니다. |
| relu | 입력 하나당 출력 하나. 프레임 처리가 없어 `in_last`는 사용하지 않습니다. |
| residual | main 값(`in_last=0`) 다음 skip 값(`in_last=1`)으로 합계 하나를 만듭니다. |
| pooling | 한 채널의 window 값들을 보내고 마지막 값에 `in_last=1`. window 최대값 하나를 만듭니다. |
| general_average_pooling | 한 채널의 공간 값들을 보내고 마지막 값에 `in_last=1`. 평균 하나를 만듭니다. |

`iteration`은 기존에 정의된 의미가 없어서 위와 같이 operand 선택 신호로 정의했습니다.
출력에는 `out_last`가 없으므로 TB가 레이어의 예상 출력 개수를 셉니다.
모듈 연산은 각각 `compute` task에서 수행하며 실제 MAC 파이프라인이나 합성 가능한 core 설계가 아닙니다.

## TB와 메모리

TB는 `feature`, `skip`, `weights` 메모리를 관리합니다. 각 모듈은 TB 메모리나 다른 모듈 내부 상태를 참조하지 않습니다.
TB의 수신기는 매 사이클 출력 handshake를 감시하여 모듈별 `captured` 메모리에 결과를 저장합니다.
레이어 완료 개수를 확인하면 task가 다음 레이어의 feature 메모리로 옮겨 재사용합니다.
레이어는 순차 실행하고 송신 task와 수신 감시기는 독립적으로 동작합니다.

`convolution` task가 NHWC feature를 output y,x,channel 순으로 순회하면서 kernel y,x,input channel 순서의 MAC 스트림으로 바꿉니다.
padding=0 삽입도 TB가 담당합니다. kernel 메모리 순서는 O,KY,KX,I입니다.
pooling task는 공간 2×2 window를 채널별로 직렬화하고 GAP task는 채널별 공간 스트림을 만듭니다.

기존 bench 파일의 순서는 case0 다음 case1입니다.

| 파일 | case0 offset/count | case1 offset/count |
|---|---|---|
| input.txt | 0 / 128 | 128 / 288 |
| kernel.txt | 0 / 68 | 68 / 68 |
| output.txt | 0 / 128 | 128 / 72 |

case당 kernel 68개는 conv1 16개, conv2 36개, conv3 16개 순서입니다.
`data/case*`에는 중간 정수 레퍼런스와 실수 레퍼런스를 따로 둡니다.

## 검증 결과

`run/logs/xsim.log`의 `ALL TESTS PASSED` 및 `results.json`을 확인합니다.
Python 실수 모델은 numpy window/einsum, 정수 모델은 별도 중첩 loop로 convolution을 계산합니다.
실수 모델은 입력과 가중치를 양자화하기 전 float64 값에서 출발하므로 입력·가중치·중간 출력 양자화 오차까지 SNR에 포함됩니다.
`check_results.py`는 **시뮬레이터가 실제로 기록한 값**으로 모든 단계의 정확 일치와 실수 기준 SNR > 30dB를 확인합니다.

SNR = 10 log10(sum(reference²) / sum((reference - actual/256)²)).

| 결과 | case0 | case1 |
|---|---:|---:|
| 최종 feature SNR | 50.03 dB | 57.70 dB |
| GAP SNR | 49.56 dB | 59.15 dB |
| 모든 중간 단계의 최소 SNR | 41.16 dB | 43.47 dB |
| 정수 레퍼런스와 다른 값 | 0 | 0 |

추가로 signed 포화 양쪽 경계, 양수·음수 tie 반올림, 음수 max pool, ReLU 경계,
MAC/pool/residual/GAP 중간 상태와 ReLU 미수신 출력이 있는 상태의 reset을 검증합니다.
재현 가능한 의사난수 backpressure 및 입력 bubble을 주며, 대기 중 출력 안정성과 전체 출력 개수도 검사합니다.

| 모듈 | 입력 전달 수 | 출력 전달 수 | 출력 stall 사이클 | 입력 대기 사이클 |
|---|---:|---:|---:|---:|
| MAC | 7072 | 624 | 1152 | 642 |
| ReLU | 624 | 624 | 1317 | 950 |
| Pool | 288 | 72 | 139 | 74 |
| Residual | 832 | 416 | 1076 | 770 |
| GAP | 200 | 16 | 35 | 20 |

시뮬레이션 완료 시간은 232330ns입니다. task 연산으로 계산 지연을 모델링하지 않았으므로 이 시간에서 실제 core 처리량을 추정하면 안 됩니다.
