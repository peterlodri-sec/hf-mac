# Publishing hf.app

Two independent distribution paths. The first is a direct/OSS download; the second
is the Mac App Store. They use *different* Apple certificates.

---

## 1. Developer-ID notarized DMG  (direct download / OSS)  — **nearly done**

Workflow: `.github/workflows/release.yml` — on a `v*` tag it builds (SwiftPM) →
bundles `HFMac.app` → Developer-ID signs (hardened runtime + the **sandbox-free**
`Packaging/hf-mac-devid.entitlements`) → **notarizes + staples** → makes a DMG →
cuts a GitHub Release.

> **Entitlements gotcha — AMFI vs plutil.** `packaging/*.entitlements` are read
> by **AMFI** at signing time, whose XML parser is stricter than `plutil`. A
> double hyphen (`--`) inside an XML comment makes `plutil -lint` say `OK` but
> AMFI fail with `Failed to parse entitlements: AMFIUnserializeXML: syntax error`.
> The failure is quiet: `codesign` exits non-zero and the binary **keeps its
> previous (often linker-signed ad-hoc) signature**, so a build can *look*
> signed but not be. Keep entitlement comments free of `--`, and run
> `bash scripts/check-entitlements.sh` — it probes each file through `codesign`
> (the same AMFI path) and is wired into both `release.yml` and `mas.yml` before
> they sign.
>
> **Two entitlement sets, on purpose.** `hf-mac-devid.entitlements` (empty, no
> sandbox) is for the Developer-ID/OSS build — it drives local companions
> (`entheai`, `ayeosd`, `hf-mount`, `python3`) as subprocesses, which
> app-sandbox forbids. `hf-mac.entitlements` (app-sandbox + network.client +
> audio-input) is for the Mac App Store build.

**Secrets (7). 5 are already set** from `entheai/.env`:

| secret | status | source |
|---|---|---|
| `MACOS_CERTIFICATE` (base64 Developer-ID `.p12`) | ✅ set | `.env MACOS_CERTIFICATE_SECRET` |
| `MACOS_CERTIFICATE_PWD` | ✅ set | `.env` |
| `MACOS_SIGN_IDENTITY` | ✅ set | `.env` |
| `NOTARY_KEY` (base64 App Store Connect `.p8`) | ✅ set | `.env MACOS_NOTARY_KEY` |
| `KEYCHAIN_PWD` | ✅ set | generated |
| **`NOTARY_KEY_ID`** | ⛔ **add it** | your ASC API key's Key ID |
| **`NOTARY_ISSUER_ID`** | ⛔ **add it** | ASC → Users & Access → Integrations → Issuer ID |

> These two live in **entheai's** GitHub secrets already (the same `.p8`), but
> secret *values* can't be read across repos. Copy them, or grab from App Store
> Connect. Then:

```bash
gh secret set NOTARY_KEY_ID    --repo peterlodri-sec/hf-mac
gh secret set NOTARY_ISSUER_ID --repo peterlodri-sec/hf-mac
git tag v0.1.0 && git push --tags     # → notarized DMG on Releases
```

---

## 2. Mac App Store  — a separate, bigger track

MAS needs *different* certs than Developer-ID, plus an app record. The app is
already **sandboxed** (`Packaging/hf-mac.entitlements`: app-sandbox +
network.client — enough for the HF API and Osaurus on localhost), so the code is
MAS-ready. What's still required (yours to create — none of this is in `.env`):

1. **App Store Connect app record** — bundle id **`dev.peterl.hfmac`**, category
   Developer Tools.
2. **Certs:** *Apple Distribution* (signs the `.app`) + *Mac Installer
   Distribution* (signs the `.pkg`).
3. **Provisioning profile:** a Mac App Store profile for the bundle id, embedded
   at `Contents/embedded.provisionprofile`.
4. Build → sign → **`productbuild`** a `.pkg` → upload with **`xcrun altool
   --upload-app`** / Transporter. Scaffold: `.github/workflows/mas.yml`.

**Recommendation:** MAS is cleanest from an **Xcode project** via **Xcode Cloud**
(Apple-managed signing, archive + upload handled for you). That project now exists —
generated from [`project.yml`](project.yml) (XcodeGen) over the same `Sources/HFMac`,
with a shared `HFMac` scheme and Xcode Cloud clone/pre-build hooks in `ci_scripts/`.
It's verified to build.

👉 **Full step-by-step: [`APP_STORE.md`](APP_STORE.md)** — App Store Connect app record,
Xcode Cloud workflow setup, and swapping the DMG runners to Blacksmith.

🜂 *ahogy lennie kell* — ship the honest DMG now; the store when the record's live.
