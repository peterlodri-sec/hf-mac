# Reply to Dipankar — round 6 (polarization half-point, rate floor, ablation design)

**Where:** HF post comment thread

---

Your §4 retirement is accepted, and your numbers reproduce on the live bytes.

## 1. Verified on the HF export (21294c68's quantizer, not the blob)

I pulled m000 from the live tree (the 21294c68 export — 62,120 distinct scales,
code-3 count zero) and ran your rate half on it:

```
m000 (L23 up_proj): -1=1,530,768  0=1,293,649  +1=1,533,727
  zero fraction 29.68% | empirical H = 1.5806 bits/weight
  sign+scale         1.500 bits/weight
  ternary entropy+sc 2.081
  ternary shipped    2.500
```

Your pooled H=1.5792 matches to the third decimal. The zero state costs **1.0
bit/weight as shipped, 0.58 at the floor**. The 2-bit payload is 21% slack
against its own entropy, and 42% of the sign→ternary gap is packing, not the
third state. Both numbers are now checked on the actual published bytes, so the
rate half of §5 is not an estimate — it is a property of the file.

## 2. Your ablation question: rate-constant, and I'll say why

> should the sign-vs-ternary ablation hold the format constant or the rate
> constant?

**Rate-constant, with the format-constant curve reported as a second series.**
Here is the reasoning, since I think it decides what the loss numbers mean.

The deployment comparison is not "ternary at 2.5 bits vs sign at 1.5 bits" —
that charges the zero state for packing, and nobody would ship the 2-bit payload
with a 1.58 entropy floor if entropy coding were available in the Rust runner.
The honest question a deployment faces is: *at the same bits/weight, what does
the zero state buy in loss?* So the primary ablation is:

- **Series R (rate-constant, ~2.5 bits/weight):** sign + scale at 2.5 (finer
  scale grid or two-scale sign), vs ternary + scale at 2.5 (2-bit payload as
  shipped). Difference in masked-val = the zero state's price at equal rate.
- **Series F (format-constant, 1.5 vs 2.5):** the current shipped comparison,
  reported for reference but not used for the verdict — because it conflates
  the zero state with packing overhead.

If Series R shows the zero state buys < ~0.05 CE at equal rate, we move the
deployed format to sign+scale and fold the zero band into the scale (which is
your compression arithmetic, and it is right). If it buys more, the third state
stays and we look at entropy-coding the payload in the Rust runner to reclaim
the 0.58. Either way the format decision is driven by the rate-constant number,
which is the one a deployment actually faces.

## 3. q_proj at 5.37 — confirmed, no story, and I won't invent one

I don't have a mechanism for it either. Your observation that it's *not* the
obvious one (k_proj had the widest spread on the old blob and sits on the null
now) is the correct frame. I'll flag it in the export notes and we'll watch it
on the 4B run's layer-0 output — if it recurs there, it's a tensor-family
property; if not, it was this checkpoint's noise. No hand-waving.

## 4. The monotonicity trace — honest status: blocked on the box

The saved checkpoints are on the training box, which just died (instance went
exited; restart is queued but the host hasn't freed resources). The one
checkpoint we have off-box (epoch-1 best of the 4B run, val 5.6562) is a single
point — not a trace. The moment the box is back I'll run your fixed-rule zero
fraction across every saved checkpoint and answer "does it move monotonically"
with data, not assertion. If it doesn't come back, the same trace is available
from any future run by saving per-epoch checkpoints — which I'll do anyway from
now on, because you've shown it's the cheapest polarization clock there is.

---

**Open items on my side, restated:**
1. Blob: put 21294c68 in the repo as `quantal_model.safetensors` (blocked on the
   same dead box; the file lives only there).
2. PR #47955 delta split — **RESOLVED (see §5 below)**.
3. Sign-vs-ternary ablation in Series R (rate-constant) + Series F (format) on
   the same corpus — the zero state's honest price.

## 5. PR #47955 delta split — measured, and it's the scale collapse

Your proposed experiment ran (pre-quantized ternary weights, per-group scales,
whatever's left is ActQuant). Five configurations on the live export, both gate
prompts, fp32:

| | A→B | B→C | C→D | A0→A |
|---|---|---|---|---|
| prompt 1 | **34.771** | **0.7503** | **0** | 33.174 |
| prompt 2 | **30.156** | **0.7997** | **0** | 28.814 |

A = collapsed scale (mean of per-64-group scales), ActQuant on · B = per-group
scales baked into the weight, ActQuant on · C = same, ActQuant bypassed ·
D = plain `BitNetForCausalLM(use_sub_norms=False)` with dequantized weights
(the deployed forward). Argmax: A→220, B/C/D→71703 (both prompts).

**The scale collapse dominates decisively — ~30–35 max-abs, ~40× the ActQuant
term.** ActQuant (B→C) is ~0.75–0.80 and does not even flip the argmax. And
**C→D = 0.0 exactly**: with per-group scales restored and ActQuant removed, the
quantized path is bit-identical to the deployed forward. There is no third
contributor — no rounding residue, no embedding/tokenizer term. Your "feed
per-group scales by hand, whatever is left is ActQuant" split is confirmed, and
what is left is ~nothing.

The fix for the PyTorch loader is therefore concrete: the per-group scales have
to live in the **weight** (as the export's `(code−1)·scale` dequant does), not in
the single-scalar `weight_scale` buffer — because the fork's `AutoBitLinear.forward`
broadcasts that buffer as a scalar and never reshapes it. Combined with
`use_sub_norms=False` and dropping the unconditional `ActQuant.apply`, the loader
reproduces the deployed forward to zero delta. (Caveat: the per-group scale form
cannot ride the 1-scalar buffer; it must be baked into the loaded weight.)

Your half-point concession is more useful than a full-point agreement would have
been, and the rate floor you handed us changes the design of the loss experiment
rather than just its interpretation.
