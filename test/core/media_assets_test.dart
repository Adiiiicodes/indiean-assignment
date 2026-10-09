import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/media_urls.dart';

const _mib = 1024 * 1024;

bool _hasMp3Header(Uint8List bytes) {
  final id3 = bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33;
  final frame =
      bytes[0] == 0xff &&
      bytes[1] & 0xe0 == 0xe0 &&
      bytes[1] & 0x18 != 0x08 &&
      bytes[1] & 0x06 != 0 &&
      bytes[2] & 0xf0 != 0 &&
      bytes[2] & 0xf0 != 0xf0;
  return id3 || frame;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fallback media is packaged with valid headers and bounded size',
    () async {
      final audio = await rootBundle.load(MediaUrls.fallbackAudioAsset);
      final video = await rootBundle.load(MediaUrls.fallbackVideoAsset);
      expect(audio.lengthInBytes, greaterThan(10));
      expect(audio.lengthInBytes, lessThanOrEqualTo(6 * _mib));
      expect(video.lengthInBytes, greaterThan(12));
      expect(video.lengthInBytes, lessThanOrEqualTo(6 * _mib));
      final audioBytes = audio.buffer.asUint8List(
        audio.offsetInBytes,
        audio.lengthInBytes,
      );
      final videoBytes = video.buffer.asUint8List(
        video.offsetInBytes,
        video.lengthInBytes,
      );
      expect(
        _hasMp3Header(audioBytes),
        isTrue,
        reason: 'MP3 ID3 or frame header',
      );
      expect(videoBytes.sublist(4, 8), [0x66, 0x74, 0x79, 0x70]);
      expect(video.getUint32(0), greaterThanOrEqualTo(8));
      expect(video.getUint32(0), lessThanOrEqualTo(video.lengthInBytes));

      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets().where(
        (asset) => asset.startsWith('assets/'),
      );
      expect(assets, contains(MediaUrls.fallbackAudioAsset));
      expect(assets, contains(MediaUrls.fallbackVideoAsset));
      var totalBytes = 0;
      for (final asset in assets) {
        totalBytes += (await rootBundle.load(asset)).lengthInBytes;
      }
      expect(totalBytes, lessThan(15 * _mib));
    },
  );
}
