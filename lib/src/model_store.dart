import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:airo_background_downloads/airo_background_downloads.dart';
import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'model_catalog.dart';
import 'on_device_llm.dart';

/// Checks that the runtime can open a model file. Throws
/// [InvalidModelFileError] or [UnsupportedDeviceError] when it cannot.
typedef ModelValidator = Future<void> Function(String path);

/// A model on this phone: downloaded from the catalog or the person's own.
class InstalledModel {
  const InstalledModel({
    required this.id,
    required this.path,
    required this.isOwn,
  });

  final String id;
  final String path;

  /// `true` for a file the person picked with [ModelStore.registerLocalModel].
  final bool isOwn;
}

/// Keeps models in one app-private directory.
///
/// Catalog models are downloaded with `airo_background_downloads`, which
/// verifies their SHA-256. A person's own model is copied in, checked by the
/// runtime, and its SHA-256 recorded next to it.
///
/// Before any model is loaded, [verifiedPath] (or [loadVerified]) hashes the
/// file again and compares it with the catalog or the recorded hash. A file
/// that does not match is deleted and never loaded.
class ModelStore {
  ModelStore({
    required this._downloads,
    required this._root,
    required this._validator,
    this._catalog = modelCatalog,
  });

  final List<ModelCatalogEntry> _catalog;
  final BackgroundDownloads _downloads;
  final Directory _root;
  final ModelValidator _validator;

  Directory get _ownDir => Directory('${_root.path}/own');

  String _catalogPath(ModelCatalogEntry entry) =>
      '${_root.path}/${entry.fileName}';

  /// Starts or resumes the download of [entry]. Progress for it arrives on
  /// [progress]. A file that fails verification is deleted.
  Future<void> download(ModelCatalogEntry entry) async {
    await _root.create(recursive: true);
    await _downloads.enqueue(
      DownloadArtifactRequest(
        artifactId: entry.id,
        source: Uri.parse(entry.url),
        destinationPath: _catalogPath(entry),
        expectedBytes: entry.sizeBytes,
        expectedSha256: entry.sha256,
        displayName: entry.name,
      ),
    );
  }

  /// Progress events for the download of [entry].
  Stream<DownloadProgress> progress(ModelCatalogEntry entry) => _downloads
      .events
      .where((event) => event.artifactId == entry.id)
      .asyncMap((event) async {
        if (event.failure?.code == DownloadFailureCode.integrityMismatch) {
          await _deleteIfExists(File(_catalogPath(entry)));
        }
        return event;
      });

  /// Stops the download of [entry] and removes the partial file.
  Future<void> cancel(ModelCatalogEntry entry) async {
    await _downloads.cancel(entry.id);
    await _deleteIfExists(File(_catalogPath(entry)));
  }

  /// Path of [entry] when it is fully downloaded, else `null`.
  Future<String?> installedPath(ModelCatalogEntry entry) async {
    final file = File(_catalogPath(entry));
    if (!await file.exists()) return null;
    return await file.length() == entry.sizeBytes ? file.path : null;
  }

  /// Copies a person's own `.litertlm` file into the store and checks that the
  /// runtime can open it. Returns the new model's id.
  Future<InstalledModel> registerLocalModel(String sourcePath) async {
    final source = File(sourcePath);
    if (!sourcePath.toLowerCase().endsWith('.litertlm')) {
      throw const InvalidModelFileError('Choose a .litertlm model file');
    }
    if (!await source.exists()) {
      throw const InvalidModelFileError('The file could not be found');
    }
    await _ownDir.create(recursive: true);
    final id = 'own-${DateTime.now().microsecondsSinceEpoch}';
    final target = File('${_ownDir.path}/$id.litertlm');
    await source.copy(target.path);
    try {
      await _validator(target.path);
      await _recordedHash(id).writeAsString(await sha256OfFile(target.path));
    } catch (_) {
      await _deleteIfExists(target);
      await _deleteIfExists(_recordedHash(id));
      rethrow;
    }
    return InstalledModel(id: id, path: target.path, isOwn: true);
  }

  File _recordedHash(String ownId) => File('${_ownDir.path}/$ownId.sha256');

  /// Path of model [id] after checking its SHA-256, or `null`.
  ///
  /// A catalog model must match the catalog's size and SHA-256. A person's own
  /// model must match the hash recorded when it was added; an own model added
  /// before hashes were recorded gets its hash recorded now. A file that does
  /// not match is deleted. Call this before every load.
  Future<String?> verifiedPath(String id) async {
    final entry = _entry(id);
    if (entry != null) {
      final file = File(_catalogPath(entry));
      if (!await file.exists()) return null;
      if (await file.length() != entry.sizeBytes ||
          await sha256OfFile(file.path) != entry.sha256) {
        await _deleteIfExists(file);
        return null;
      }
      return file.path;
    }
    final file = File('${_ownDir.path}/$id.litertlm');
    if (!await file.exists()) return null;
    final actual = await sha256OfFile(file.path);
    final recorded = _recordedHash(id);
    if (!await recorded.exists()) {
      await recorded.writeAsString(actual);
      return file.path;
    }
    if ((await recorded.readAsString()).trim() != actual) {
      await _deleteIfExists(file);
      await _deleteIfExists(recorded);
      return null;
    }
    return file.path;
  }

  /// Loads model [id] with [llm] only if [verifiedPath] accepts it. Returns
  /// `null`, without calling the runtime, when the file is missing or does not
  /// match its hash; the app should then show the model as not ready.
  Future<LoadedModel?> loadVerified(
    OnDeviceLlm llm,
    String id, {
    LlmBackend backend = LlmBackend.cpu,
  }) async {
    final path = await verifiedPath(id);
    if (path == null) return null;
    return llm.load(path, backend: backend);
  }

  /// Every usable model in the store.
  Future<List<InstalledModel>> installed() async {
    final models = <InstalledModel>[];
    for (final entry in _catalog) {
      final path = await installedPath(entry);
      if (path != null) {
        models.add(InstalledModel(id: entry.id, path: path, isOwn: false));
      }
    }
    if (await _ownDir.exists()) {
      await for (final file in _ownDir.list()) {
        if (file is File && file.path.endsWith('.litertlm')) {
          final name = file.uri.pathSegments.last;
          models.add(
            InstalledModel(
              id: name.substring(0, name.length - '.litertlm'.length),
              path: file.path,
              isOwn: true,
            ),
          );
        }
      }
    }
    return models;
  }

  /// Removes a model by id, downloaded or own.
  Future<void> delete(String id) async {
    final entry = _entry(id);
    if (entry != null) {
      await _deleteIfExists(File(_catalogPath(entry)));
      return;
    }
    await _deleteIfExists(File('${_ownDir.path}/$id.litertlm'));
    await _deleteIfExists(_recordedHash(id));
  }

  ModelCatalogEntry? _entry(String id) {
    for (final entry in _catalog) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}

/// SHA-256 of the file at [path] in lowercase hex, computed on a background
/// isolate so a multi-gigabyte model does not block the UI.
Future<String> sha256OfFile(String path) => Isolate.run(() async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
});
