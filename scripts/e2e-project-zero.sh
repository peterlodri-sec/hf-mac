#!/usr/bin/env bash
# e2e-project-zero.sh — end-to-end check of the Project Zero lane.
#
# Builds shifulegend/project-zero, serves a model, and verifies the exact
# OpenAI-compatible surface hf.app's ProjectZeroClient speaks:
#
#   GET  /v1/models              → the loaded model id
#   POST /v1/chat/completions     (stream:false) → choices[0].message.content
#   POST /v1/chat/completions     (stream:true)  → SSE `delta.content` … `[DONE]`
#
# Usage:  bash scripts/e2e-project-zero.sh [path/to/model.gguf]
# Env:    PZ_DIR (~/project-zero) · MODEL_DIR (~/models) · PZ_PORT (8090)
#
# NOTE: the engine's GGUF loader supports F32/F16/BF16/Q8_0/Q4_K/Q4_0/Q5_*/Q6_K/
# Q2_K/Q3_K/IQ4_NL — but NOT the ternary 1.58-bit quant (type 36 / TQ1_0) that
# Falcon3-*-1.58bit ships as. Choose a supported quant for the smoke test; the
# ternary gap is documented in docs/project-zero.md.
set -euo pipefail

cd "$(dirname "$0")/.."

PZ_DIR="${PZ_DIR:-$HOME/project-zero}"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"
PORT="${PZ_PORT:-8090}"
MODEL="${1:-}"

echo "== 1/4 engine: $PZ_DIR"
if [ ! -d "$PZ_DIR/.git" ]; then
  git clone https://github.com/shifulegend/project-zero "$PZ_DIR"
fi
if [ ! -x "$PZ_DIR/adaptive_ai_engine" ]; then
  ( cd "$PZ_DIR" && make release )
fi
echo "   $("$PZ_DIR/adaptive_ai_engine" --version 2>/dev/null | head -1 || echo built)"

echo "== 2/4 model"
if [ -z "$MODEL" ]; then
  # Prefer a supported (non-ternary) GGUF for the smoke test.
  MODEL="$(find "$MODEL_DIR" -name '*.gguf' ! -iname '*1.58*' ! -iname '*i2_s*' 2>/dev/null | head -1 || true)"
fi
if [ -z "$MODEL" ]; then
  echo "!! no supported .gguf found under $MODEL_DIR — pass one explicitly." >&2
  echo "   (ternary 1.58-bit GGUFs are rejected by the loader; see docs/project-zero.md)" >&2
  exit 1
fi
echo "   $MODEL"

echo "== 3/4 serve on :$PORT"
"$PZ_DIR/adaptive_ai_engine" --model "$MODEL" --server --port "$PORT" >/tmp/pz-e2e.log 2>&1 &
ENGINE_PID=$!
trap 'kill "$ENGINE_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 60); do
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then break; fi
  if ! kill -0 "$ENGINE_PID" 2>/dev/null; then
    echo "!! engine exited during load — last log lines:" >&2
    tail -5 /tmp/pz-e2e.log >&2
    exit 1
  fi
  sleep 1
done
lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || { echo "!! :$PORT never came up" >&2; exit 1; }

echo "== 4/4 probe hf.app's client surface"
python3 - "$PORT" <<'PY'
import json, sys, urllib.request
port = sys.argv[1]; base = f"http://127.0.0.1:{port}"
ok = True

def check(label, cond):
    global ok
    print(("  OK   " if cond else "  FAIL ") + label)
    ok = ok and cond

# models()
r = urllib.request.urlopen(base + "/v1/models", timeout=30)
body = json.loads(r.read())
check("GET /v1/models → list", isinstance(body.get("data"), list) and body["data"])
model_id = body["data"][0]["id"] if body.get("data") else "local"

# chat() — non-streaming
req = urllib.request.Request(base + "/v1/chat/completions",
    data=json.dumps({"model": model_id, "messages": [{"role": "user", "content": "reply with one word: pong"}], "stream": False}).encode(),
    headers={"Content-Type": "application/json"})
r = urllib.request.urlopen(req, timeout=300)
obj = json.loads(r.read())
content = (obj.get("choices") or [{}])[0].get("message", {}).get("content", "")
check(f"POST /v1/chat/completions (stream:false) → message.content {content!r}", bool(content))

# chatStream() — SSE `delta.content` … `[DONE]`
req = urllib.request.Request(base + "/v1/chat/completions",
    data=json.dumps({"model": model_id, "messages": [{"role": "user", "content": "say hi"}], "stream": True}).encode(),
    headers={"Content-Type": "application/json"})
r = urllib.request.urlopen(req, timeout=300)
saw_delta, saw_done = False, False
for raw in r:
    line = raw.decode(errors="replace").strip()
    if line.startswith("data:"):
        payload = line[5:].strip()
        if payload == "[DONE]": saw_done = True
        else:
            try:
                if (json.loads(payload).get("choices") or [{}])[0].get("delta", {}).get("content"):
                    saw_delta = True
            except Exception:
                pass
check("POST /v1/chat/completions (stream:true) → delta.content + [DONE]", saw_delta and saw_done)

sys.exit(0 if ok else 1)
PY

echo
echo "e2e: hf.app's ProjectZeroClient surface verified against the live engine."
