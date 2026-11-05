#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------
# init
# ----------------------------------------------------------------
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

PATH_BASE_TB="$ROOT/bottleneck/bench"
CONFIG_GUI=0
WINDOWS=0

usage() {
    echo "Usage: bash behav_sim.sh TB_NAME [--gui]" >&2
    exit 2
}

[[ $# -ge 1 ]] || usage
TB_NAME="$1"
TB_PATH="$PATH_BASE_TB/$TB_NAME"
PATH_LOG="$TB_PATH/.log"
TB_FILES="$TB_PATH/$TB_NAME.f"
shift

# ----------------------------------------------------------------
# options
# ----------------------------------------------------------------
[[ "$TB_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || usage
for OPTION in "$@"; do
    case "$OPTION" in
        --gui)
            CONFIG_GUI=1
            ;;
        *)
            usage
            ;;
    esac
done

# ----------------------------------------------------------------
# check environment
# ----------------------------------------------------------------
if [[ ! -f "$TB_FILES" ]]; then
    echo "[ ERROR ] File list not found: \"$TB_FILES\"." >&2
    exit 1
fi

case "$(uname -s)" in
    MINGW*|MSYS*)
        WINDOWS=1
        ;;
esac

for TOOL in xvlog xelab xsim; do
    TOOL_NAME="$TOOL"
    if (( WINDOWS )); then
        TOOL_NAME="$TOOL.bat"
    fi
    if ! command -v "$TOOL_NAME" >/dev/null; then
        echo "[ ERROR ] $TOOL_NAME not found. Add the Vivado bin directory to PATH." >&2
        exit 1
    fi
done

# ----------------------------------------------------------------
# platform helpers
# ----------------------------------------------------------------
tool_path() {
    if (( WINDOWS )); then
        cygpath -am "$1"
    else
        printf '%s\n' "$1"
    fi
}

run_tool() {
    local TOOL="$1"
    shift
    if (( WINDOWS )); then
        # Git Bash dispatches batch files through CMD
        MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 "$TOOL.bat" "$@"
    else
        "$TOOL" "$@"
    fi
}

# ----------------------------------------------------------------
# prepare sources
# ----------------------------------------------------------------
mkdir -p -- "$PATH_LOG"
(
    cd -- "$TB_PATH"
    while IFS= read -r SOURCE || [[ -n "$SOURCE" ]]; do
        SOURCE=${SOURCE%$'\r'}
        SOURCE=${SOURCE#"${SOURCE%%[![:space:]]*}"}
        SOURCE=${SOURCE%"${SOURCE##*[![:space:]]}"}
        if [[ -z "$SOURCE" || "$SOURCE" == \#* ]]; then
            continue
        fi
        if [[ ! -f "$SOURCE" ]]; then
            echo "[ ERROR ] Source not found: \"$SOURCE\"." >&2
            exit 1
        fi
        ABSOLUTE_SOURCE="$(cd -- "$(dirname -- "$SOURCE")" && pwd)/$(basename -- "$SOURCE")"
        printf 'sv work "%s"\n' "$(tool_path "$ABSOLUTE_SOURCE")"
    done < "$TB_FILES"
) > "$PATH_LOG/sources.prj"

cd -- "$PATH_LOG"

echo "----------------------------------------------------------------"
echo "[1/3] Compiling HDL..."
echo "----------------------------------------------------------------"

run_tool xvlog -prj sources.prj -i "$(tool_path "$TB_PATH")" -log compile.log || {
    echo "[ ERROR ] Compilation failed. See \"$PATH_LOG/compile.log\"." >&2
    exit 1
}

echo "----------------------------------------------------------------"
echo "[2/3] Elaborating $TB_NAME..."
echo "----------------------------------------------------------------"

run_tool xelab "$TB_NAME" -s behav_tb -debug typical -log elaborate.log || {
    echo "[ ERROR ] Elaboration failed. See \"$PATH_LOG/elaborate.log\"." >&2
    exit 1
}

echo "----------------------------------------------------------------"
echo "[3/3] Running behavioral simulation..."
echo "----------------------------------------------------------------"
run_tool xsim behav_tb -runall -log simulate.log || {
    echo "[ ERROR ] Simulation failed. See \"$PATH_LOG/simulate.log\"." >&2
    exit 1
}

if (( CONFIG_GUI )); then
    run_tool xsim behav_tb -gui -onfinish stop -runall -log xsim_gui.log || {
        echo "[ ERROR ] Simulation failed. See \"$PATH_LOG/xsim_gui.log\"." >&2
        exit 1
    }
fi
