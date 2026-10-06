/// Display details derived from a screenshot row, e.g. the source app and the
/// exact time, both encoded in Android screenshot file names like
/// `Screenshot_20260930-122156_GPay.png`.
class ScreenshotInfo {
  final String name;
  final String? sourceApp;
  final DateTime? takenAt;

  const ScreenshotInfo._(this.name, this.sourceApp, this.takenAt);

  static final _pattern = RegExp(
    r'^Screenshot_(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})(?:[_.](.+?))?\.\w+$',
  );

  factory ScreenshotInfo.fromRow(Map row) {
    final name = row['name'] as String? ?? '';
    final match = _pattern.firstMatch(name);
    if (match != null) {
      final p = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
      return ScreenshotInfo._(
        name,
        match.group(7),
        DateTime(p[0], p[1], p[2], p[3], p[4], p[5]),
      );
    }
    final created = DateTime.tryParse(row['createdAt'] as String? ?? '');
    return ScreenshotInfo._(name, null, created);
  }

  bool get isScreenshot => _pattern.hasMatch(name);

  /// "GPay", "Screenshot" or "Photo".
  String get title => sourceApp ?? (isScreenshot ? 'Screenshot' : 'Photo');

  /// "30 Sep 2026" (+ " · 12:21" when the time is known).
  String get dateLabel {
    final d = takenAt;
    if (d == null) return 'Unknown date';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final date = '${d.day} ${months[d.month - 1]} ${d.year}';
    if (!isScreenshot) return date;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$date · $hh:$mm';
  }
}

/// Hero tag shared by the grid tile and the details page.
String screenshotHeroTag(Map row) => 'screenshot-${row['id']}';
