# Dipankar r8 — fixed-point verification + the CE-only vs KL level-rule question

## 1. Verification — all four rows reproduced exactly

I ran the fixed-point claim, exactly your loop, on the 2d54a10f blob:

**Measurement environment** (per your definition):
- blob: `2d54a10f` — `PeetPedro/quantal-ternary` `quantal_model.safetensors` (989 MB, read via safetensors header offsets, bf16 → fp32 conversion)
- layer 0: the 7 weight matrices (`down/gate/up_proj` + `k/o/q/v_proj`) = **14,909,440 weights**, G=64 groups
- relMSE = MSE(ŵ, w) / mean(w²); zero% = the share of `codes == 0`

| rule | relMSE | zero% | vs shipped |
|---|---|---|---|
| shipped `s = mean\|w\|` | **0.267649** | **29.53** | +0.00% |
| A: level moves, band pinned to 0.5·s_init | **0.219453** | **29.53** | −18.01% |
| B: one pass, band moves with level | **0.206389** | **38.28** | −22.89% |
| C: iterated to the fixed point | **0.195194** | **42.43** | −27.07% |

**Convergence** (20 iterations, `a = abs_w[abs_w >= 0.5*a].mean()`):

| iter | relMSE | zero% |
|---|---|---|
| 1 (= B) | 0.206389 | 38.28 |
| 11 | 0.195222 | 42.43 |
| 12 | 0.195209 | 42.43 |
| 20 | 0.195194 | 42.43 |

Every value matches yours to 6 decimal places — no divergence in any row. Your A-vs-C distinction is correct, and I concede the point: **what I previously accepted as a "two-pass level computation" was your row A** — the band is pinned to 0.5·s_init, the level moves once, the zero fraction does not move (stays at 29.53%). The real win is row C, the fixed point.

## 2. The shipped rule in code (the deployed forward)

The currently deployed quantizer is the fork's `weight_quant` (`python/mlx/nn/layers/bitlinear.py:37-69`):

```python
scale_g = mx.abs(wr).mean(axis=-1, keepdims=True)                 # per G=64 group
q = mx.where(mx.abs(wr) < threshold * scale_g, 0.0, mx.sign(wr) * scale_g)  # threshold=0.5
```

This is exactly the **shipped row**: `s = mean|w|`, one pass, band = 0.5·s. Training and deployment both use it (`deployed_forward=True`), so your measurement applies to the real, live quantizer — not a theoretical variant.

## 3. Answer to the CE-only vs KL question

**Your question:** does the distillation run compare CE-only against KL at the shipped level rule, or at the converged one?

**Answer: both arms run on the shipped rule.** Both `train_quantal_distill.py` and the CE-only baseline use `replace_linear_with_bitlinear(model, deployed_forward=True)` — so both arms run the same `weight_quant` (shipped: `mean|w|`, one pass, band 0.5·scale) during training and when the val loss is measured. The 2.1369 (KL) vs 2.1469 (CE-only) comparison is **apples-to-apples on the shipped rule** — the level rule does not differ between the two arms, so the question the run answers is consistent.

**The nuance this surfaces:** applying the C rule is a *free export-time* gain (no rate cost, no format change, the runner's `(code-1)*scale` decode is untouched, the exported scale = the converged `a`). But if we adopt C:

1. **Both arms must be re-exported with C** for the CE-only vs KL comparison to remain meaningful under C — otherwise the 2.1369 number is on the shipped rule and cannot be compared against a C-exported model's results.
2. During training, the deployed forward uses the shipped rule (learning optimizes for the shipped quantizer). Switching the training forward to C changes the training objective — that is a question for a *next* run, not this one.
3. **Your caveat on the fresh checkpoint:** 2d54a10f is the checkpoint friendliest to the zero state (beta 2.33). The v2 run's latents (beta 2.33 → 2.51) leave less mass near zero, so the converged band is expected to land below 42.4% — the direction of the fix does not change, its size does. **This must be re-measured on the fresh best ckpt (2.1369)**, not on 2d54a10f.

## 4. Accepted decisions and next steps

- **Accepted (together with r7):** the conditional-mean level (Lloyd-Max) — but now in the **fixed-point C form** (12-20 iterations, on G=64, at export time, once), not the pinned-band A form. The zero state's place remains in the entropy coder.
- **Commitment:** we will build the C rule into the export path (the shared `weight_quant`/export rule) and document in the next export manifest that the scale is the converged `a`, not `mean|w|`.
- **Re-measurement:** we will run the C rule's effect on the fresh 2.1369 ckpt as well (replacing the −27.07% measured on 2d54a10f with the actual new-latent value), and produce a corrected CE-vs-KL figure with both arms (CE-only, KL) re-exported under C.

---

*Verification script: `verify_fixedpoint2.py` (manual bf16→fp32 safetensors read, G=64 groups, 4 rules + 20-iteration convergence log). Blob: `PeetPedro/quantal-ternary` `quantal_model.safetensors`, blob `2d54a10f`.*
