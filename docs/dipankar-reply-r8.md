# Dipankar r8 — fix-pont verifikáció + CE-only vs KL level-rule kérdés

## 1. Verifikáció — mind a négy sor pontosan reprodukálva

A fix-pont állítását futtattam, pontosan a te loopoddal, a 2d54a10f blob-on:

**Mérési környezet** (a te definíciód szerint):
- blob: `2d54a10f` — `PeetPedro/quantal-ternary` `quantal_model.safetensors` (989 MB, bf16 → fp32 konverzióval olvasva, safetensors header-offsetekből)
- layer 0: a 7 súlymátrix (`down/gate/up_proj` + `k/o/q/v_proj`) = **14,909,440 súly**, G=64 csoportok
- relMSE = MSE(ŵ, w) / mean(w²); zero% = a `codes == 0` arány

| rule | relMSE | zero% | vs shipped |
|---|---|---|---|
| shipped `s = mean\|w\|` | **0.267649** | **29.53** | +0.00% |
| A: level moves, band pinned to 0.5·s_init | **0.219453** | **29.53** | −18.01% |
| B: one pass, band moves with level | **0.206389** | **38.28** | −22.89% |
| C: iterated to the fixed point | **0.195194** | **42.43** | −27.07% |

**Konvergencia** (20 iteráció, `a = abs_w[abs_w >= 0.5*a].mean()`):

| iter | relMSE | zero% |
|---|---|---|
| 1 (= B) | 0.206389 | 38.28 |
| 11 | 0.195222 | 42.43 |
| 12 | 0.195209 | 42.43 |
| 20 | 0.195194 | 42.43 |

Minden érték 6 tizedesjegyre egyezik a tieddel — nincs eltérés egyetlen sorban sem. Az A-vs-C megkülönböztetésed helyes, és elismerem: **amit korábban "two-pass level computation"-ként elfogadtam, az a te A sora volt** — a band a 0.5·s_init-hez van pinelve, a level egyszer mozdul, a zero-frakció nem mozdul (29.53% marad). A valódi nyereség a C sor, a fix-pont.

## 2. A shipped rule a kódban (a deployed forward)

A jelenleg deployolt quantizer a fork `weight_quant`-ja (`python/mlx/nn/layers/bitlinear.py:37-69`):

```python
scale_g = mx.abs(wr).mean(axis=-1, keepdims=True)                 # G=64 csoportonként
q = mx.where(mx.abs(wr) < threshold * scale_g, 0.0, mx.sign(wr) * scale_g)  # threshold=0.5
```

Ez pontosan a **shipped sor**: `s = mean|w|`, one-pass, band = 0.5·s. A training és a deploy ugyanezt használja (`deployed_forward=True`), szóval a mérésed a valós, éles quantizerre vonatkozik — nem egy elméleti változatra.

## 3. Válasz a CE-only vs KL kérdésre

**A kérdésed:** a distillation run a CE-only-t és a KL-t a shipped level rule-on hasonlítja-e, vagy a konvergáltan?

**Válasz: mindkét kar a shipped rule-on fut.** A `train_quantal_distill.py` és a CE-only baseline is `replace_linear_with_bitlinear(model, deployed_forward=True)`-t használ — tehát mindkét kar ugyanazt a `weight_quant`-ot (shipped: `mean|w|`, one-pass, band 0.5·scale) futtatja a tréning alatt és a val loss mérésekor. A 2.1369 (KL) vs 2.1469 (CE-only) összehasonlítás **apples-to-apples a shipped rule-on** — a level rule nem különbözik a két kar között, tehát a kérdés, amit a run megválaszol, konzisztens.

**A finomság, amit ez felszínre hoz:** a C rule alkalmazása *export-time* ingyenes nyereség (nincs rate-költség, nincs formátum-változás, a runner `(code-1)*scale` dekódja érintetlen, az exportált scale = a konvergált `a`). De ha C-t elfogadjuk:

1. **Mindkét kart újra kell exportálni C-vel** ahhoz, hogy a CE-only vs KL összehasonlítás C-n is értelmes maradjon — különben a 2.1369-es szám shipped rule-on van, és nem összehasonlítható egy C-n exportált modell eredményeivel.
2. A tréning ideje alatt a deployed forward a shipped rule-t használja (a tanulás a shipped quantizerre optimalizál). Ha a tréning forward-ot is C-re váltjuk, az a tanítási objektívumot változtatja — ez egy *következő* run kérdése, nem az aktuálisé.
3. **A caveat-ed a friss checkpointon:** a 2d54a10f a zero-állapothoz legbarátabb checkpoint (beta 2.33). A v2 run latens-ei (beta 2.33 → 2.51) kevesebb tömeget hagynak a nulla közelében, tehát a konvergált band várhatóan 42.4% alatt landol — a fix iránya nem változik, a mérete igen. **Ezt a friss legjobb ckpt-on (2.1369) kell újramérni**, nem a 2d54a10f-ön.

## 4. Elfogadott döntések és következő lépések

- **Elfogadva (r7-tel együtt):** a conditional-mean level (Lloyd-Max) — de immár a **fix-pontos C formában** (12-20 iteráció, G=64-en, export-time, egyszer), nem a pinned-band A formában. A zero-state helye továbbra is az entropy-coderben marad.
- **Kötelezettségvállalás:** a C rule-t az export path-ba építjük (a `weight_quant`/export közös szabálya), és a következő export manifest-ben dokumentáljuk, hogy a scale a konvergált `a`, nem a `mean|w|`.
- **Újramérés:** a C rule hatását a friss 2.1369-es ckpt-on is lefuttatjuk (a 2d54a10f-en mért −27.07% helyett a tényleges, új-latens értékkel), és mindkét kart (CE-only, KL) C-vel újraexportálva adunk egy korrigált CE-vs-KL számot.

---

*A verifikációs script: `verify_fixedpoint2.py` (bf16→fp32 manuális safetensors olvasás, G=64 group-ok, 4 szabály + 20 iteráció konvergencia-naplóval). A blob: `PeetPedro/quantal-ternary` `quantal_model.safetensors`, blob `2d54a10f`.*
