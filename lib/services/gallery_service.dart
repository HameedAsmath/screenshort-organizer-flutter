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

  /// Finds the album whose name contains "screenshot" (any case).
  static Future<AssetPathEntity?> findScreenshotsAlbum() async {
    if (!await requestPermission()) return null;

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );

    for (final album in albums) {
      if (album.name.toLowerCase().contains('screenshot')) {
        return album;
      }
    }
    return null;
  }

  /// Returns every screenshot on the phone, newest first.
  static Future<List<AssetEntity>> getAllScreenshots() async {
    final album = await findScreenshotsAlbum();
    if (album == null) {
      print('❌ Screenshots album not found');
      return [];
    }

    final count = await album.assetCountAsync;
    final assets = await album.getAssetListRange(start: 0, end: count);
    print('📸 Found ${assets.length} screenshots');

    return assets;
  }
}
