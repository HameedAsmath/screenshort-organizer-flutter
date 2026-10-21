import 'package:flutter_test/flutter_test.dart';
import 'package:shotnest/ui/screenshot_info.dart';

void main() {
  test('reads source app and time from an Android screenshot name', () {
    final info = ScreenshotInfo.fromRow({
      'name': 'Screenshot_20260930-122156_GPay.png',
    });
    expect(info.sourceApp, 'GPay');
    expect(info.takenAt, DateTime(2026, 9, 30, 12, 21, 56));
    expect(info.title, 'GPay');
  });

  test('older names use a dot before the app', () {
    final info = ScreenshotInfo.fromRow({
      'name': 'Screenshot_20251024-122221.MakeMyTrip.png',
    });
    expect(info.sourceApp, 'MakeMyTrip');
  });

  test('photos fall back to createdAt', () {
    final info = ScreenshotInfo.fromRow({
      'name': '1000146879.jpg',
      'createdAt': '2026-09-30',
    });
    expect(info.sourceApp, isNull);
    expect(info.title, 'Photo');
    expect(info.takenAt, DateTime(2026, 9, 30));
  });
}
