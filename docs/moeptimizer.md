# MOE-ptimizer — the context-optimizing proxy lane

[MOE-ptimizer](https://github.com/peterlodri-sec/moeptimizer) is a **transparent
OpenAI-compatible proxy** that optimizes context for MoE + MTP models in
multi-turn agentic tasks — large token savings with **byte-stable prefixes**, so
the backend's native prefix cache is reused instead of evicted.

```
Client (OpenAI SDK) → moeptimizer:8080 → backend (e.g. Lemonade :13305)
```

## what hf.app adds

hf.app treats it as **another OpenAI endpoint** — `OsaurusClient` already speaks
that shape, so the wire is a new `InferenceSource`:

| piece | where |
|---|---|
| `InferenceSource.moeptimizer` — a fourth Run source | `Sources/HFMac/HFMacApp.swift` |
| `AppState.refreshMoeptimizer()` — `GET /v1/models` probe | `Sources/HFMac/HFMacApp.swift` |
| the **Ecosystem** card + integration-map row | `Sources/HFMac/Views.swift` |

Select **MOE-ptimizer (proxy)** in the Run tab and hf.app routes chat through
the proxy — you get the token savings without changing anything else.

## run it

```bash
git clone https://github.com/peterlodri-sec/moeptimizer
cd moeptimizer
# follow its README (uv/pyproject) — the proxy listens on :8080 by default
```

Then in hf.app → **Run** → select **MOE-ptimizer (proxy)** and **Refresh**.

## port

`8080` by default (the repo's own default). On this Mac `8080` is held by the
litellm caddy, so override with `MOEPTIMIZER_PORT` — hf.app reads the same env
var.

---

*fine touch from within · the context keeps its cache · 0 + 1*
