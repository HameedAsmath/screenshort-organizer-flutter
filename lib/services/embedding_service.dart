import 'dart:typed_data';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

import 'clip_tokenizer.dart';

import 'dart:isolate';

class EmbeddingService {
  static late OrtSession _imageSession;
  static late OrtSession _textSession;
  static late ClipTokenizer _tokenizer;
  static bool _initialized = false;
  static Future<void>? _initFuture;

  /// Loads the models once. If it's already loading, callers wait for the
  /// same job instead of starting a second one.
  static Future<void> initialize() {
    _initFuture ??= _loadModels();
    return _initFuture!;
  }

  /// Initialize ORT sessions
  static Future<void> _loadModels() async {
    if (_initialized) return;

    try {
      print('🔄 Loading CLIP models...');

      OrtEnv.instance.init();
      final options = OrtSessionOptions();

      // Load image encoder
      final imageModel = await rootBundle.load('assets/clip_image.onnx');
      _imageSession = OrtSession.fromBuffer(
        imageModel.buffer.asUint8List(),
        options,
      );
      print('✅ Image model loaded');
      print('   image inputs: ${_imageSession.inputNames}');
      print('   image outputs: ${_imageSession.outputNames}');

      // Load text encoder
      final textModel = await rootBundle.load('assets/clip_text.onnx');
      _textSession = OrtSession.fromBuffer(
        textModel.buffer.asUint8List(),
        options,
      );
      print('✅ Text model loaded');
      print('   text inputs: ${_textSession.inputNames}');
      print('   text outputs: ${_textSession.outputNames}');

      _tokenizer = await ClipTokenizer.load();
      print('✅ Tokenizer loaded');

      _initialized = true;
    } catch (e) {
      print('❌ Error loading models: $e');
      _initFuture = null;
      rethrow;
    }
  }

  /// Generate embedding from image file
  static Future<List<double>> generateImageEmbedding(
    String imagePath, {
    bool background = true,
  }) async {
    try {
      if (!_initialized) await initialize();

      final normalized = background
          ? await Isolate.run(() => _preprocessImage(imagePath))
          : _preprocessImage(imagePath);

      final inputTensor = OrtValueTensor.createTensorWithDataList(normalized, [
        1,
        3,
        224,
        224,
      ]);
      final embedding = await _run(
        _imageSession,
        'pixel_values',
        inputTensor,
        background: background,
      );
      print('✅ Image embedding generated (dim: ${embedding.length})');
      return embedding;
    } catch (e) {
      print('Error generating image embedding: $e');
      return [];
    }
  }

  /// Generate embedding from text
  static Future<List<double>> generateTextEmbedding(String text) async {
    try {
      if (!_initialized) await initialize();

      final ids = _tokenizer.encode(text);
      print('   tokens: ${ids.takeWhile((id) => id != 0).toList()}');

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(ids),
        [1, 77],
      );
      final embedding = await _run(_textSession, 'input_ids', inputTensor);
      print('✅ Text embedding generated for: "$text"');
      return embedding;
    } catch (e) {
      print('Error generating text embedding: $e');
      return [];
    }
  }

  /// Runs [session] with one input and returns the first output as a flat list.
  /// [background]: run the model in a separate isolate so the UI stays smooth.
  /// Only use it when runs on this session never overlap.
  static Future<List<double>> _run(
    OrtSession session,
    String inputName,
    OrtValueTensor input, {
    bool background = false,
  }) async {
    final runOptions = OrtRunOptions();
    final outputs = background
        ? (await session.runAsync(runOptions, {inputName: input}))!
        : session.run(runOptions, {inputName: input});

    // Output shape is [1, 512], so take the first (and only) row.
    final result = List<double>.from((outputs[0]!.value as List)[0]);

    input.release();
    runOptions.release();
    for (final o in outputs) {
      o?.release();
    }
    return result;
  }

  /// Cosine similarity
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0.0, normA = 0.0, normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    normA = sqrt(normA);
    normB = sqrt(normB);
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (normA * normB);
  }

  /// Reads, decodes, resizes, crops and normalizes an image.
  /// Runs inside a background isolate, so it must only use its arguments.
  static Float32List _preprocessImage(String imagePath) {
    final imageBytes = File(imagePath).readAsBytesSync();
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Failed to decode image');

    // Resize so the SHORT side is 224 (keeps the shape, no squashing)
    final resized = image.width < image.height
        ? img.copyResize(
            image,
            width: 224,
            interpolation: img.Interpolation.cubic,
          )
        : img.copyResize(
            image,
            height: 224,
            interpolation: img.Interpolation.cubic,
          );

    // Cut out the center 224x224 square
    final cropped = img.copyCrop(
      resized,
      x: (resized.width - 224) ~/ 2,
      y: (resized.height - 224) ~/ 2,
      width: 224,
      height: 224,
    );

    return _normalizeImage(cropped);
  }

  /// Converts the image to CLIP's input format: CHW order, normalized
  /// with CLIP's mean/std.
  static Float32List _normalizeImage(img.Image image) {
    const size = 224;
    const planeSize = size * size; // pixels per color plane
    final data = Float32List(3 * planeSize);
    const mean = [0.48145466, 0.4578275, 0.40821073];
    const std = [0.26862954, 0.26130258, 0.27577711];

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final pixel = image.getPixelSafe(x, y);
        final i = y * size + x; // position inside one plane
        data[0 * planeSize + i] =
            ((pixel.r / 255.0) - mean[0]) / std[0]; // red plane
        data[1 * planeSize + i] =
            ((pixel.g / 255.0) - mean[1]) / std[1]; // green plane
        data[2 * planeSize + i] =
            ((pixel.b / 255.0) - mean[2]) / std[2]; // blue plane
      }
    }
    return data;
  }
}
