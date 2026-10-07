#!/usr/bin/env bash
# setup-project-zero.sh — build shifulegend/project-zero locally and fetch a
# 1.58-bit model, so hf.app can talk to a local CPU ternary engine.
#
# Project Zero is a dependency-free C99 inference engine (GGUF, mmap'd ternary
# weights, AVX-512/NEON). Its release tarballs are x86_64-linux, so on Apple
# Silicon (and any host) we build from source — Clang + make, NEON supported.
#
# Usage:  bash scripts/setup-project-zero.sh
# Then:   adaptive_ai_engine --model "$GGUF" --server --port 8090
#         (hf.app → Run → "Project Zero (CPU)")
set -euo pipefail

PZ_DIR="${PZ_DIR:-$HOME/project-zero}"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"
# default per the ternary lane (Falcon3-3B-Instruct-1.58bit); the engine's
# flagship demo is microsoft/bitnet-b1.58-2B-4T.
MODEL_REPO="${MODEL_REPO:-tiiuae/Falcon3-3B-Instruct-1.58bit-gguf}"
PZ_PORT="${PZ_PORT:-8090}"     # 8080 is taken on this Mac (litellm caddy)

echo "== 1/3 engine: $PZ_DIR"
if [ ! -d "$PZ_DIR/.git" ]; then
  git clone https://github.com/shifulegend/project-zero "$PZ_DIR"
fi
cd "$PZ_DIR"
git pull --ff-only || true

echo "== 2/3 build (make release)"
make release

echo "== 3/3 model: $MODEL_REPO"
mkdir -p "$MODEL_DIR"
if command -v hf >/dev/null 2>&1; then
  hf download "$MODEL_REPO" --local-dir "$MODEL_DIR"
elif command -v huggingface-cli >/dev/null 2>&1; then
  huggingface-cli download "$MODEL_REPO" --local-dir "$MODEL_DIR"
else
  echo "!! no Hugging Face client found — install one (pip install -U huggingface_hub)" >&2
  echo "   and re-run, or drop a .gguf into $MODEL_DIR manually." >&2
  exit 1
fi

GGUF="$(find "$MODEL_DIR" -name '*.gguf' | head -n1 || true)"
if [ -z "$GGUF" ]; then
  echo "!! no .gguf found under $MODEL_DIR" >&2
  exit 1
fi

echo
echo "engine: $PZ_DIR/adaptive_ai_engine"
echo "model:  $GGUF"
echo
echo "start the engine:"
echo "  $PZ_DIR/adaptive_ai_engine --model \"$GGUF\" --server --port $PZ_PORT"
echo
echo "then open hf.app → Run → select \"Project Zero (CPU)\"."
