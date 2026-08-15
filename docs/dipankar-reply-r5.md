# Reply to Dipankar — round 5 (blob mismatch, zero-state, PR delta)

**Where:** HF post comment thread (the "does this model ever want a zero?" round)

---

You're right about the blob, and I want to be precise about exactly which parts of
your read I'm conceding, because they're not all the same fact.

## 1. The blob mismatch — confirmed, and it's on me

`index.json` declares `checkpoint_sha256 21294c68…8285`, size 988,097,722, val 2.1469.
The `quantal_model.safetensors` blob on the Hub is `2d54a10f…5c4c`, size 989,099,518 —
the 1.6998 file. Two different checkpoints, 1,001,796 bytes apart, and the blob is the
only one a reader can download. That is a real gap, it is the same shape as the one we
closed a round ago, and I'm not going to wave it off: **the manifest, the card, and the
matrices describe 21294c68; the convenience blob is 2d54a10f.** The fix is to put the
21294c68 checkpoint in the repo as `quantal_model.safetensors` (or rename it and make
the Layout block name it explicitly), and update `index.json`'s `checkpoint_size_bytes`
to the real value. The 21294c68 file currently lives only on the training box that
produced it — I'm retrieving it and will re-push in the manifest order. Until then the
repo is internally inconsistent, exactly as you say.

## 2. What your control proved about the zero state

Your per-group-scale control on the *published blob's layer 0* is the cleaner experiment,
and it settles something I'd been assuming rather than measuring:

- k_proj zero appetite: 42.96% (per-tensor) → 30.65% (per-group-64) — a 12.3 point drop
- the drop tracks the tensor's scale heterogeneity (k_proj 5.43x group p99/p50 → −12;
  up_proj 1.24x → −0.20)
- your Gaussian null at group 64: 30.73%; our export pools to 29.02% — five of seven
  tensors below the null

So the zero state is not paid for by *appetite* at either checkpoint. That part is
conceded cleanly: the per-group scale finds ~29% zeros regardless of which checkpoint,
and the third state's justification has to be loss, not histogram. That's a fair and
precise correction to how I'd framed the nightly.

But I want to keep one thing separate, because it's the point of the thresholded
quantizer and it survives your control: **the zero state is no longer paid for by the
format's bytes either.** In the old sign-based export the zeros were 12-in-4.36M —
the third code was *dead*, a slot the format carried in every file. In the new export
it's ~29% live, on the same checkpoint rule you held fixed. Your own read of m161–m167
confirms it: zero code-3s, zero fractions 28–31%, pooled 29.02%. So even if the loss
argument for the zero state ends up marginal, the format is at least *honest* now — it
stores a 2-bit code whose third state actually occurs, and the per-group scale array
carries 62,120 distinct values instead of 2. The "scalar wearing a shape" is gone from
the export even if the checkpoint's latent weights haven't polarized.

## 3. The PR #47955 delta — your decomposition is the right way to measure it

`use_sub_norms=False` is one of three differences, and you're right that the other two
are mine to separate. The clean experiment is exactly what you propose: feed the
PyTorch path pre-quantized ternary weights with `weight_scale` set per group by hand
(so the 68,096 group scales are represented), and whatever residual delta remains is
ActQuant. I'll run that on `quantal_to_bitnet.py` against the fresh export and report
the split. My working guess: the scale collapse (one scalar vs 68,096) is the larger
term, because the Rust runner and the MLX reference agree to 1.3e-5 with the group
scales intact — the collapse only enters at the PyTorch loader.

## 4. The one thing I'd push back on, briefly

"The published epoch-10 blob has not polarized" — I want to flag that the blob's
polarization state is only meaningful if we agree the blob is authoritative, and right
now it isn't (see §1). Once the correct 21294c68 file is in the repo, the decile table
deserves a re-run against *it* — my expectation is that the same-signature shape (flips
concentrated in the bottom |w| decile) will read differently on the checkpoint the
matrices actually came from, because the thresholded quantizer was trained into that
checkpoint from epoch 1, not applied to it post-hoc. If I'm wrong, the control still
stands and I'll say so.

## 5. What I'm doing about the format cost

Your §4 arithmetic (2 bits on a 1-bit payload, 68,096-entry array on near-one-number)
is the compression question the gain-slot work is meant to answer. The thresholded
export is the honest baseline; the next question is whether the *deployed* format should
be sign+scale (1 bit + per-group scale) with the zero state folded into the scale, or
stay 2-bit. The loss comparison on the new corpus (2.1469 vs the 1.6998 line) doesn't
settle it because the corpus changed — I'll run the same-corpus sign-vs-ternary ablation
once the current run finishes, which is the only way to give the zero state its honest
price.

---

**Summary of what I'm fixing now:**
1. Retrieve 21294c68 from the training box, push it as `quantal_model.safetensors`,
   align `index.json` `checkpoint_size_bytes` → manifest-consistent state. (Your §1.)
2. Run your PR #47955 delta split (scale-collapse vs ActQuant) on `quantal_to_bitnet.py`.
3. Run the same-corpus sign-vs-ternary loss ablation for the zero state's real price.

Your reading of the two files as "different ticks of the training clock" is the most
useful single sentence in this round — it reframes the blob mismatch from a packaging
bug into evidence, and it's the framing I'll use to make sure the convenience file and
the export never drift again. Thank you for checking the public bytes instead of the
repo's claims.
