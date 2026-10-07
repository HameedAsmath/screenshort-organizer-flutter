import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:screenshot_organizer_mobile/services/vector_math.dart';

void main() {
  test('normalize scales a vector to length 1', () {
    final v = VectorMath.normalize([3, 4]); // length 5
    expect(v[0], closeTo(0.6, 1e-9));
    expect(v[1], closeTo(0.8, 1e-9));
  });

  test('normalize leaves a zero vector alone', () {
    expect(VectorMath.normalize([0, 0]), [0, 0]);
  });

  test('dot of normalized vectors is the cosine', () {
    final a = VectorMath.normalize([1, 0]);
    final b = VectorMath.normalize([1, 1]); // 45° away from a
    expect(VectorMath.dot(a, a), closeTo(1, 1e-9)); // same direction
    expect(VectorMath.dot(a, b), closeTo(math.sqrt1_2, 1e-9)); // cos 45°
    expect(VectorMath.dot([1, 0], [0, 1]), 0); // perpendicular
  });

  test('addInto adds in place', () {
    final sum = [1.0, 2.0];
    VectorMath.addInto(sum, [10, 20]);
    expect(sum, [11, 22]);
  });
}
