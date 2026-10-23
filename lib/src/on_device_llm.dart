import 'dart:async';

import 'package:flutter/services.dart';

import 'errors.dart';

/// Which processor the runtime uses. CPU works on every supported phone;
/// GPU is faster where the driver supports it.
enum LlmBackend { cpu, gpu }

/// Native calls, behind an interface so apps and tests can swap in a fake.
abstract interface class LlmPlatform {
  Future<bool> isSupported();
  Future<void> load(String path, LlmBackend backend);
  Future<void> validate(String path);
  Future<String> generate(String prompt, int? maxTokens);
  Stream<String> generateStream(String prompt, int? maxTokens);
  Future<void> unload();
}

/// Loads a local `.litertlm` model and generates text on the phone.
///
/// One model is loaded at a time. Each prompt runs in a fresh conversation,
/// so calls do not share context. Nothing is sent over the network.
class OnDeviceLlm {
  OnDeviceLlm({LlmPlatform? platform})
    : _platform = platform ?? MethodChannelLlmPlatform();

  final LlmPlatform _platform;
  String? _loadedPath;

  /// Whether this phone can run the runtime at all (Android 8+, 64-bit ARM).
  Future<bool> isSupported() => _platform.isSupported();

  /// Path of the loaded model, or `null`.
  String? get loadedPath => _loadedPath;

  /// Loads [path], replacing any loaded model.
  Future<LoadedModel> load(
    String path, {
    LlmBackend backend = LlmBackend.cpu,
  }) async {
    await _platform.load(path, backend);
    _loadedPath = path;
    return _LoadedModel(this, path);
  }

  /// Frees the loaded model.
  Future<void> unload() async {
    await _platform.unload();
    _loadedPath = null;
  }
}

/// A model ready to generate text.
abstract interface class LoadedModel {
  String get path;

  /// Full reply for [prompt].
  Future<String> generate(String prompt, {int? maxTokens});

  /// The reply so far, growing as the model writes. The last event is the
  /// full reply.
  Stream<String> generateStream(String prompt, {int? maxTokens});
}

class _LoadedModel implements LoadedModel {
  _LoadedModel(this._llm, this.path);

  final OnDeviceLlm _llm;

  @override
  final String path;

  void _checkLoaded() {
    if (_llm._loadedPath != path) {
      throw const GenerationError('This model is no longer loaded');
    }
  }

  @override
  Future<String> generate(String prompt, {int? maxTokens}) {
    _checkLoaded();
    return _llm._platform.generate(prompt, maxTokens);
  }

  @override
  Stream<String> generateStream(String prompt, {int? maxTokens}) {
    _checkLoaded();
    return _llm._platform.generateStream(prompt, maxTokens);
  }
}

/// The Android implementation.
class MethodChannelLlmPlatform implements LlmPlatform {
  MethodChannelLlmPlatform({
    this._channel = const MethodChannel('airo_on_device_llm'),
    this._streamChannel = const EventChannel('airo_on_device_llm/stream'),
  });

  final MethodChannel _channel;
  final EventChannel _streamChannel;

  @override
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> load(String path, LlmBackend backend) async {
    try {
      await _channel.invokeMethod<bool>('load', {
        'path': path,
        'backend': backend.name,
      });
    } on PlatformException catch (e) {
      throw _mapError(e, (m) => ModelLoadError(m));
    } on MissingPluginException {
      throw const UnsupportedDeviceError();
    }
  }

  @override
  Future<void> validate(String path) async {
    try {
      await _channel.invokeMethod<bool>('validate', {'path': path});
    } on PlatformException catch (e) {
      throw _mapError(e, (m) => InvalidModelFileError(m));
    } on MissingPluginException {
      throw const UnsupportedDeviceError();
    }
  }

  @override
  Future<String> generate(String prompt, int? maxTokens) async {
    try {
      final text = await _channel.invokeMethod<String>('generate', {
        'prompt': prompt,
        'maxTokens': ?maxTokens,
      });
      return text ?? '';
    } on PlatformException catch (e) {
      throw _mapError(e, (m) => GenerationError(m));
    }
  }

  @override
  Stream<String> generateStream(String prompt, int? maxTokens) {
    late StreamController<String> controller;
    StreamSubscription<Object?>? sub;
    controller = StreamController<String>(
      onListen: () {
        sub = _streamChannel.receiveBroadcastStream().listen((event) {
          if (event is! Map) return;
          switch (event['type']) {
            case 'text':
              controller.add(event['text'] as String? ?? '');
            case 'error':
              controller.addError(
                GenerationError(
                  event['message'] as String? ?? 'Generation failed',
                ),
              );
              controller.close();
            case 'done':
              controller.close();
          }
        }, onError: controller.addError);
        _channel
            .invokeMethod<bool>('generateStream', {
              'prompt': prompt,
              'maxTokens': ?maxTokens,
            })
            .catchError((Object e) {
              controller.addError(
                e is PlatformException
                    ? _mapError(e, (m) => GenerationError(m))
                    : e,
              );
              controller.close();
              return false;
            });
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> unload() async {
    try {
      await _channel.invokeMethod<bool>('unload');
    } on MissingPluginException {
      return;
    }
  }

  OnDeviceLlmError _mapError(
    PlatformException e,
    OnDeviceLlmError Function(String) fallback,
  ) {
    final message = e.message ?? e.code;
    return e.code == 'UNSUPPORTED_DEVICE'
        ? UnsupportedDeviceError(message)
        : fallback(message);
  }
}
