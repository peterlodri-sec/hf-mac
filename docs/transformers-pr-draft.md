# transformers-PR draft — BitNet `use_sub_norms=False` support

**Title:** `[bitnet] Support use_sub_norms=False (weight-quant-only BitLinear checkpoints)`

**Target:** `huggingface/transformers`, `src/transformers/models/bitnet/`

## Summary

Adds the `use_sub_norms` flag to `BitNetConfig` and honours it in
`BitNetMLP`/`BitNetAttention`. When `False`, the per-projection sub-layer
RMSNorm modules are **not created at all** (not neutralised to ones), which
is what weight-quant-only BitLinear checkpoints require.

## Why

BitNet checkpoints come in two forward variants:

1. **Full BitNet** (`use_sub_norms=True`, the default): per-projection
   RMSNorm (attn_sub_norm / ffn_sub_norm) applied before the projection
   bias and the residual. This is the `microsoft/bitnet-b1.58-2B-4T` shape.
2. **Weight-quant-only** (`use_sub_norms=False`): trained through a BitLinear
   that skips the per-projection RMSNorm and activation quant entirely —
   the weights are already ternary `{-1, 0, +1}` and the forward is a plain
   `nn.Linear`. The sub-norm modules are **absent**, not present-with-neutral
   weights: an RMSNorm initialised to ones still normalises, so it cannot be
   neutralised by `weight=ones`. The module has to not exist.

Today `BitNetMLP.forward` always runs `self.ffn_sub_norm(...)` and
`BitNetAttention.forward` always runs `self.attn_sub_norm(...)`, and the
modules are unconditionally constructed in `__init__`. A weight-quant-only
checkpoint therefore loads with the sub-norms applied, producing logits that
differ from the trained/deployed forward by ~10 in max-abs and flip the
argmax.

## The fix

```python
# configuration_bitnet.py
use_sub_norms: bool = True

# modular_bitnet.py (BitNetMLP)
self.ffn_sub_norm = (
    BitNetRMSNorm(config.intermediate_size, eps=config.rms_norm_eps)
    if config.use_sub_norms else None
)
# forward: apply only when present

# modular_bitnet.py (BitNetAttention)
self.attn_sub_norm = (
    BitNetRMSNorm(config.hidden_size, eps=config.rms_norm_eps)
    if config.use_sub_norms else None
)
# forward: apply only when present
```

Backward compatible: the default stays `True`, so existing `bitnet` model
cards (which don't set `use_sub_norms`) are unchanged.

## Verification

A continued-trained Qwen2.5-0.5B weight-quant-only BitNet (ternary export,
`PeetPedro/quantal-ternary`) was loaded into `BitNetForCausalLM` with
`use_sub_norms=False` and compared against a golden reference (the deployed
forward the Rust runner reproduces to 1e-5):

```
prompt 1: max_abs 6.497e-06  argmax 71703 = 71703  PASS
prompt 2: max_abs 6.676e-06  argmax 71703 = 71703  PASS
```

Before the fix (sub-norms forced on): max_abs ~10-20, argmax off. The two
variants differ by ~10 in max-abs — a real, reproducible signal, not noise.

## Files

- `src/transformers/models/bitnet/configuration_bitnet.py` — add
  `use_sub_norms: bool = True`.
- `src/transformers/models/bitnet/modular_bitnet.py` — conditional sub-norm
  construction + conditional application (the modular source).
- `src/transformers/models/bitnet/modeling_bitnet.py` — generated mirror of
  the modular change (via `make fix-repo`).

## Notes

- `modeling_bitnet.py` is generated from `modular_bitnet.py`; the modular
  file is the source of truth (`make fix-repo` propagates).
- The `use_sub_norms` docstring lives on the `BitNetConfig` field; the
  `@strict` dataclass requires it documented to pass `make check-repo`.
- Test: add a `use_sub_norms=False` smoke test that constructs
  `BitNetForCausalLM`, asserts `model.model.layers[0].mlp.ffn_sub_norm is
  None`, and forward-runs on a few tokens.

*the constellation · 0 + 1 · fine touch from within · vaked.dev*
