#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TB_PATH="$ROOT/bottleneck/bench/tb_core"
PATH_LOG="$TB_PATH/.log"
GUI=0
WINDOWS=0
for option in "$@"; do
    case "$option" in
        tb_core) ;;
        --gui) GUI=1 ;;
        *) echo "Usage: bash utiles/behav_sim.sh [tb_core] [--gui]" >&2; exit 2 ;;
    esac
done
case "$(uname -s)" in MINGW*|MSYS*) WINDOWS=1 ;; esac
for tool in xvlog xelab xsim; do
    name="$tool"
    if (( WINDOWS )); then name="$tool.bat"; fi
    command -v "$name" >/dev/null || { echo "[ ERROR ] $name not found. Add Vivado bin to PATH." >&2; exit 1; }
done
[[ -f "$TB_PATH/tb_core.f" ]] || { echo '[ ERROR ] tb_core.f not found.' >&2; exit 1; }
tool_path() {
    if (( WINDOWS )); then cygpath -am "$1"; else printf '%s\n' "$1"; fi
}
run_tool() {
    local name="$1"
    shift
    if (( WINDOWS )); then
        MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 "$name.bat" "$@"
    else
        "$name" "$@"
    fi
}
mkdir -p -- "$PATH_LOG"
(
    cd -- "$TB_PATH"
    while IFS= read -r source || [[ -n "$source" ]]; do
        source=${source%$'\r'}
        source=${source#"${source%%[![:space:]]*}"}
        source=${source%"${source##*[![:space:]]}"}
        [[ -z "$source" || "$source" == \#* ]] && continue
        [[ -f "$source" ]] || { echo "[ ERROR ] Source not found: $source" >&2; exit 1; }
        absolute="$(cd -- "$(dirname -- "$source")" && pwd)/$(basename -- "$source")"
        printf 'sv work "%s"\n' "$(tool_path "$absolute")"
    done < tb_core.f
) > "$PATH_LOG/sources.prj"
cd -- "$PATH_LOG"
: > simulate.log
echo '[1/3] Compiling HDL...'
run_tool xvlog -prj sources.prj -i "$(tool_path "$TB_PATH")" -log compile.log
echo '[2/3] Elaborating tb_core...'
run_tool xelab tb_core -s behav_tb -debug typical -log elaborate.log
echo '[3/3] Running case1...'
args=(behav_tb -runall -log simulate.log)
if (( GUI )); then args+=(-gui -onfinish stop); fi
run_tool xsim "${args[@]}"
if grep -Fq 'Fatal:' simulate.log || ! grep -Fq '[ PASS ] ALL TESTS PASSED' simulate.log; then
    echo "[ ERROR ] TB did not pass. See $PATH_LOG/simulate.log" >&2
    exit 1
fi
