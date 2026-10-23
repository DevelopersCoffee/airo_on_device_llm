/// A model the store knows how to download.
class ModelCatalogEntry {
  const ModelCatalogEntry({
    required this.id,
    required this.name,
    required this.family,
    required this.url,
    required this.sizeBytes,
    required this.licence,
    required this.licenceUrl,
    required this.minMemoryMb,
    required this.sha256,
  });

  final String id;
  final String name;
  final String family;

  /// Public HTTPS URL that downloads without a login, pinned to a commit
  /// (`/resolve/<40-hex commit>/`), never a branch such as `main`, so a file
  /// changed upstream can never be downloaded in its place.
  final String url;

  /// Exact file size. The store rejects a file of any other size.
  final int sizeBytes;

  /// SHA-256 of the file in lowercase hex. The download is verified against
  /// it, and [ModelStore.verifiedPath] checks it again before every load.
  final String sha256;

  final String licence;
  final String licenceUrl;

  /// Device RAM below which the model is not offered.
  final int minMemoryMb;

  /// File name the store saves the model under.
  String get fileName => '$id.litertlm';
}

/// Gemma `.litertlm` models, smallest first. Sizes and URLs come from the
/// airo `core_ai` catalog, where these models already run on Android. URLs
/// are pinned to the Hugging Face commit whose file has this size and
/// SHA-256 (read from the Hub API on 2026-10-23).
const List<ModelCatalogEntry> modelCatalog = [
  ModelCatalogEntry(
    id: 'gemma-4-e2b-it',
    name: 'Gemma 4 E2B',
    family: 'gemma',
    url:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it.litertlm',
    sizeBytes: 2588147712,
    sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
    licence: 'Apache-2.0',
    licenceUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm',
    minMemoryMb: 3500,
  ),
  ModelCatalogEntry(
    id: 'gemma-4-e4b-it',
    name: 'Gemma 4 E4B',
    family: 'gemma',
    url:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/2eee7ac325f20eb8c9ac1d0e972f7c84663062da/gemma-4-E4B-it.litertlm',
    sizeBytes: 3659530240,
    sha256: '0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0',
    licence: 'Apache-2.0',
    licenceUrl:
        'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm',
    minMemoryMb: 5500,
  ),
];

/// The catalog entry with [id], or `null`.
ModelCatalogEntry? catalogEntry(String id) {
  for (final entry in modelCatalog) {
    if (entry.id == id) return entry;
  }
  return null;
}
