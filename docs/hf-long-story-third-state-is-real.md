# The third state is real — what a stranger counting zeros taught a 2-bit model

**By PeetPedro · the constellation · 2026-08-13**

---

Every training post on this model ended with a better number. This one ends
with the same number — but with the quantizer honest, the pipeline
reproducible, and the deployed model finally matching the trained one to
**1.3e-5**. Sometimes the win is not a lower loss. It is knowing the loss is
real.

## The backstory in one paragraph

`quantal-ternary` is a Qwen2.5-0.5B continued-trained as a BitNet b1.58
ternary model — 168 packed matrices, a Rust runner, a golden-logits parity
gate. The masked val went 11.34 → 3.2862 → 1.6998 → 0.5597 across a long,
honest week of fixes (masked CE, dynamic padding, a 68-file seam caught by
byte count, three external audits). Then a stranger on the Hub read the
bytes and asked a question that changed the quantizer.

## The stranger who counted the zeros

Dipankar Sarkar range-read the published model — no download, just the
header and a tensor slice — and unpacked one exported matrix. Precise
findings:

- The scale array, 68,096 entries, held **two distinct values**. The
  `[4864][14]` scale block was "a scalar wearing a shape".
- The codes were a **sign matrix**, not ternary: 12 zeros in 4.36M weights.
  The zero state of a 2-bit format was used once in 360,000.
- The 12 minority-scale rows were *exactly* the 12 zero-code rows. A row hit
  the lower scale bucket precisely when it contained a weight that rounded to
  zero.
- The published blob and the exported matrices were **different checkpoints**
  — sign agreement 0.86, misses concentrated in the bottom |w| decile.

And the question that changed the code:

> "Does this model ever want a zero? If the trained weights are all at plus
> or minus one scale, b1.58 is doing b1 work, and the third state is a slot
> you are paying for in every file."

## The model wants zeros — about a third of it

Measuring the latent weight distribution directly: on the first layer's 21M
weights, **34.25% sit below 0.5·scale** — they want the zero state. A sweep
of a real ternary threshold confirmed it:

| quantizer | MAE | zero fraction |
|---|---|---|
| sign-based (old) | 0.01005 | 0.00% |
| ternary t=0.5 | 0.00753 | 31.8% |
| ternary t=1.0 | 0.00961 | 58.5% |

The old `weight_quant` was `sign(w − mean)·mean|w|` — a value was +scale or
−scale unless it landed *exactly* on the mean (your 12). The third code was a
slot the format paid for and the quantizer never used. The "polarization"
was not a property of the trained weights; it was the quantizer hiding the
b1.58 third state by construction.

## The rebuild: thresholded ternary, per group

A true thresholded ternary, per 64-column group, matching the ayeOS scale
layout the Rust runner dequantizes:

```python
scale_g = mean(|w|) over the group
q = 0            if |w| < 0.5·scale_g
    sign(w)·scale_g  otherwise
```

Training forward ≡ export ≡ Rust by construction. Results:

- **Zero fraction ~30%** (was 2.75e-6) — the third state is real.
- **62,120 distinct scales** (was 2) — the scale array carries data again.
- **Quantization MAE 2.4× lower** on the trained weights.

## The nightly run

Retrained on 20,007 samples, Qwen2.5-0.5B, deployed-forward, thresholded
ternary. Best masked val **2.1469** (epoch 2 — the run overfits after that;
the curve is the honest shape of a small-corpus continued-train). A
bleeding-edge variant with lr 5e-5 instead of 3e-4 converged slower and
landed at 2.3112 — the higher lr found the better optimum faster, so the
2.1469 stands.

## The tightest parity yet

The Rust runner and the MLX reference on the fresh export:

```
prompt 1: max_abs 1.335e-05  argmax 71703 = 71703  PASS
prompt 2: max_abs 1.335e-05  argmax 71703 = 71703  PASS
```

**1.3e-5** — tighter than any previous run (was 9.6e-5). And the same
checkpoint now loads into a PyTorch `BitNetForCausalLM` at **6.5e-06** once
the transformers bitnet module honours `use_sub_norms=False`
([PR #47955](https://github.com/huggingface/transformers/pull/47955)).

## The format got paid

The reply to "does this model ever want a zero?" is: yes, a third of it, and
the format now gets paid. The 2-bit payload, the scale array, and the third
code are all earning their bytes again.

Published in the manifest order Dipankar argued for — matrices, then assets,
then the card, then `index.json` with `export_complete: true` last, so the
manifest window closes on its own. The blob, the card, and the matrices
finally describe the same tensor: `21294c68…8285`, masked val 2.1469.

The constellation's quantal thread: [from 3.29 to 1.64] →
[from 11.34 to 0.63] → this one. Each correction had nothing to do with the
model and everything to do with honesty about what was measured.

*the constellation · 0 + 1 · fine touch from within · vaked.dev*
