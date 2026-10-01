import 'dart:typed_data';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:ort/ort.dart';

class EmbeddingService {
  static const int EMBEDDING_DIM = 512;
  static late Session _imageSession;
  static late Session _textSession;
  static bool _initialized = false;

  /// Initialize ORT sessions
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      print('🔄 Loading CLIP models...');

      // Load image encoder
      final imageModel = await rootBundle.load('assets/clip_image.onnx');
      _imageSession = await Session.builder().commitFromMemory(
        imageModel.buffer.asUint8List(),
      );
      print('✅ Image model loaded');

      // Load text encoder
      final textModel = await rootBundle.load('assets/clip_text.onnx');
      _textSession = await Session.builder().commitFromMemory(
        textModel.buffer.asUint8List(),
      );
      print('✅ Text model loaded');

      _initialized = true;
    } catch (e) {
      print('❌ Error loading models: $e');
      rethrow;
    }
  }

  /// Generate embedding from image file
  static Future<List<double>> generateImageEmbedding(String imagePath) async {
    try {
      if (!_initialized) await initialize();

      final file = File(imagePath);
      final imageBytes = await file.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) throw Exception('Failed to decode image');

      // Resize to 224x224
      final resized = img.copyResize(image, width: 224, height: 224);

      // Normalize to [-1, 1]
      final normalized = _normalizeImage(resized);

      // Run inference
      final inputTensor = Tensor.fromArrayF32(
        data: normalized,
        shape: [1, 3, 224, 224],
      );

      final output = await _imageSession.run(
        inputValues: {'pixel_values': inputTensor},
      );

      // Extract embeddings
      final embedding = output['image_embeds']?.data as List<double>;
      print('✅ Image embedding generated (dim: ${embedding.length})');
      return embedding;
    } catch (e) {
      print('Error generating image embedding: $e');
      return List<double>.filled(EMBEDDING_DIM, 0.0);
    }
  }

  /// Generate embedding from text
  static Future<List<double>> generateTextEmbedding(String text) async {
    try {
      if (!_initialized) await initialize();

      // Simple tokenization
      final tokens = _tokenizeText(text);
      final padded = List<double>.filled(77, 0.0);
      for (int i = 0; i < min(tokens.length, 77); i++) {
        padded[i] = tokens[i].toDouble();
      }

      final inputTensor = Tensor.fromArrayF32(data: padded, shape: [1, 77]);

      final output = await _textSession.run(
        inputValues: {'input_ids': inputTensor},
      );

      final embedding = output['text_embeds']?.data as List<double>;
      print('✅ Text embedding generated for: "$text"');
      return embedding;
    } catch (e) {
      print('Error generating text embedding: $e');
      return List<double>.filled(EMBEDDING_DIM, 0.0);
    }
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

  /// Normalize image [-1, 1]
  static Float32List _normalizeImage(img.Image image) {
    final data = Float32List(3 * 224 * 224);
    int idx = 0;
    const mean = [0.48145466, 0.4578275, 0.40821073];
    const std = [0.26862954, 0.26130258, 0.27577711];

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixelSafe(x, y);
        data[idx++] = ((pixel.r.toInt() / 255.0) - mean[0]) / std[0];
        data[idx++] = ((pixel.g.toInt() / 255.0) - mean[1]) / std[1];
        data[idx++] = ((pixel.b.toInt() / 255.0) - mean[2]) / std[2];
      }
    }
    return data;
  }

  /// Simple tokenizer
  static List<int> _tokenizeText(String text) {
    final words = text.toLowerCase().split(RegExp(r'[^\w]+'));
    return words
        .where((w) => w.isNotEmpty)
        .map((w) => w.hashCode.abs() % 49408)
        .toList();
  }
}
