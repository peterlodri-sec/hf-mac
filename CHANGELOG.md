# Changelog

All notable changes to HF-MAC{-1,0,+1}.

## [Unreleased]

### Added
- **Project Zero — local CPU ternary backend.** A third Run source:
  [`shifulegend/project-zero`](https://github.com/shifulegend/project-zero),
  a dependency-free C99 engine serving `{-1,0,+1}` inference on `:8090`.
  `ProjectZeroClient` + `scripts/setup-project-zero.sh` + `docs/project-zero.md`.
- **`HFMac --check-tools`** — a headless companion health check: resolves the
  binaries, probes the ayeOS daemon over its socket, and prints the entheai argv.
- **MiroFish connection** — connect to a local
  [`666ghj/MiroFish`](https://github.com/666ghj/MiroFish) swarm-intelligence
  prediction engine over HTTP (Flask `:5001`, Vue `:3000`). `MiroFishClient` +
  an Ecosystem card; AGPL stays a separate process. `docs/mirofish.md`.
- **Landing reskin** — `docs/` is now an interactive surface (animated ternary
  field, live MoE router demo, animated data-flow pipeline, reveals).

### Fixed
- **Companion detection** — the Ecosystem tab reported entheai / ayeOS /
  hf-mount / HF Accelerate as missing. Paths were hardcoded to `/usr/local/bin`
  (they live in `~/.cargo/bin`, `/opt/homebrew/bin`, the Python framework), and
  the Developer-ID build was signed with `app-sandbox`, which cannot read those
  paths or exec the children. A `Toolchain` resolver (PATH + known dirs + env
  overrides) now backs every client, and the OSS build is sandbox-free.
- **entheai launch** — the prompt must be **positional** (`--prompt` does not
  exist), with `--fanout` / `--no-companion`; and a first-wins continuation
  gate stops the timeout path and the completion path double-resuming (the
  v0.12.0 background crash).
- **ayeOS daemon** — the client dialed TCP:9876, but `ayeosd` binds a local
  **UNIX socket** (`/tmp/ayeosd.sock`) under the AyeFire covenant (no IP).

### Changed
- `Packaging/Info.plist` `0.9.3 → 0.12.0`; entitlements split into
  `hf-mac-devid.entitlements` (sandbox-free) and `hf-mac.entitlements` (App
  Store), guarded by `scripts/check-entitlements.sh` (AMFI-safe).

## [0.12.0] — 2026-08-12

### Added
- **HF Storage Buckets support** — native bucket management via the `hf`
  CLI integration: `hf buckets create/sync/info`, with Xet dedup and the
  built-in CDN for streaming training corpora to GPUs.
- **quantal-ternary ready** — first-class support for the constellation's
  0.5B BitNet b1.58 ternary model (masked val 0.5597): 168 ayeOS ternary
  matrices run through the MLX-QUANT + ayeOS stack, offline in Rust.

### Changed
- Version bumped to 0.12.0; landing page download URLs aligned to v0.12.0.
- Landing page now lists the quantal-ternary + HF Storage Bucket features.

## [0.11.0] — 2026-07-28

### Added
- Notarized `.dmg` release pipeline (Developer-ID signed, Gatekeeper-clean).

## [0.10.0] — 2026-07-28

### Added
- Ecosystem tab: Osaurus · entheai · ayeOS · MEM8 · MLX-QUANT unified status.

*the constellation · 0 + 1 · fine touch from within · vaked.dev*
