/// Base type for errors this package throws.
sealed class OnDeviceLlmError implements Exception {
  const OnDeviceLlmError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The phone cannot run the LiteRT-LM runtime (API level or CPU).
final class UnsupportedDeviceError extends OnDeviceLlmError {
  const UnsupportedDeviceError([
    super.message = 'This device cannot run on-device models',
  ]);
}

/// The runtime could not open the model file.
final class ModelLoadError extends OnDeviceLlmError {
  const ModelLoadError(super.message);
}

/// A file offered with `registerLocalModel` is not a usable `.litertlm` model.
final class InvalidModelFileError extends OnDeviceLlmError {
  const InvalidModelFileError(super.message);
}

/// `generate` was called before a model was loaded, or generation failed.
final class GenerationError extends OnDeviceLlmError {
  const GenerationError(super.message);
}
