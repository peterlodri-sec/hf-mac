# Local Liberty Models — the halogen family

HF-MAC runs models through **Osaurus** on Apple Silicon. This note records the
*sibling* local-inference story we keep watching, on **AMD Strix Halo** (Ryzen
AI Max, gfx1151, 128 GB unified), and the pipeline that turns a base model into
an open, uncensored, rerunnable build.

## the engine and the base

- **Engine** — [`peonist-ai/halogen-flash-server`](https://github.com/peonist-ai/halogen-flash-server)
  serves a Qwen3.8 Flash MoE from a custom `hgn` pack, OpenAI-compatible.
- **Base model** — [`peonist-ai/halogen-qwen3.8-flash-next`](https://huggingface.co/peonist-ai/halogen-qwen3.8-flash-next).
  Community benchmarks on Strix Halo: prefill ~1.4–1.7k tok/s (8k–32k ctx),
  decode ~40–50 tok/s on a 1M-token window. Thread:
  [**"Very fast."**](https://huggingface.co/peonist-ai/halogen-qwen3.8-flash-next/discussions/1).

## the recipe (quantize → abliterate → liberate → projectZeroify)

```bash
# 1. quantize: safe-tensors -> bf16 gguf -> imatrix -> IQ4_XS
#    (imatrix from unsloth/Qwen3.8-Flash-Next-GGUF)
llama-quantize ... IQ4_XS
# 2. abliterate: use an uncensored base, e.g. orcarouter/Qwen3.8-Flash-Next-Uncensored
# 3. liberate: repack to the fast-load hgn form and publish it
flash_serve --repack IN.gguf --out OUT.hgn
# 4. projectZeroify: run it on the dependency-free C ternary engine
#    https://github.com/shifulegend/project-zero
```

**Gotcha:** a repack without the n-gram and draft tables yields **1166** tensors,
not the complete **1198** — the runtime then fails with
`checkpoint: no tensor named layers.N.ple.ngram_embedding.weight`.

## published builds (community, all credit to them)

| build | author |
|---|---|
| `davenetdev/halogen-qwen3.8-flash-next-uncensored` | davenetdev — first custom HGN in the wild |
| `G1LL1/Qwen3.8-Flash-Next-Uncensored-orca-halogen` | G1LL1 |
| `tatianyi/Qwen3.8-Flash-Next-Uncensored-Halogen` | tatianyi |

## see also

- blogpost: <https://pocoo.vaked.dev/posts/2026-10-08-quantize-abliterate-liberate.html>
- Project Zero setup: [`project-zero.md`](project-zero.md)
- Osaurus setup (Apple Silicon): the entheai guide, `osaurus-setup.md`

*Not affiliated with peonist-ai or the builders above; links are theirs.*
