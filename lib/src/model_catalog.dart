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
    this.sha256,
  });

  final String id;
  final String name;
  final String family;

  /// Public HTTPS URL that downloads without a login.
  final String url;

  /// Exact file size. The store rejects a file of any other size.
  final int sizeBytes;

  /// SHA-256 of the file in lowercase hex. When set, the download is verified
  /// against it. `null` means the size check is the only integrity check.
  final String? sha256;

  final String licence;
  final String licenceUrl;

  /// Device RAM below which the model is not offered.
  final int minMemoryMb;

  /// File name the store saves the model under.
  String get fileName => '$id.litertlm';
}

/// Gemma `.litertlm` models, smallest first. Sizes and URLs come from the
/// airo `core_ai` catalog, where these models already run on Android.
const List<ModelCatalogEntry> modelCatalog = [
  ModelCatalogEntry(
    id: 'gemma-4-e2b-it',
    name: 'Gemma 4 E2B',
    family: 'gemma',
    url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    sizeBytes: 2588147712,
    licence: 'Apache-2.0',
    licenceUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm',
    minMemoryMb: 3500,
  ),
  ModelCatalogEntry(
    id: 'gemma-4-e4b-it',
    name: 'Gemma 4 E4B',
    family: 'gemma',
    url: 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    sizeBytes: 3659530240,
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
