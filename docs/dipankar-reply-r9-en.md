# Dipankar r9 — codes-only re-measurement, estimator, and the arm-provenance question

## 1. The -0.51 point is confirmed, and your layer-sensitivity point is the stronger one

You read the shipped zero fraction of the fresh export directly from the m*.json
codes (`(code-1)*scale`, code == 1 = zero) — 21294c68, val 2.1469, 168 matrices.
Layer 0 (m161-m167) matches my 14,909,440 weights exactly:

| checkpoint | shipped zero% |
|---|---|
| 2d54a10f (old blob) | 29.5292 |
| 21294c68 (fresh) | 29.0176 |

**-0.51 points.** My caveat was right in direction (the v2 latents do leave less
mass in the band) and wrong in size — it is half a point, not a fraction of the
27-point gap. And your depth-spread check is the more important correction:
1.8 points across depth inside one checkpoint (28.77% / 30.55% / 29.68%)
vs 0.51 points between checkpoints. The layer you measure moves the number
more than the checkpoint change does. Noted for every future measurement.

## 2. The k-estimator holds — the -27.07% is not in danger

You reproduced my four-row table independently from 30 MB of range-reads, six
decimals matching. Then you fit `E[zero_C | k]` on the old blob's 232,960
groups and applied it to the fresh export's k-histogram, with an honest
half/half holdout:

- holdout: predicted 42.4316, actual 42.4104
- fresh export: **predicted 41.8** (vs 42.4 measured on the old blob)
- additive check (moving converged by the same -0.51 the shipped moved): 41.9

Two estimators built differently, 0.1 apart. Accepted: **the C rule's
relMSE improvement (-27.07% on the old blob) survives on the fresh
checkpoint**, and the re-export decision does not need to wait for the number.
The stated assumption (within-group shape of |w| at fixed k is stable across
checkpoints) is the honest boundary of that estimate — exactly what beta
2.33 → 2.51 could move — and we will verify it on the new latents when the
current run exports.

## 3. The strict bound is accepted as a proof

For a group of 64 with k non-zeros:

```
0.5·s·(64 + k)/k  <  a1  ≤  64·s/k
```

Lower bound exceeds s whenever k < 64 — which holds for all 232,960 groups on
the fresh export. On the old blob, true a1/s sits inside the interval at the
0.518 position (sd 0.069). So the level strictly rises on the first pass, the
band strictly widens, and **the converged zero fraction is strictly above the
shipped one for any checkpoint, without measuring it**. The zero state can
only gain mass under C, never lose it. This is a stronger statement than a
measurement — accepted as a theorem.

## 4. The published arm is not the winning arm — acknowledged, and the fix is in motion

You are right, and this is a real provenance problem: the Hub export (21294c68)
is the CE-only baseline (2.1469), while the KL arm (2.1369) — the winner — is
not on the Hub in any form. Everything above is measured on the losing arm,
which is fine for the C question (export-time transform, arm-agnostic) but not
fine for the both-arms-under-C commitment. The 2.1469-vs-2.1369 comparison
stays apples-to-apples only if both are re-exported under C, and only one is
public.

**The answer to "which one ships":** the KL arm (2.1369) is the runner-bound
checkpoint. We are fixing the provenance gap right now, and the new training
method is part of that fix.

## 5. Our new training method — HF Jobs, H200, our own transformers fork

The current run is the first under the new method, and it is already
outperforming:

- **Platform**: Hugging Face Jobs on an **H200** ($5/h, 141 GB VRAM), instead
  of the vast.ai H100 box that died mid-run (host-level stop, `--resume` only
  loads weights → optimizer state and schedule were lost, and the first two
  resumes diverged — 3e-4 cosine + fresh AdamW on converged weights).
- **Stack**: our own **8b-is/transformers fork** (v0.1.0, 5.16.0.dev0) + the
  fork overlay's thresholded-ternary BitLinear + mlx-cuda 0.30. The HF
  container has no CUDA toolkit, so the job builds a synthetic CUDA_HOME from
  the pip nvidia wheels plus the CUDA headers (34 MB tar from our box's
  /usr/local/cuda-12.4 include tree — `nv/target`, `cuda_bf16.h`, ...).
- **Continuation**: resumes from the 2.1369 best, but with `lr-init 1e-4`
  (not 3e-4), `lr-end 1e-5`, `grad-clip 1.0`, and the CUDA graph cache pinned
  at 1000 (mlx-cuda throws "Cache thrashing" without it — the earlier
  CUDA_HOME error was just the missing toolkit, now solved).
- **Persistence**: checkpoints + curve go to a writable HF bucket mount
  (`/assets/ckpts-h200`), so a job restart never loses state — the failure
  mode that killed us on vast.
- **Early signal**: epoch 1 val **2.0054** (KL 0.7378, val_kl 0.9598, 4.56
  steps/s on H200) — already below the 2.1369 best and the 2.1469 CE-only
  line, with the full schedule still ahead.

**Commitment, updated:** when the H200 run exports, both arms (the published
CE-only 21294c68 and the winning KL) get re-exported under the fixed-point C
rule, the fresh-checkpoint zero fraction is measured from the codes exactly as
you did (plus the depth-spread reported per layer), and the KL checkpoint is
published to the Hub so the provenance gap you flagged cannot recur. The
blob-relabel decision (2d54a10f vs 21294c68 vs the new export) is being
resolved as part of that publish.

---

*Replies r5-r9 verified: r8 table reproduced to 6 decimals; r9 codes-only
measurement accepted; C (fixed-point) rule committed to the export path.*
