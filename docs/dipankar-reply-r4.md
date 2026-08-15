# Reply draft — Dipankar Sarkar, round 4 v4 (the zero state is now real)

**Where:** HF post (round 3 → "does this model ever want a zero?")

---

Your zero question was the right question, and it changed the quantizer.

**The model does want zeros — about a third of it.** Sweeping a real ternary
threshold over the trained SOTA checkpoint:

```
sign-based (old):  mae 0.01005   zero 0.00%
ternary t=0.5:     mae 0.00753   zero 31.8%
ternary t=1.0:     mae 0.00961   zero 58.5%
```

On the first layer's 21M weights, **34.25% sit below 0.5·scale** — they want
the zero state. The old `weight_quant` (`sign(w−mean)·mean|w|`) had no zero
path at all; a value was +scale or −scale unless it landed exactly on the
mean (your 12). The third code was a slot the format paid for and the
quantizer never used.

**So I rebuilt the quantizer as a true thresholded ternary**, per 64-column
group (matching the ayeOS scale layout the Rust runner dequantizes):

```python
scale_g = mean(|w|) over the group
q = 0            if |w| < 0.5·scale_g
    sign(w)·scale_g  otherwise
```

Training forward ≡ export ≡ Rust by construction — the export now computes
the same per-group scale and the same zero band, and the Rust runner's
`(code−1)·scale` decodes it exactly.

**Your two format findings are both resolved by the same change:**

- The scales are no longer "a scalar wearing a shape". The old export had 2
  distinct scales in 68,096 (both multiples of 1/65536) because `sign`-based
  collapse made every group's mean|w| nearly equal. The thresholded export
  has **62,120 distinct scales** over 0.0086..0.046 — real per-group data.
- The codes are no longer a sign matrix. Zero fraction is now **~30%** (was
  2.75e-6), and the zero state appears where a weight genuinely sits below
  the band, not as a rounding accident.

**New nightly run (this replaced the old corpus):** 20,007 samples,
Qwen2.5-0.5B, deployed-forward, thresholded ternary. Best masked val
**2.1469** (epoch 2, early stop — the run overfits after epoch 2, val
2.38 → 2.15 → 2.25 → 2.49 → 2.72 → 2.76 → 3.07). Parity gate on the fresh
export: **max_abs 1.335e-5, max_rel 1.323e-5, argmax 71703 = 71703** on both
gate prompts — tighter than any previous run (was 9.6e-5).

**Published to HF in your manifest order:** 168 matrices, then embeddings /
norms / tokenizer, then the card, then `index.json` with
`export_complete: true` **last**. The checkpoint sha in the card and in
`index.json` now agree with the blob: `21294c68…8285`, val 2.1469, 7 epochs.
The blob, the card, and the matrices finally describe the same tensor.

The four-line reply to your zero question was: yes, a third of it, and the
format now gets paid.

---

One honest caveat: the transformers bitnet loader (the PyTorch path) does not
yet reproduce the deployed forward — the parity debug is still open there
(delta ~10, argmax off). The Rust runner and the MLX reference agree to
1.3e-5; the transformers port is the remaining gap, and it is a transformers-
side issue, not a checkpoint one. Working it now.
