import 'dart:async';
import 'dart:io';

import 'package:airo_background_downloads/airo_background_downloads.dart';
import 'package:airo_on_device_llm/airo_on_device_llm.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDownloads implements BackgroundDownloads {
  final requests = <DownloadArtifactRequest>[];
  final cancelled = <String>[];
  final controller = StreamController<DownloadProgress>.broadcast();

  @override
  Stream<DownloadProgress> get events => controller.stream;

  @override
  Future<void> enqueue(DownloadArtifactRequest request) async =>
      requests.add(request);

  @override
  Future<void> cancel(String artifactId) async => cancelled.add(artifactId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory root;
  late FakeDownloads downloads;
  final validated = <String>[];
  var rejectValidation = false;

  ModelStore store() => ModelStore(
    downloads: downloads,
    root: root,
    validator: (path) async {
      validated.add(path);
      if (rejectValidation) throw const InvalidModelFileError('cannot open');
    },
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('models');
    downloads = FakeDownloads();
    validated.clear();
    rejectValidation = false;
  });

  tearDown(() => root.delete(recursive: true));

  test('every catalog entry has an HTTPS URL, a size and a unique id', () {
    final ids = <String>{};
    for (final entry in modelCatalog) {
      expect(Uri.parse(entry.url).scheme, 'https');
      expect(entry.sizeBytes, greaterThan(0));
      expect(ids.add(entry.id), isTrue);
      if (entry.sha256 != null) {
        expect(entry.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    }
  });

  test(
    'download enqueues the catalog file with its size and checksum',
    () async {
      final entry = modelCatalog.first;
      await store().download(entry);
      final request = downloads.requests.single;
      expect(request.artifactId, entry.id);
      expect(request.source.toString(), entry.url);
      expect(request.expectedBytes, entry.sizeBytes);
      expect(request.expectedSha256, entry.sha256);
      expect(request.destinationPath, '${root.path}/${entry.fileName}');
    },
  );

  test('installedPath needs the exact size', () async {
    final entry = modelCatalog.first;
    final s = store();
    expect(await s.installedPath(entry), isNull);
    await File('${root.path}/${entry.fileName}').writeAsBytes([1, 2, 3]);
    expect(await s.installedPath(entry), isNull);
  });

  test('a checksum failure deletes the file', () async {
    final entry = modelCatalog.first;
    final file = File('${root.path}/${entry.fileName}');
    await file.writeAsBytes([1]);
    final s = store();
    final seen = s.progress(entry).first;
    downloads.controller.add(
      DownloadProgress(
        artifactId: entry.id,
        status: DownloadStatus.failed,
        downloadedBytes: 1,
        totalBytes: entry.sizeBytes,
        failure: const DownloadFailure(
          code: DownloadFailureCode.integrityMismatch,
          message: 'sha mismatch',
        ),
      ),
    );
    await seen;
    expect(await file.exists(), isFalse);
  });

  test('registerLocalModel copies and validates a .litertlm file', () async {
    final source = File('${root.path}/mine.litertlm')..writeAsBytesSync([1, 2]);
    final model = await store().registerLocalModel(source.path);
    expect(model.isOwn, isTrue);
    expect(File(model.path).existsSync(), isTrue);
    expect(validated, [model.path]);
    final all = await store().installed();
    expect(all.map((m) => m.id), [model.id]);
    await store().delete(model.id);
    expect(File(model.path).existsSync(), isFalse);
  });

  test(
    'registerLocalModel rejects other files and removes failed copies',
    () async {
      final text = File('${root.path}/notes.txt')..writeAsStringSync('x');
      expect(
        () => store().registerLocalModel(text.path),
        throwsA(isA<InvalidModelFileError>()),
      );

      rejectValidation = true;
      final source = File('${root.path}/broken.litertlm')
        ..writeAsBytesSync([0]);
      await expectLater(
        store().registerLocalModel(source.path),
        throwsA(isA<InvalidModelFileError>()),
      );
      expect(Directory('${root.path}/own').listSync(), isEmpty);
    },
  );
}
