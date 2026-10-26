## 0.3.0

- A full SHA-256 check that passes leaves a `<model>.verified` stamp with the hash, size and modification time. Later checks trust the stamp while the size and modification time are unchanged, and hash again otherwise. On a Pixel 9 this takes a Gemma 4 E2B reload from 51 s to 0.6 s.
- `registerLocalModel` stamps the copy it hashed, so a person's own model is not hashed twice.
- Deleting or cancelling a model also removes its stamp.
- `ModelStore` takes an optional `hasher` for tests.

## 0.2.0

- Catalog URLs are pinned to a Hugging Face commit, and every entry has a SHA-256 (`ModelCatalogEntry.sha256` is now required).
- `ModelStore.verifiedPath` and `ModelStore.loadVerified` check a model's SHA-256 before every load. A file that does not match is deleted and never loaded.
- A person's own model has its SHA-256 recorded when it is added and checked before load.
- `ModelStore` takes an optional `catalog` for tests.

## 0.1.0

- First release. Android text generation with LiteRT-LM 0.18.0 (`OnDeviceLlm`, `LoadedModel.generate`, `generateStream`).
- Gemma 4 E2B and E4B catalog entries from the airo `core_ai` catalog.
- `ModelStore`: downloads through `airo_background_downloads`, size and SHA-256 checks, `registerLocalModel` for a person's own `.litertlm` file, delete.
