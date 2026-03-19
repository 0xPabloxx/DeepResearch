#!/bin/bash

# =============================================================================
# DeepResearch Inference Debug Script for 4x H100 GPUs
# Supports VS Code debugger attachment via debugpy
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Debug configuration
DEBUG_PORT=${DEBUG_PORT:-5678}
DEBUG_MODE=${DEBUG_MODE:-vscode}  # vscode, pdb, or none

# Load environment variables
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

echo "Loading environment variables from .env..."
set -a
source "$ENV_FILE"
set +a

# =============================================================================
# Configuration
# =============================================================================
MODEL_PATH="${MODEL_PATH:-Alibaba-NLP/Tongyi-DeepResearch-30B-A3B}"
VLLM_PORT=8000
TENSOR_PARALLEL_SIZE=4

export CC=/home/langgenius/miniconda3/bin/gcc
export CXX=/home/langgenius/miniconda3/bin/g++

# =============================================================================
# Check/Start vLLM
# =============================================================================
echo "Checking vLLM server status..."

if curl -s http://localhost:${VLLM_PORT}/health > /dev/null 2>&1; then
    echo "vLLM server is already running on port ${VLLM_PORT}"
else
    echo "Starting vLLM server with ${TENSOR_PARALLEL_SIZE} GPUs..."
    nohup vllm serve "$MODEL_PATH" \
        --host 0.0.0.0 \
        --port ${VLLM_PORT} \
        --tensor-parallel-size ${TENSOR_PARALLEL_SIZE} \
        --disable-log-requests \
        > /tmp/vllm_4h100.log 2>&1 &

    echo "Waiting for vLLM server..."
    timeout=600
    start_time=$(date +%s)
    while true; do
        if curl -s http://localhost:${VLLM_PORT}/health > /dev/null 2>&1; then
            echo "vLLM server is ready!"
            break
        fi
        elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -gt $timeout ]; then
            echo "Error: vLLM startup timeout"
            exit 1
        fi
        printf "."
        sleep 10
    done
fi

# =============================================================================
# Run Inference with Debugger
# =============================================================================
echo ""
echo "==== Starting Debug Inference ===="
echo "Debug Mode: $DEBUG_MODE"
echo "Debug Port: $DEBUG_PORT (for VS Code)"
echo "Model: $MODEL_PATH"
echo "Dataset: $DATASET"
echo ""

cd "$SCRIPT_DIR"

# Ensure debugpy is installed
if [ "$DEBUG_MODE" = "vscode" ]; then
    pip show debugpy > /dev/null 2>&1 || pip install debugpy
fi

COMMON_ARGS="run_multi_react.py \
    --dataset ${DATASET:-bamboogle} \
    --output ${OUTPUT_PATH:-/data/langgenius/DeepResearch/output} \
    --max_workers 1 \
    --model $MODEL_PATH \
    --temperature ${TEMPERATURE:-0.85} \
    --presence_penalty ${PRESENCE_PENALTY:-1.1} \
    --roll_out_count 1"

case "$DEBUG_MODE" in
    vscode)
        echo "============================================="
        echo "Waiting for VS Code debugger to attach..."
        echo "Configure VS Code launch.json:"
        echo '{'
        echo '  "name": "Python: Remote Attach",'
        echo '  "type": "debugpy",'
        echo '  "request": "attach",'
        echo '  "connect": {'
        echo "    \"host\": \"localhost\","
        echo "    \"port\": $DEBUG_PORT"
        echo '  },'
        echo '  "pathMappings": [{'
        echo '    "localRoot": "${workspaceFolder}",'
        echo '    "remoteRoot": "/data/langgenius/DeepResearch"'
        echo '  }]'
        echo '}'
        echo "============================================="
        python -m debugpy --listen 0.0.0.0:${DEBUG_PORT} --wait-for-client $COMMON_ARGS
        ;;
    pdb)
        echo "Starting with pdb (command-line debugger)..."
        echo "Commands: n=next, s=step, c=continue, b=breakpoint, q=quit"
        python -m pdb $COMMON_ARGS
        ;;
    *)
        echo "Running without debugger (DEBUG_MODE=none)..."
        python -u $COMMON_ARGS
        ;;
esac

echo "==== Debug Session Complete ===="
