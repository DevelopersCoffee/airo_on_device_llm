import 'package:airo_on_device_llm/airo_on_device_llm.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('airo_on_device_llm');
  final calls = <MethodCall>[];

  void handle(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('loads a model and generates text', () async {
    handle(
      (call) async => switch (call.method) {
        'load' => true,
        'generate' => 'hello from gemma',
        _ => null,
      },
    );
    final llm = OnDeviceLlm();
    final model = await llm.load('/models/a.litertlm');
    expect(await model.generate('hi', maxTokens: 64), 'hello from gemma');
    expect(calls.first.arguments, {
      'path': '/models/a.litertlm',
      'backend': 'cpu',
    });
    expect(calls.last.arguments, {'prompt': 'hi', 'maxTokens': 64});
  });

  test('maps native errors to typed errors', () async {
    handle(
      (call) async =>
          throw PlatformException(code: 'UNSUPPORTED_DEVICE', message: 'no'),
    );
    await expectLater(
      OnDeviceLlm().load('/x.litertlm'),
      throwsA(isA<UnsupportedDeviceError>()),
    );

    handle(
      (call) async =>
          throw PlatformException(code: 'LOAD_FAILED', message: 'bad file'),
    );
    await expectLater(
      OnDeviceLlm().load('/x.litertlm'),
      throwsA(isA<ModelLoadError>()),
    );

    handle(
      (call) async =>
          throw PlatformException(code: 'INVALID_MODEL', message: 'bad'),
    );
    await expectLater(
      MethodChannelLlmPlatform().validate('/x'),
      throwsA(isA<InvalidModelFileError>()),
    );
  });

  test('a replaced model can no longer generate', () async {
    handle((call) async => call.method == 'load' ? true : 'text');
    final llm = OnDeviceLlm();
    final first = await llm.load('/a.litertlm');
    await llm.load('/b.litertlm');
    expect(() => first.generate('hi'), throwsA(isA<GenerationError>()));
  });

  test('isSupported is false when the plugin is missing', () async {
    expect(await OnDeviceLlm().isSupported(), isFalse);
  });
}
