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

## e2e — verified against the live engine

`scripts/e2e-project-zero.sh` builds the engine, serves a model, and checks the
**exact** surface `ProjectZeroClient` speaks. Run against engine `eb46557` with
`SmolLM2-1.7B-Instruct-Q4_K_M.gguf`:

```
OK   GET  /v1/models                              → {object:list, data:[{id:local-adaptive-engine}]}
OK   POST /v1/chat/completions (stream:false)     → choices[0].message.content
OK   POST /v1/chat/completions (stream:true)      → SSE choices[0].delta.content … [DONE]
```

So `models()`, `chat()`, and `chatStream()` are bit-shaped correctly for the
real engine — not just the mock.

## the ternary gap — the model it *should* run, it can't (yet)

The engine's GGUF loader supports `F32 · F16 · BF16 · Q8_0 · Q4_K · Q4_0 · Q5_0
· Q5_1 · Q5_K · Q6_K · Q2_K · Q3_K · IQ4_NL` — but **not the ternary 1.58-bit
quant** (ggml type 36) that `tiiuae/Falcon3-*-1.58bit` ships. Loading it fails:

```
[gguf_loader] unsupported quant type 36 ('UNKNOWN') for tensor 'blk.0.attn_q.weight'
Failed to load GGUF weights.
```

This is the lane's own headline: Project Zero is *"the same `{-1,0,+1}`
arithmetic ambition in a dependency-free C binary"*, yet the deployed ternary
GGUF format isn't in its loader. The supported path today is a dense quant
(SmolLM2 Q4_K here, or BitNet's native `.bin`); the ternary GGUF is the open
gap — a loader/dequant addition upstream (parallel to the MoE repack work in
`docs/architecture/MOE_RESEARCH_AND_FIX_PLAN.md` and [PR #39](https://github.com/shifulegend/project-zero/pull/39)).

**The full analysis — measured against the actual file — is in
[`project-zero-ternary-loader.md`](project-zero-ternary-loader.md):** type 36 is
4 trits/byte (codes `{0,1,2}={-1,0,+1}`, LSB first) with **no stored scale**, and
the unpack is *the engine's own native packing* — so the fix is small, but the
scale convention is the crux.

---

*fine touch from within · the C citizen of the ternary lane · 0 + 1*
