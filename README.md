# Outline

이 프로젝트는 AI기반으로 소스코드를 생성헀습니다.

이 자료 그대로 dummy module을 실재 RTl로 대체하는 방식으로 작업 가능.

### 회로 디자인
- bottleneck/[rtl_dummy](bottleneck/rtl_dummy)/*.v
    - 구현 예정인 각 모듈 (완성된 디지털 회로 아님)
    - single MAC 구조
    - mac(conv, fc), relu, pooling등을 수행함.

### Testbench 구성
- bottleneck/bench/tb_core/[tb_core.v](bottleneck/bench/tb_core/tb_core.v)
    - rtl_dummy들을 연결하고, tb 수행

### 참고

- 프로젝트 관점에서는 다음과 위치로 생각하시면 될것 같아요.

```text
- zynq proccessor
    └ ResNet.c
   ↕
- AXI-interconnet
   ↕
- DMA
   ↕
- axi_bottleneck.v              : axi interface 컨트롤
    └ top_bottleneck.v
        └ BRAM_buffer.v         : 버퍼 저장소
        └ bottleneck.v          : 메인 모듈
            ┠ controller.v      : 컨트롤러 (tb의 일부 동작 수행)
            └ core.v            : 연산 수행 모듈 (tb 대상)
                └ mac.v         : dummy rtl 영역
                └ relu.v
                └ ...
```

# How to run Behavioral simulation

- in Linux jump to step 3

1. open git bash
2. bash setup (if you need)

    ```bash
    export PATH="/c/{vivado path}/bin:$PATH"
    ```

3. download

    ```bash
    git clone https://github.com/HyunKeon-Cho/FPGA-bottleneck.git
    cd FPGA-bottleneck
    ```

4. run

    ```bash
    # without Vivado GUI
    bash utiles/behav_sim.sh tb_core

    # with Vivado GUI
    bash utiles/behav_sim.sh tb_core --gui
    ```

# Appendix

- [TB bottleneck structure & flow](docs/bottleneck_flow.md)
- [input model & data arrange rules](docs/appendix.md)

# Update Log

- 2026.11.06 15:00
    1. core 모듈의 interface를 enable 단일 구성으로 수정
    2. (1)에 맞추어 tb_core.sv 및 하위 모듈 수정
    3. VScode 기반 
- 2026.11.06 15:58
    1. gui 옵션 버그 수정