# ultra-brainstorm — the ternary loader gap (ggml type 36)

*Why the Project Zero lane can't load the very model it is named for, measured
against `tiiuae/Falcon3-3B-Instruct-1.58bit-gguf` (`ggml-model-i2_s.gguf`),
2,221,465,632 bytes.*

---

## 0 · the symptom

```
[gguf_loader] unsupported quant type 36 ('UNKNOWN') for tensor 'blk.0.attn_q.weight'
[gguf_loader] Supported: F32, F16, BF16, Q8_0, Q4_K, Q4_0, Q5_0, Q5_1, Q5_K, Q6_K, Q2_K, Q3_K, IQ4_NL
Failed to load GGUF weights.
```

154 of 201 tensors are type 36. The engine's loader has no such type.

## 1 · what type 36 *is*

Mainline ggml's enum:

```
GGML_TYPE_TQ1_0 = 34      // ternary 1.58-bit, 9 trits / 2 bytes-ish
GGML_TYPE_TQ2_0 = 35      // ternary, 2-bit trits
// GGML_TYPE_IQ4_NL_4_4 = 36   ← REMOVED from gguf files
GGML_TYPE_MXFP4 = 39
```

So **36 is not a mainline ggml type any more**. It is a **fork convention** —
Microsoft's `BitNet.cpp` / T-MAC line assigns the ternary packing an id the
mainline removed. That is why Project Zero (which implements the *mainline*
supported set) rejects it, and it is why mainline `llama.cpp` cannot load this
file either.

## 2 · what the payload actually is (measured, not guessed)

Parsing the GGUF header and walking the tensor offsets gives the layout exactly:

| tensor class | type | bytes/elem |
|---|---|---|
| `token_embd.weight`, `output.weight` | F16 (1) | 2.0 |
| `blk.*.*norm.weight` (45 of them) | F32 (0) | 4.0 |
| `blk.*.{attn_q,k,v,output,ffn_up,gate,down}.weight` (154) | **36** | **0.250002** |

`0.25 B/elem` — and the offsets are **contiguous and exact**
(`blk.0.ffn_up.off = blk.0.ffn_gate.off + numel/4`). So:

- **2 bits per weight, 4 weights per byte.**
- **No per-block scale, no per-row scale, no `*.scale` tensor** — the F32
  tensors are *only* the 45 norms, and the KV block (24 keys) carries nothing
  scale-like.
- `general.file_type = 40`, `general.quantization_version = 2`.

Histogramming the packed 2-bit codes of a real tensor:

```
blk.0.attn_q.weight : code 0: 21.0%   code 1: 58.0%   code 2: 21.1%   code 3: 0.0%
blk.5.ffn_gate.weight: code 0: 35.3%  code 1: 29.6%   code 2: 35.2%   code 3: 0.0%
```

**Code 3 never appears.** It is a 3-state ternary packing —
`{0,1,2} = {-1, 0, +1}`, LSB first, code 3 reserved. (The 58%-zero row is the
same shape as the operator's earlier finding, *"the third state restored:
34.25 % want zero"*.)

## 3 · the twist — the engine already knows this packing

Project Zero's own native `.bin` format is documented as:

> *4 ternary weights per byte (`-1→0b00, 0→0b01, 1→0b10`, LSB first), one float
> scale after each packed matrix.*

That is **the same packing** this GGUF uses. So the unpack path is not new
math — it is the engine's *existing* ternary unpack, just reached through the
**GGUF** loader instead of the native path. The gap is not the bit-twiddling;
it is that (a) the loader doesn't recognise the type, and (b) **this file
carries no scale**.

## 4 · the crux — the missing scale

Every working ternary path in the constellation agrees on the law:

> **weights stay ternary the whole way, the scale lands once, at the end.**

For most ternary checkpoints, that one scale is a **per-tensor absmean**
(`scale = mean(|W|)`), stored as a side tensor (`blk.*.scale`). This file has
**none** — no `.scale` tensor, no KV. Three possibilities:

1. **The file is scale-less by construction** and the runtime applies a scale
   from the original checkpoint's config (a `scale` per module in `config.json`).
2. **A single global scale** (near 1) is assumed — wrong for BitNet, whose
   per-tensor scales vary.
3. tiiuae's conversion **dropped** the scale tensors, making the GGUF
   *incomplete for correct inference* — which would itself be the upstream bug
   to file.

We can decide this cheaply and in the open: compare a token stream against the
reference (BitNet.cpp / the HF `transformers` checkpoint) at scale ∈ {sidecar,
global, per-tensor-absmean}. Whichever reproduces the golden tokens is the
convention.

## 5 · the fix — four small moves

Mirror the shape the engine already uses for `IQ4_NL`/`Q2_K`:

1. **`gguf_reader.c`** — add type 36 to the size/name table:
   `GGUF_TYPE_TERNARY_I2S` → `bytes = numel / 4`, name `"I2_S"`. (Zeroing the
   "UNKNOWN".)
2. **`gguf_quant.c`** — a `dequantize_i2_s`: 4 codes/byte → `{-1,0,+1}`
   (code 3 → 0, or reject), **reusing the engine's native unpack**, then apply
   the one scale. Ideally skip dequant entirely and add a `i2_s` matmul that
   accumulates in `i32` and applies the scale once — matching the lane's law
   and the engine's own Q4_K discipline.
3. **scale resolution** — resolve the per-tensor scale (sidecar → global →
   absent/error). Never silently assume 1.0: a wrong scale is fluent garbage,
   the worst failure mode.
4. **`gguf_loader.c`** — accept type 36 for `*.weight` linear tensors only;
   norms/embeddings stay F32/F16.

## 6 · verification (borrowed from the ternary lane)

- **golden hash** — fixed prompt → first-32-logit hash asserted in `make test`
  (the discipline the engine's MoE work and the ternary lane already keep).
- **France→Paris / Germany→Berlin** — the engine's existing coherence probe.
- **A/B** — this GGUF's tok/s vs the dense SmolLM2 Q4_K path the E2E already
  measures (3.2 tok/s ceiling on this M1).

## 7 · the one-sentence ask

> *Project Zero's GGUF loader rejects the ternary 1.58-bit packing (a
> fork-specific type id, 2 bits/weight, 4 trits/byte, no stored scale) — so the
> engine can't load the very `{-1,0,+1}` models it is built for. Add an `I2_S`
> type: a `numel/4` size, the existing ternary unpack, and an explicit
> per-tensor scale resolution.*

---

*fine touch from within · the third state is real · 0 + 1*
