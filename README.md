# airo_on_device_llm

Run Gemma `.litertlm` models on an Android phone with [LiteRT-LM](https://ai.google.dev/edge/litert-lm), download them with [`airo_background_downloads`](https://pub.dev/packages/airo_background_downloads), or let people bring their own model file.

Carved out of the `airo` app (`LiteRtLmPlugin.kt` and the `core_ai` model catalog) so other DevelopersCoffee apps can use it.

## Privacy

- Inference runs on the phone. The plugin makes no network calls and declares no permissions.
- The only network traffic is a model download your app starts through `ModelStore.download`, which fetches a public file and sends no user content.
- No telemetry or analytics.

## Support

| Platform | Status |
|---|---|
| Android 8.0+ (API 26), 64-bit ARM | Supported |
| Everything else | `isSupported()` returns `false` |

## Generate text

```dart
final llm = OnDeviceLlm();
if (await llm.isSupported()) {
  final model = await llm.load(path); // LlmBackend.cpu by default
  final reply = await model.generate('Suggest three questions about tea', maxTokens: 512);
  await for (final soFar in model.generateStream('Explain in one line')) {
    print(soFar); // the reply so far; the last event is the full reply
  }
  await llm.unload();
}
```

Each call runs in a fresh conversation, so prompts do not share context. One model is loaded at a time; loading another replaces it.

## Download a catalog model

```dart
final store = ModelStore(
  downloads: createBackgroundDownloads(),
  root: Directory('${(await getApplicationSupportDirectory()).path}/models'),
  validator: MethodChannelLlmPlatform().validate,
);
final entry = modelCatalog.first;               // Gemma 4 E2B
store.progress(entry).listen(print);
await store.download(entry);
final model = await store.loadVerified(llm, entry.id); // null if missing or the hash does not match
```

`loadVerified` (or `verifiedPath`) hashes the file again **before every load** and compares it with the catalog's SHA-256. A file that does not match is deleted and never loaded; show the model as not ready. Hashing runs on a background isolate so the UI stays responsive, but a multi-gigabyte file still takes noticeable time; show a "checking the model" state. A download that fails SHA-256 verification is also deleted. Apps targeting Android 14+ must declare the WorkManager foreground service type in their own manifest, as the `airo_background_downloads` README explains:

```xml
<service
    android:name="androidx.work.impl.foreground.SystemForegroundService"
    android:foregroundServiceType="dataSync"
    tools:node="merge" />
```

`airo_background_downloads` 1.2 has no Wi-Fi-only option on Android, so check the connection yourself before calling `download` if you need that. Check `minMemoryMb` and `sizeBytes` against the phone before offering a model (`airo_device_profile` can report both).

### Catalog

| id | Size | Min RAM | SHA-256 |
|---|---|---|---|
| `gemma-4-e2b-it` | 2.59 GB | 3.5 GB | `181938105e0e…` |
| `gemma-4-e4b-it` | 3.66 GB | 5.5 GB | `0b2a8980ce15…` |

Every entry needs a SHA-256 and a URL pinned to a Hugging Face commit (`/resolve/<40-hex commit>/`, never `/resolve/main/`), so a file changed upstream can never be downloaded or loaded. A test fails if either is missing. To add or move an entry, read `sha` (the commit) and the file's `lfs.sha256` and `size` from `https://huggingface.co/api/models/<repo>?blobs=true`. A Gemma of about 1 GB or less is planned for apps that need a smaller first download.

## Bring your own model

```dart
final own = await store.registerLocalModel(pickedFilePath); // copies, checks the runtime can open it, records its SHA-256
final model = await store.loadVerified(llm, own.id);        // null if the file changed since
```

Throws `InvalidModelFileError` for a non-`.litertlm` file or one the runtime cannot open, and leaves nothing behind.

## Release builds

The plugin ships R8 keep rules for LiteRT-LM in `consumer-rules.pro`, so apps can minify. LiteRT-LM is pinned to 0.18.0 because its Kotlin API changed between minor releases.
