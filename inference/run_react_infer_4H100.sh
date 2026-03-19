#!/bin/bash

# =============================================================================
# DeepResearch Inference Script for 4x H100 GPUs (Tensor Parallel)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

# Load environment variables
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please copy .env.example to .env and configure your settings"
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

# Compiler settings for Triton
export CC=/home/langgenius/miniconda3/bin/gcc
export CXX=/home/langgenius/miniconda3/bin/g++

# =============================================================================
# 1. Check if vLLM is already running
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

    VLLM_PID=$!
    echo "vLLM started with PID: $VLLM_PID"

    # Wait for server to be ready
    echo "Waiting for vLLM server to start..."
    timeout=600
    start_time=$(date +%s)

    while true; do
        if curl -s http://localhost:${VLLM_PORT}/health > /dev/null 2>&1; then
            echo "vLLM server is ready!"
            break
        fi

        current_time=$(date +%s)
        elapsed=$((current_time - start_time))

        if [ $elapsed -gt $timeout ]; then
            echo "Error: vLLM server startup timeout"
            echo "Check logs: tail -f /tmp/vllm_4h100.log"
            exit 1
        fi

        printf "."
        sleep 10
    done
fi

# =============================================================================
# 2. Run Inference
# =============================================================================
echo ""
echo "==== Starting Inference ===="
echo "Model: $MODEL_PATH"
echo "Dataset: $DATASET"
echo "Output: $OUTPUT_PATH"
echo "Max Workers: ${MAX_WORKERS:-10}"
echo "Rollout Count: ${ROLLOUT_COUNT:-3}"
echo ""

cd "$SCRIPT_DIR"

python -u run_multi_react.py \
    --dataset "${DATASET:-bamboogle}" \
    --output "${OUTPUT_PATH:-/data/langgenius/DeepResearch/output}" \
    --max_workers ${MAX_WORKERS:-10} \
    --model "$MODEL_PATH" \
    --temperature ${TEMPERATURE:-0.85} \
    --presence_penalty ${PRESENCE_PENALTY:-1.1} \
    --roll_out_count ${ROLLOUT_COUNT:-3}

echo "==== Inference Complete ===="
