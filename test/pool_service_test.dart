import 'package:flutter_test/flutter_test.dart';
import 'package:screenshot_organizer_mobile/services/pool_service.dart';
import 'package:screenshot_organizer_mobile/services/vector_math.dart';

void main() {
  // Two obvious groups: three vectors pointing "east", three pointing "north".
  final vectors = [
    [1.0, 0.1, 0.0], [0.9, 0.0, 0.1], [1.0, 0.05, 0.05], // east
    [0.0, 1.0, 0.1], [0.1, 0.9, 0.0], [0.05, 1.0, 0.0], // north
  ].map(VectorMath.normalize).toList();

  test('k-means separates two obvious groups', () {
    final a = PoolService.kMeans(vectors, 2).assignments;
    // First three together, last three together, and the two groups differ
    expect(a[0], a[1]);
    expect(a[1], a[2]);
    expect(a[3], a[4]);
    expect(a[4], a[5]);
    expect(a[0], isNot(a[3]));
  });

  test('same seed gives the same result', () {
    expect(
      PoolService.kMeans(vectors, 2, seed: 7).assignments,
      PoolService.kMeans(vectors, 2, seed: 7).assignments,
    );
  });
}
