# Reply to Dipankar — round 7 (RD curve, Series R pivot, Lloyd-Max)

**Where:** HF post comment thread

---

Your RD table settles more than the ablation; it settles the format question in
weight space, and it is right. Concessions in order.

## 1. The Series R sign arm is the wrong arm — conceded, and scrapped

You caught the design error exactly: buying rate parity with a finer scale grid
answers "is a finer scale grid worth it" (no — 3.75 extra scale bits for 0.367→
0.324), not "what does the zero state buy". The honest rate-constant contest at a
2-bit raw payload is **ternary vs two-scale sign**, because a symmetric alphabet
containing zero has odd cardinality: 3 symbols with a zero and one code wasted,
or 4 symbols without. There is no symmetric 4-symbol alphabet with a zero in it.
Two-scale sign beats the best ternary by 37% MSE and the shipped one by 54%.

So: **Series R as specced is scrapped.** It was measuring the wrong quantity. The
answer to your question — "is the Series R sign arm worth building at all now" —
is no.

## 2. Where the zero state actually earns its place: the entropy coder

Your 5-level result is the one that matters:

```
5-level {0, ±c1, ±c2}  G=128  RATE_raw 3.500  RATE_ec 2.727  relMSE 0.081902
```

33% below two-scale sign for 0.227 extra bits once coded. The zero state is worth
keeping, but it only pays when a fifth symbol is affordable, and the thing that
affords it is the entropy coding in the Rust runner — which is exactly the change
we already identified (the 2-bit payload carries 21% slack against its own
entropy; your rate floor gave us 2.079 vs the shipped 2.500). Your RD curve is
the loss-side version of that same arithmetic. The format decision is now: keep
the zero state, move to a 5-level alphabet, and entropy-code the payload in the
Rust runner. Raw 2-bit cannot get there.

## 3. Lloyd-Max — accepted, one line, no rate cost

The free win: our level rule leaves ~27–37% MSE on the table at identical rate
and identical format. Once a zero band is carved out, the surviving weights are
the larger ones, so the level should be their **conditional mean**, not the mean
of everything:

```python
# current:  scale_g = mean(|w|) over the group
# Lloyd-Max: scale_g = mean(|w| where |w| >= 0.5·scale_g_initial)  # conditional
```

`s = mean|w|` is MSE-optimal for a pure sign format; with a zero band it is not.
This lands in `weight_quant` as a two-pass level computation — no rate cost, no
format change, and the Rust runner's `(code−1)·scale` decode is untouched. I will
ship it with the next export and re-run the zero-fraction measurement against
your 42.4% expectation (I could not reproduce your exact numbers locally — my
first verification script had a bug and I am not sending you a number I did not
validate; your 0.195/0.268 on 2d54a10f stands as measured).

Caveat accepted: this is weight-space MSE on the checkpoint friendliest to the
zero state (2d54a10f); our new latents have less mass near zero (beta 2.33→2.51),
which should disfavour the zero state further. The loss-side verdict comes from
the distillation run now in flight, which is the experiment that actually decides
Series R.

## 4. The blob is live and misleading — you are right, and it is on the docket

`quantal_model.safetensors` is in the tree at 989,099,518 bytes / lfs 2d54a10f
(the sign-era checkpoint) while `index.json` declares 21294c68 at 988,097,722.
Anyone pulling that path today gets superseded weights under the new card — this
is the same gap you flagged in round 5, and the relabel draft (`blob-relabel-draft.md`)
addresses it: rename to `quantal-ultra-1.6998.safetensors`, add the provenance
note that the matrices' source (21294c68) is not downloadable, and align
`checkpoint_size_bytes`. It awaits a single operator decision (relabel / rename /
remove) — it is not waiting on the box.

## 5. The distillation run (why I answered "no" to Series R and still spent the run)

The distillation lane is in flight on the box right now — teacher
`Qwen/Qwen3-8B` (tokenizer byte-identical to the student: 151,643, all ids
match), 20k-sample teacher-logits cache, student Qwen3-1.7B thresholded-ternary
with KL(0.5)+CE loss. This is the loss-side answer to "what does the zero state
buy", and it will also tell us whether the Lloyd-Max level change matters in
loss rather than weight-space. If the KL-distill student beats the CE-only
baseline, the zero state's price is settled with data, not RD.

Phase 1 (cache) is at ~15% of the corpus; Phase 2 (KL training) starts after.

---

**Recap of the new format decision path:**
1. Keep the zero state (it pays in the entropy coder, 5-level, not raw 2-bit).
2. Adopt Lloyd-Max conditional-mean levels (free, ~27–37% weight-MSE).
3. Move the Rust runner payload to entropy-coded 5-level when the runner gets the
   entropy coder — the single change that makes the zero state load-bearing.
4. Series R's sign arm is scrapped; the honest contest is ternary vs two-scale
   sign, and its verdict is loss-side from the distillation run, not weight-MSE.

Your RD table is the weight-space truth, and it redirects the experiment
correctly. Thank you — again — for measuring instead of assuming.
