# 배치 · 인터페이스

[구조 · Flow](bottleneck_flow.md)

## 설정

`batch=1 · H=W=6 · signed 16-bit Q7.8 · stride=1 · cross-correlation`
`bias / BN / projection skip 없음 · task 동작 검증`

| 설정 | Phase1 | Phase2 | Phase3 |
|---|---|---|---|
| Cin→Cout / K / padding | 8→2 / 1 / 0 | 2→2 / 3 / 1 | 2→8 / 1 / 0 |
| kernel base | 0 | 16 | 52 |
| enable: MAC/Residual/ReLU/Pool/GAP | 1/0/1/0/0 | 1/0/1/0/0 | 1/1/1/1/1 |
| iteration: MAC/Pool/GAP | 8/4/9 | 18/4/9 | 2/4/9 |
| MAC 입력 쌍 / 출력 수 | 576 / 72 | 1296 / 72 | 576 / 8 |

## 배열

`tb_core.sv 전역 · 용량=BUFFER_SIZE=1296 · 배치 task: input 원본 → output 버퍼`

| 배열 | 유효 개수 | 용도 |
|---|---:|---|
| feature / kernel | 288 / 68 | 원본 보존 |
| feature_buf / kernel_buf | 각각 576→1296→576 | phase별 MAC 입력 |
| skip_buf | 288 | Phase3 residual |
| output_data | 72→72→8 | 현재 실제 출력 |

## 주소 · 배치

```text
feature_addr(y, x, c) = (y*W + x)*C + c
kernel_addr(oc, ky, kx, ic) = base + ((oc*K + ky)*K + kx)*Cin + ic

Phase1: source = feature
Phase2: source = 이전 output_data

for y, x, oc, ky, kx, ic:
    iy = y + ky - K//2
    ix = x + kx - K//2
    feature_buf.append(source[iy, ix, ic] if 범위 안 else 0)
    kernel_buf.append(kernel[kernel_addr(oc, ky, kx, ic)])

Phase3: source = 이전 output_data
for oc, window_y, window_x:
    for (dy, dx) in [(0,0), (0,1), (1,0), (1,1)]:
        y, x = 2*window_y + dy, 2*window_x + dx
        skip_buf.append(feature[y, x, oc])
        for ic:
            feature_buf.append(source[y, x, ic])
            kernel_buf.append(kernel[52 + oc*2 + ic])
```

```text
Phase1·2 출력: y → x → channel (NHWC)
Phase3 입력  : channel → window 행·열 → 좌상·우상·좌하·우하
               4개 → Pool → 9개 → GAP → 채널별 출력

검증 → 다음 입력 전체 배치 → core_run → output_data 덮어쓰기
정답 파일 ─×→ 입력 배치
```

## Handshake

```text
negedge clk: TB 입력·sink ready 구동
posedge clk: valid && ready일 때만 전달

MAC/Pool/GAP (iteration: 5-bit, N=1..31):
    N개 수집 → enable ? 결과 1개 : 입력 N개 그대로
    출력 전부 전달 → 다음 묶음 수집

Residual:
    main·skip 독립 수신 → 둘 다 준비 → 포화 합산
    disable → main 그대로, skip_ready=0

ReLU: enable ? max(0, input) : input
Pool: signed max(N개)
GAP : rounded mean(N개)
출력 stall: valid·data 유지
```

## 수치 · 판정

```text
real_value = signed_integer / 256
sat16(x)   = clamp(x, -32768, 32767)
round(x)   = 최근접 반올림, tie는 0에서 멀어지는 방향

MAC      = sat16(round(sum(feature*kernel) / 256))  // 64-bit 누산
Residual = sat16(포화된 Conv3 결과 + 원본 skip)
GAP      = sat16(round(sum(pool) / 9))

scoreboard(actual_buf, size, reference_name):
    actual_buf[0..size-1] == 정수 정답
    actual_real = actual_buf / 256
    SNR = 10*log10(sum(float_ref²) / sum((float_ref-actual_real)²))
    잡음=0 → SNR=1e300
    assert SNR > 30 dB
    phase번호 = 호출 순서             // 총 3회
    저장: phase{번호}_actual.txt, scoreboard_results.txt
```

| 입력·정답 | 파일 |
|---|---|
| 원본 | ref_input.txt, ref_kernel.txt |
| Phase1 | ref_2_relu1.txt, ref_2_relu1_float.txt |
| Phase2 | ref_4_relu2.txt, ref_4_relu2_float.txt |
| Phase3 | ref_ouptut.txt, ref_ouptut_float.txt |

`data/: 8개 · .log/: 실행 결과 · 파일 열기/형식/개수 오류 → Fatal`
`중간 reset·설정값/용량/timeout 방어·FPGA 자원/타이밍 검증 제외`

## 코드 스타일

```systemverilog
// ------------------------------------
// {part name or module name}
// ------------------------------------
```

`인자·변수·포트: 한 줄 하나 + 열 정렬 · 단계 사이 빈 줄 · 모듈별 묶기`
