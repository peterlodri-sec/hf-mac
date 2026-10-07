# MiroFish — the swarm-intelligence lane

[MiroFish](https://github.com/666ghj/MiroFish) is a **swarm-intelligence
prediction engine**: it extracts seed information from the real world (news,
policy drafts, financial signals) and builds a parallel digital world where
thousands of agents with independent personalities, memory, and behaviour
interact — then returns a prediction report and an interactive world you can
poke from a god's-eye view.

> *"Rehearse the future in a digital sandbox, and win decisions after countless
> simulations."*

## what hf.app adds

hf.app **connects** to a locally-running MiroFish — it does not reimplement it
and does not ship it:

| piece | where |
|---|---|
| `MiroFishClient` — HTTP client (`/api/graph/*`) + lenient project decode | `Sources/HFMac/Services.swift` |
| `AppState.refreshMiroFish()` — reachability + project list | `Sources/HFMac/HFMacApp.swift` |
| the **Ecosystem** card + integration-map row (status · Refresh · Open MiroFish) | `Sources/HFMac/Views.swift` |

## the license boundary

MiroFish is **AGPL-3.0**; hf.app is **MIT**. They stay **separate processes**:
hf.app speaks HTTP to MiroFish's Flask backend and never links its code — the
same rule as `mpv` and `steel-sky`. Running MiroFish locally as a service is
the intended use; shipping it inside hf.app would drag the AGPL across the
boundary.

## run it

```bash
git clone https://github.com/666ghj/MiroFish
cd MiroFish
cp .env.example .env          # LLM_API_KEY + LLM_BASE_URL + LLM_MODEL_NAME, and ZEP_API_KEY
npm run setup:all
npm run dev                   # backend :5001 · frontend :3000
```

Then in hf.app → **Ecosystem**, MiroFish shows **connected** (green), and
**Open MiroFish** opens the frontend at `http://127.0.0.1:3000`.

## the API hf.app uses

The backend is a Flask app (`backend/run.py`, `FLASK_PORT` default **5001**)
with three blueprints — `/api/graph`, `/api/simulation`, `/api/report`:

| call | endpoint |
|---|---|
| reachability + project list | `GET /api/graph/project/list` |
| kick a build (provisional) | `POST /api/graph/build` `{requirement, seed}` |

The simulation engine itself is [OASIS](https://github.com/camel-ai/oasis)
(CAMEL-AI), and MiroFish's own simulation is backed by Zep Cloud memory.

---

*fine touch from within · the swarm, over a process boundary · 0 + 1*
