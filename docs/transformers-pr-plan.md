# PR plan — quantal-ternary loader into transformers' bitnet module

**Target:** https://github.com/huggingface/transformers (PR to the bitnet module)
**Model:** `PeetPedro/quantal-ternary` (Qwen2.5-0.5B, BitNet b1.58 ternary, masked val 0.5597)

## Goal

Make `PeetPedro/quantal-ternary` run natively in PyTorch via the existing
`transformers.models.bitnet` module — no Rust runner required. The repo ships
168 ternary matrices + embeddings + norms; a loader that reconstructs the
deployed forward closes the loop between our Rust runtime and the transformers
ecosystem.

## What exists already (verified 2026-08-12)

- `transformers` has `BitNetForCausalLM` (modular, generated from
  `modular_bitnet.py`), `BitNetConfig`, RMSNorm, MLP, Attention.
- The forward uses a ternary `weight_quant` (the {-1,0,+1} path) — same
  concept as our deployed-forward `weight_quant`.
- Our repo: `m000.json..m167.json` (packed codes + scales), `embeddings.f16`,
  `norms.f32`, `index.json` (per-matrix sha256, byte counts).

## The gap

The transformers BitNet quantizes **full-precision weights at forward time**.
Our repo ships **already-quantized ternary matrices** (no full-precision
weights). Two integration points:

1. **A `from_pretrained` path for the ternary export** — load the 168
   matrices, dequantize to {-1,0,+1} (or keep packed and dequantize in
   forward), reconstruct the Qwen2.5-0.5B architecture with BitNet projections
   replaced, set embeddings/norms from the sidecars.
2. **A `PreTrainedModel.from_quantal` classmethod** (or a small
   `QuantalBitNet` wrapper) on the bitnet module — named so the HF repo loads
   with `AutoModelForCausalLM.from_pretrained("PeetPedro/quantal-ternary")`.

## Deployed-forward parity (the constraint)

Training used weight-quant-only BitLinear (per-projection RMSNorm +
activation_quant **skipped**). The PyTorch forward must match the Rust runner
**to 1e-5** — reuse the same gate: the golden-logits reference vs the PyTorch
logits, identical prompts. If the transformers BitNet applies activation_quant
or the extra RMSNorm, it will not match; the loader must use the
weight-quant-only path.

## Files to touch (draft)

- `src/transformers/models/bitnet/modeling_bitnet.py` (or the modular source):
  add `QuantalBitNetForCausalLM` (or a loader hook) reading the ternary export.
- `src/transformers/models/bitnet/configuration_bitnet.py`: add the export
  flags (packed layout, group_size, has_quantal_export).
- A `PeetPedro/quantal-ternary` config.json so `AutoModel` routes to the
  bitnet module.
- Tests: parity gate (PyTorch vs Rust golden logits, 1e-5), plus a
  from-quantal smoke test.

## Sequencing

1. The claude2 parity chain finishes (HF upload of the 0.5597 export) — the
   loader targets that repo state.
2. Draft the modular change + the loader in a fork of transformers.
3. Parity test (PyTorch vs Rust golden logits) must pass 1e-5 before the PR.
4. Open the PR against `huggingface/transformers` with the test + the model
   config.

## Notes / risks

- The transformers bitnet module is **generated** from `modular_bitnet.py` —
  edit the modular source, regenerate.
- `torch` import in the loader must be lazy or the module must be torch-free
  at import (the transformers convention).
- The 168-matrix dequant is cheap (small model) — no packed GEMM needed for
  the first PR; correctness first, speed later.

*the constellation · 0 + 1 · fine touch from within · vaked.dev*

## Update 2026-08-13 — tiszta ternary + parity-debug megállapításai

### A parity-hiba eddigi diagnózisa (a régi sign-alapú demo-n)

A `quantal_to_bitnet.py` parity-teszt FAIL: transformers argmax 91812 vs
golden 35929 (max_abs ~20). A bisectálás megállapításai:

- **q/k/v, RoPE cos/sin, mask, scaling mind pontosak** (layer-0 szinten a
  transformers és a manuális numpy/torch egyezik).
- **A `eager_attention_forward` és a manuális torch attention EGYEZIK**
  (`dbg_tf17`, `dbg_tf21`) — tehát a transformers bitnet attention helyes.
- **A `repeat_kv` == `repeat_interleave`** (`dbg_tf20`).
- A **layer-0 attn_out a teljes `model(x)` forwardban és a külső manuális
  között eltér** (`dbg_tf11` [0.130] vs `dbg_tf17` [-0.0009]) — ez a
  rejtély, valószínűleg a `model(x)` belső mask/causal kezelése és a külső
  triu mask közötti finom eltérés.

### Mit jelent ez a nightly után

- A **nightly a tiszta ternary-t** tréningeli (per-group scale, 0-állapot).
  Az új exporttel a parity-tesztet **újra kell futtatni** — a kódok
  (0/1/2) és a scales másképp néznek ki, de a dequant-formátum ugyanaz.
- A parity-hiba oka **a transformers bitnet modul és a Qwen2.5 közti
  finom forward-eltérés** — a nightly checkpointra az egész
  (export + parity) egyszerre újraértékelendő.
- A `dbg_tf21`-szerű explicit forward a folytatás kiindulópontja.

### A nightly állapota (2026-08-13)

- RTX PRO 6000 (vast 47647576), `MLX_CUDA_GRAPH_CACHE_SIZE=2000` fix.
- 40 epoch, 20,007-es korpusz, deployed-forward + tiszta ternary.
- 7. epoch: loss 0.12-0.17 (a régi 1.3-1.9-hez képest drámai javulás).
- Best a curve-ben, `ckpts-nightly/quantal-long-best.safetensors`.

## Update 2026-08-13 — A parity-hiba MEGOLDVA

A transformers-PR parity FAIL oka a **PyPI 5.15.0 `BitNetMLP`/`BitNetAttention`**:
a `use_sub_norms` flag NINCS implementálva — a `ffn_sub_norm` és az
`attn_sub_norm` **mindig** létrejön és alkalmazódik a forwardban. Ezért a
deployed-forward (sub-norm nélküli) modell eltér a transformers-től.

A `/root/src` (transformers **5.16.0.dev0**) viszont helyesen kezeli:
`BitNetRMSNorm(...) if config.use_sub_norms else None` (modeling_bitnet.py:80,
189). Ezzel a parity-teszt **PASS**: max_abs 6.5e-06, argmax 71703=71703
mindkét promptnál — szorosabb, mint a Rust parity (1.3e-5).

### Mit jelent a PR-hez

- A transformers-PR-nek a **`use_sub_norms` támogatást** kell tartalmaznia
  (a PyPI 5.15.0-ból hiányzik; a dev-branchben megvan). A PR a dev-ből
  a `BitNetMLP`/`BitNetAttention` `use_sub_norms`-kezelését hozza be.
- A parity-teszt (PyTorch vs golden, 1e-5) már működik — a `--ref` a
  golden vanilla, a `--model-dir` a demo-nightly.
- A config `use_sub_norms=False` a deployed-forwardnak felel meg.
