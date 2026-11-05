# 3-phase 모델과 인터페이스

## 모델과 제어

입력은 batch=1, 6×6×8이며 채널은 8→2→2→8이다. Conv1·Conv3은 1×1, Conv2는 3×3 padding 1이다.
모든 convolution은 stride 1, 커널을 뒤집지 않는 cross-correlation이다. 가중치는 총 68개이며
Conv1·2·3의 시작 인덱스는 0·16·52다. 학습된 분류 모델, bias, BN, projection skip은 포함하지 않는다.

고정 연결은 MAC→Residual→ReLU→Pool→GAP이다. 다음 설정은 phase가 완전히 종료된 뒤에만 바뀐다.

| 설정 | Phase1 | Phase2 | Phase3 |
|---|---|---|---|
| enable (MAC/Residual/ReLU/Pool/GAP) | 1/0/1/0/0 | 1/0/1/0/0 | 1/1/1/1/1 |
| MAC iteration | 8 | 18 | 2 |
| Pool / GAP iteration | 4 / 9 | 4 / 9 | 4 / 9 |
| MAC 입력 쌍 | 576 | 1296 | 576 |
| 마지막 포트 출력 | 72 | 72 | 8 |

`controller()`는 초기화 후 각 phase의 `data_schedule()`을 호출하고, MAC 입력 공급과 Phase3 skip 공급을 병행한다.
공급 완료와 마지막 출력 수신, 모든 출력 valid 해제를 확인한 뒤 `scoreboard()`를 호출한다.
Scoreboard 완료 후 다음 phase로 넘어간다. 개별 레이어 완료 통보나 검증 handshake는 없다.

## 전역 데이터와 순서

다음 값은 모두 `tb_core`의 전역 배열이다. Task 지역 변수는 인덱스와 임시 계산값만 보관한다.

| 배열 | 역할 |
|---|---|
| `global_input[0:287]` | 원본 입력 및 residual 원본 |
| `global_kernel[0:67]` | 원본 가중치 |
| `global_activation_schedule[0:2][0:1295]` | phase별 배치한 activation |
| `global_kernel_schedule[0:2][0:1295]` | 같은 인덱스의 activation에 대응하는 kernel |
| `global_skip_schedule[0:287]` | Phase3 MAC 출력 좌표 순서에 맞춘 skip |
| `global_phase_output[0:2][0:287]` | 실제 마지막 포트 출력; 유효 길이는 72·72·8 |

각 phase의 arrange 결과는 다음 phase에서 덮어쓰지 않는다. 정답 파일은 다음 phase 입력에 사용하지 않는다.
Phase2는 실제 Phase1 출력, Phase3은 실제 Phase2 출력을 사용한다.

```text
NHWC feature 주소 = (y×W+x)×C+c
kernel 주소 = base+((oc×K+ky)×K+kx)×Cin+ic
```

Phase1·2의 출력 좌표는 y→x→출력 채널 순서다. 해당 출력의 MAC 입력은 kernel y→x→입력 채널 순서이며,
경계 밖 activation은 0으로 넣는다. Phase3 출력 좌표는 다음 순서다.

```text
채널 c → pooling window 행·열 → window 내부 좌상·우상·좌하·우하
```

Skip도 같은 좌표에서 읽는다. 같은 채널의 네 값이 Pool에 연속 도착하여 하나의 값을 만들고,
그 채널의 Pool 결과 9개가 GAP에 연속 도착하여 하나의 평균을 만든다.
Phase1·2는 NHWC, 최종 GAP은 채널 순서이므로 scoreboard에서 별도 재배치하지 않는다.

## 모듈 처리 규칙

입력·출력은 상승 에지 `valid && ready`에서만 전달한다. TB는 하강 에지에 입력과 sink ready를 구동한다.
중간 모듈 ready는 다음 모듈의 입력 ready와 직접 연결한다. 최종 sink에는 고정 seed의 backpressure를 적용한다.

MAC·Pool·GAP의 iteration은 5비트, 사용하는 범위는 1~31이고 내부 묶음 버퍼는 31개다.
입력 묶음이 다 모이면 compute task를 실행하고 등록된 출력으로 전달한다.
출력을 모두 전달할 때까지 다음 입력 묶음을 받지 않는다. 비활성화 상태도 동일한 수집 조건을 적용하며,
모인 입력 N개를 같은 순서로 N개 출력한다. 입력과 출력 개수를 줄이지 않는다.

- MAC: activation과 kernel을 공통 valid/ready로 동시에 받아 저장한다. 활성화 시 dot product 하나를 출력한다.
- Residual: iteration 없이 main·skip을 각각 독립 valid/ready로 한 개 보관한다. 둘 다 준비되면 합산한다.
  비활성화 시 main만 그대로 내보내며 skip_ready는 0이다.
- ReLU: 입력 하나당 결과 하나. 활성화 시 음수를 0으로, 비활성화 시 그대로 출력한다.
- Pool: 활성화 시 iteration개 입력의 signed 최댓값 하나를 출력한다.
- GAP: 활성화 시 iteration개 입력의 평균 하나를 출력한다.

데이터와 포트 이름은 `mac_kernel_data`, `residual_skip_ready`, `pooling_iteration`처럼 역할을 명시한다.
기존 operand 선택 iteration 비트 및 in_last 포트는 제거했다.

## 수치·reset·판정

Q7.8 값은 signed 정수/256이며 범위는 -128~127.99609375다. MAC은 곱 전체를 64비트로 더한 뒤
256으로 나누어 한 번 반올림한다. MAC과 GAP은 최근접 반올림하고 정확히 절반이면 0에서 멀어지는 방향이다.
MAC·Residual·GAP은 16비트 포화를 적용한다. Conv3 결과를 먼저 포화한 뒤 residual을 더한다.

비동기 reset은 부분 입력·출력 대기 상태를 버린다. TB의 진행 중 controller task와 그 producer들을 취소하고
phase·수신 개수를 초기화한다. 자동 재개하지 않으며 재실행은 controller()를 Phase1부터 다시 호출한다.

Scoreboard는 phase 경계에서만 세 번 호출한다. 정수 정확 일치와 real 연산 기반 SNR>30 dB를 검사하고,
phase 실제 출력 3개와 scoreboard_results.txt를 저장한다. SNR은 다음과 같다.

```text
10 × ln(Σ reference_float² / Σ(reference_float - actual_integer/256)²) / ln(10)
```

양자화 전 float 정답을 사용하므로 입력·가중치·중간 결과의 양자화 오차를 포함한다.
잡음이 0인 경우에는 무한 SNR을 나타내는 큰 양수(1e300)를 기록한다.
Python 검사기는 원본 입력부터 별도로 계산하여 152개 값과 TB SNR을 대조한다.

`data/`에는 입력·가중치, Phase1/2의 정수·실수 정답, 최종 출력의 정수·실수 정답 8개만 둔다.
파일 누락·개수·hex/float 형식·읽기/쓰기 오류는 실패 처리한다. 별도 설정값·용량·timeout 검사는 없다.
이 구현은 task 기반 동작 검증이며 실제 FPGA 파이프라인, 자원, 주파수, 처리량이나 인식 정확도는 검증하지 않는다.
