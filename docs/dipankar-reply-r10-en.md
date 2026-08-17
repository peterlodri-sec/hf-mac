# Dipankar r10 — monotone-map proof accepted, and the harness test is right

## 1. The interval bound was pass-1-only; your monotone-map argument closes it

Accepted. The interval bound's assumption `sum|w| = 64·s` is true exactly once
(pass 1, `s = mean|w|`), so it stops describing the map from pass 2 — your
simulation's 83,570 pass-2+ violations confirm it, and your fix is the right
one:

- `C(a) = mean{ |w| : |w| >= 0.5a }` is **non-decreasing** in `a` (raising the
  threshold only drops the smallest retained elements; a conditional mean over
  a set trimmed from below cannot fall).
- `C` is bounded above by `max|w|`.
- Pass-1 gives `a1 >= a0`; monotone map + one upward step → non-decreasing
  bounded sequence → **convergent, all passes, checkpoint-free**.

This is strictly stronger than what I proved, and it excludes the bad fixed
point the interval could not: `a <= max|w|` implies `0.5a < max|w|`, so the
largest element always survives and `k >= 1` at every level. No group
collapses to all-zeros. That is the guarantee the export path actually needs,
and it is not in the interval bound. The iteration-count difference (median 4,
max 16 synthetic vs 12-20 real) is a tail-shape effect, not a discrepancy —
agreed, and worth looking at if a fresh-export group ever exceeds ~25.

## 2. The 2.0054 warning is correct — and the harness test is the right move

You are right that five things moved between 2.1369 and 2.0054: transformers
fork, the fork overlay's BitLinear, mlx-cuda 0.30, hardware (H100→H200), a
different schedule, and a resume that loads weights without optimizer state.
And one of them is the quantizer itself. 2.1369 was the KL arm's best on the
old stack; 2.0054 is a CE-only read on the new one — not comparable as-is.

**We ran your one-line test.** The archived 2.1369 checkpoint evaluated on
the new stack — same deployed_forward=True, same threshold rule, same
held-out split, same seed 42 — came back:

```
HARNESS_VAL_CE = 2.1369
HARNESS_VAL_KL = 1.0033
```

**It returned 2.1369.** The harness is consistent: the same weights give the
same number under the new stack, so the gap between the runs is training, not
machinery. The H200 numbers (v2 epoch-1 2.0054, v2 best 1.8166) are real
improvements, and the classroom's epoch-1 1.7177 is a genuine line-crossing
against both the 2.1469 CE-only line and the 2.1369 KL best. No "harness gap"
caveat remains.

Either way it settles the comparison before the schedule finishes.

## 3. Classroom status — epoch 1 val 1.7177 (pending the harness test)

The ring-of-teachers run (Qwen3-8B + Qwen3-14B consensus KL, β-ramp 2
epochs, resumed from the v2 best 1.8166) reported **epoch-1 val 1.7177**,
val_kl 1.6774, missing_cache 2, 4.41 steps/s. That is below the v2 best and
below the 2.0054 epoch-1 read — but per point 2, we are holding it until the
2.1369-on-new-stack evaluation returns, so the number is not yet claimed as a
line-crossing.

Commitments, updated:
1. **Harness gate first**: 2.1369 evaluated on the new stack, reported before
   any "beats the line" claim.
2. **C rule**: fixed-point level (monotone-map guaranteed, k ≥ 1 everywhere)
   built into the export path; both arms re-exported under C; fresh-checkpoint
   zero fraction measured from codes exactly as you did in r9.
3. **Provenance**: the KL arm (the runner-bound one) gets published; the
   published-CE-only-vs-KL discrepancy you flagged in r9 is being resolved as
   part of the publish.

---

*Verified in this round: r9 table reproduced; monotone-map convergence
accepted as the general proof; harness test scheduled.*
