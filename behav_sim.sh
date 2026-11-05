#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: bash behav_sim.sh TB_NAME [--gui]" >&2
    exit 2
}

[[ $# -ge 1 ]] || usage
TB_NAME=$1
shift
[[ "$TB_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || usage
CONFIG_GUI=0
for option in "$@"; do
    case "$option" in
        --gui) CONFIG_GUI=1 ;;
        *) usage ;;
    esac
done

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TB_PATH="$ROOT/bottleneck/bench/$TB_NAME"
TB_FILES="$TB_PATH/$TB_NAME.f"
PATH_LOG="$TB_PATH/.log"
[[ -f "$TB_FILES" ]] || { echo "[ ERROR ] File list not found: $TB_FILES" >&2; exit 1; }

WINDOWS=0
case "$(uname -s)" in
    MINGW*|MSYS*) WINDOWS=1 ;;
esac

# Vivado's Windows entry points are batch files; Linux uses shell executables.
for tool in xvlog xelab xsim; do
    tool_name=$tool
    if (( WINDOWS )); then tool_name="$tool.bat"; fi
    command -v "$tool_name" >/dev/null || {
        echo "[ ERROR ] $tool_name not found. Add the Vivado bin directory to PATH." >&2
        exit 1
    }
done

tool_path() {
    if (( WINDOWS )); then
        cygpath -am "$1"
    else
        printf '%s\n' "$1"
    fi
}

run_tool() {
    local tool=$1
    shift
    if (( WINDOWS )); then
        # Git Bash dispatches batch files through CMD. Paths are converted above.
        MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 "$tool.bat" "$@"
    else
        "$tool" "$@"
    fi
}

mkdir -p -- "$PATH_LOG"
# File-list paths are relative to the testbench directory, as in behav_sim.bat.
(
    cd -- "$TB_PATH"
    while IFS= read -r source || [[ -n "$source" ]]; do
        source=${source%$'\r'}
        source=${source#"${source%%[![:space:]]*}"}
        source=${source%"${source##*[![:space:]]}"}
        [[ -z "$source" || "$source" == \#* ]] && continue
        [[ -f "$source" ]] || { echo "[ ERROR ] Source not found: $source" >&2; exit 1; }
        absolute_source="$(cd -- "$(dirname -- "$source")" && pwd)/$(basename -- "$source")"
        printf 'sv work "%s"\n' "$(tool_path "$absolute_source")"
    done < "$TB_FILES"
) > "$PATH_LOG/sources.prj"

cd -- "$PATH_LOG"
echo "[1/3] Compiling HDL..."
run_tool xvlog -prj sources.prj -i "$(tool_path "$TB_PATH")" -log compile.log || {
    echo "[ ERROR ] Compilation failed. See $PATH_LOG/compile.log" >&2
    exit 1
}

echo "[2/3] Elaborating $TB_NAME..."
run_tool xelab "$TB_NAME" -s behav_tb -debug typical -log elaborate.log || {
    echo "[ ERROR ] Elaboration failed. See $PATH_LOG/elaborate.log" >&2
    exit 1
}

echo "[3/3] Running behavioral simulation..."
run_tool xsim behav_tb -runall -log simulate.log || {
    echo "[ ERROR ] Simulation failed. See $PATH_LOG/simulate.log" >&2
    exit 1
}

if (( CONFIG_GUI )); then
    run_tool xsim behav_tb -gui -onfinish stop -runall -log xsim_gui.log || {
        echo "[ ERROR ] GUI simulation failed. See $PATH_LOG/xsim_gui.log" >&2
        exit 1
    }
fi
