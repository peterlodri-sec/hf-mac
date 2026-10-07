# Project Zero — the local CPU ternary lane

`hf.app` normally talks to **Osaurus** (MLX, on-device GPU) for local inference
and to **coder.vaked.dev** for the free remote tier. **Project Zero** is the
third backend: a dependency-free **C99** ternary inference engine that runs on
the **CPU** — the same `{ -1, 0, +1 }` arithmetic as ayeOS and MLX-QUANT, in a
single binary with no Python and no CUDA.

- **upstream**: [`shifulegend/project-zero`](https://github.com/shifulegend/project-zero)
  — GGUF + native `.bin`, mmap'd weights, 4 ternary weights per byte,
  `-1→0b00 / 0→0b01 / 1→0b10`, one float scale after each packed matrix.
- **the law it shares with the 8b-is stack** — *weights stay ternary/quantized
  the whole way, the scale lands once, at the end* — the same contract as the
  ternary lane and MLX-QUANT. See `8b-is-engine/docs/project-zero-bridge.md`
  for the memory-side story (expert scatter, the native Q4_K matmul, the golden
  hash).

## what hf.app adds

| piece | where |
|---|---|
| `ProjectZeroClient` — OpenAI-compatible client (models · chat · stream) | `Sources/HFMac/Services.swift` |
| `InferenceSource.projectZero` — a third backend in the Run tab | `Sources/HFMac/HFMacApp.swift` |
| engine discovery + a friendly hint when it's not running | `ProjectZeroClient.engineBinary(in:)` + `AppState.refreshProjectZero()` |
| build + model helper | [`scripts/setup-project-zero.sh`](../scripts/setup-project-zero.sh) |

## run it

```bash
# 1 · build the engine and fetch a 1.58-bit GGUF (Falcon3-3B-Instruct-1.58bit)
bash scripts/setup-project-zero.sh

# 2 · start the engine (default port 8090 — 8080 is taken by litellm on this Mac)
~/project-zero/adaptive_ai_engine --model ~/models/*.gguf --server --port 8090

# 3 · open hf.app → Run → select "Project Zero (CPU)"
```

The engine speaks OpenAI's `/v1` shape, so hf.app reuses the same streaming
path as Osaurus and coder.vaked.dev. If the engine is not built, the Run tab
tells you exactly which script to run.

## port

`8090` (`projectZeroDefaultPort`). `8080` is reserved on this Mac by the
litellm caddy, so the engine is seated one port up.

---

*fine touch from within · the C citizen of the ternary lane · 0 + 1*
