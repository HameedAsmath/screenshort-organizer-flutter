import 'dart:math' as math;

/// Small helpers for working with embedding vectors.
class VectorMath {
  /// Returns a copy of [v] scaled to length 1. A zero vector stays zero.
  static List<double> normalize(List<double> v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final length = math.sqrt(sum);
    if (length == 0) return List<double>.from(v);
    return [for (final x in v) x / length];
  }

  /// Dot product. For normalized vectors this equals cosine similarity.
  static double dot(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  /// Adds [v] into [target] in place (target += v).
  static void addInto(List<double> target, List<double> v) {
    for (var i = 0; i < target.length; i++) {
      target[i] += v[i];
    }
  }
}
