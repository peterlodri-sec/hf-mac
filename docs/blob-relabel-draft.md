# Blob relabel draft — quantal-ternary (round-5 fix, Dipankar §1)

**Decision pending:** the 21294c68 checkpoint (source of the matrices, val 2.1469)
is lost (lived only on the destroyed training box). The `quantal_model.safetensors`
blob on the Hub is the 1.6998 ULTRA checkpoint (2d54a10f). This draft relabels the
repo honestly so the card, the manifest, and the downloadable file describe what
is actually there.

## 1. README.md — Layout block

Replace the current `## Layout` block with:

```markdown
## Layout

```
m000.json … m167.json   168 ternary matrices (packed codes + per-group scales)
index.json              capsule metadata + file manifest (sha256, shapes)
embeddings.f16          token embedding matrix, BF16→FP16, [151936, 896]
norms.f32               49 RMSNorm gain vectors (24×2 + final), [49, 896]
quantal-ultra-1.6998.safetensors   ULTRA checkpoint (val 1.6998, sha 2d54a10f…5c4c)
```

> **Note on the convenience checkpoint.** `quantal-ultra-1.6998.safetensors` is
> the 1.6998 ULTRA run checkpoint (sha `2d54a10f…5c4c`) — it is a *fine-tuning
> starting point*, NOT the source of the matrices. The matrices and assets in this
> repo were exported from the 2.1469 nightly best (sha `21294c68…8285`), which is
> **not available as a downloadable file** (the training box that produced it was
> decommissioned; the export captures its quantizer decisions, verified against
> the blob's bytes at sign-agreement 0.86 with misses concentrated in the bottom
> |w| decile). The manifest, the card, and the matrices describe the same tensor;
> the convenience blob is a different checkpoint and is labelled as such.
```

## 2. index.json — metadata

Set `checkpoint_size_bytes` to the real blob value and add a provenance note:

```json
"checkpoint_sha256": "21294c68f05f36fcf72a25246caea92cac6664173f684328a2aad72f9a988285",
"checkpoint_size_bytes": 989099518,
"blob_note": "The downloadable convenience file is quantal-ultra-1.6998.safetensors
  (sha 2d54a10f…, val 1.6998). The 21294c68 checkpoint that produced the matrices
  is not available as a file; the export preserves its quantizer decisions.",
```

(Optionally rename the file via LFS pointer + `git mv` on the hub so the name
matches the content — requires pushing a new LFS object under the new name and
deleting the old one; the README block above assumes the rename.)

## 3. Verification after push

- `curl index.json` → `checkpoint_sha256` still `21294c68…`, `checkpoint_size_bytes`
  now the real blob size.
- `README.md` Layout shows the relabelled filename + provenance note.
- The 168 matrix byte-counts still match the manifest (Dipankar verified 168/168).
- No `__metadata__` in the blob header remains a separate open item (header has
  null metadata — noted in round-5).

## Decision points for the operator

- [ ] Relabel only (rename in README/index, keep filename) — lowest risk
- [ ] Rename file too (`quantal_model.safetensors` → `quantal-ultra-1.6998.safetensors`)
      via LFS pointer swap — cleaner, needs a hub write + old-file delete
- [ ] Remove the blob entirely — matrices+assets alone reconstruct the model
