import 'package:photo_manager/photo_manager.dart';

class GalleryService {
  /// Asks the user for permission to read photos. Returns true if allowed.
  static Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image, // only photos, not videos or audio
          mediaLocation: false, // we don't need GPS location of photos
        ),
      ),
    );
    print('📷 Gallery permission: $state');
    return state.hasAccess;
  }

  /// Temporary: prints every photo album and how many photos it has.
  static Future<void> debugListAlbums() async {
    if (!await requestPermission()) {
      print('❌ No gallery permission');
      return;
    }

    final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    for (final album in albums) {
      print('📁 ${album.name}: ${await album.assetCountAsync} photos');
    }
  }
}
