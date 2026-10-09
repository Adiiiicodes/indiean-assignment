import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/data/models/track_model.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';

void main() {
  test(
    'catalog preserves all verified sources and distinct artwork metadata',
    () {
      final tracks = const AudioRepository().focusTracks;
      expect(tracks, hasLength(3));
      expect(tracks.map((track) => track.source), MediaUrls.audio);
      expect(tracks.map((track) => track.title), [
        AppStrings.trackOne,
        AppStrings.trackTwo,
        AppStrings.trackThree,
      ]);
      expect(tracks.map((track) => track.mood), [
        AppStrings.moodLofi,
        AppStrings.moodAmbient,
        AppStrings.moodPiano,
      ]);
      expect(tracks.map((track) => track.id).toSet(), hasLength(3));
      expect(tracks.map((track) => track.artworkIcon).toSet(), hasLength(3));
      for (final track in tracks) {
        expect(track.artist, AppStrings.trackArtist);
        expect(track.artworkColors, hasLength(2));
        expect(
          track.artworkColors.every(
            (color) => color >= 0 && color <= 0xffffffff,
          ),
          isTrue,
        );
        expect(track.isAsset, isFalse);
        expect(Uri.parse(track.source).scheme, 'https');
        expect(track.durationHint, isNull);
      }
      expect(const AudioRepository().getTracks(), same(tracks));
      expect(() => tracks.clear(), throwsUnsupportedError);
    },
  );

  test('track owns immutable artwork and compares metadata by value', () {
    final colors = [0xFF7353BA, 0xFFAA87DF];
    final track = TrackModel(
      id: 'test-track',
      title: 'Track title',
      artist: 'Artist',
      source: MediaUrls.fallbackAudioAsset,
      durationHint: const Duration(seconds: 19),
      artworkColors: colors,
      artworkIcon: 'waves',
      mood: 'Ambient',
    );
    colors.clear();
    expect(track.artworkColors, [0xFF7353BA, 0xFFAA87DF]);
    expect(() => track.artworkColors.add(0), throwsUnsupportedError);
    expect(track.isAsset, isTrue);
    expect(track.copyWith(), track);
    expect(track.copyWith(mood: 'Piano'), isNot(track));
    expect(track.copyWith(artworkColors: [0, 1]), isNot(track));
    expect(
      track.copyWith(durationHint: const Duration(seconds: 20)),
      isNot(track),
    );
  });

  test(
    'fallback source copy preserves identity and can clear uncertain duration',
    () {
      final original = const AudioRepository().focusTracks.first.copyWith(
        durationHint: const Duration(minutes: 5),
      );
      final fallback = original.copyWith(
        source: MediaUrls.fallbackAudioAsset,
        clearDurationHint: true,
      );
      expect(fallback.id, original.id);
      expect(fallback.title, original.title);
      expect(fallback.artist, original.artist);
      expect(fallback.mood, original.mood);
      expect(fallback.artworkIcon, original.artworkIcon);
      expect(fallback.artworkColors, original.artworkColors);
      expect(fallback.isAsset, isTrue);
      expect(fallback.durationHint, isNull);
      expect(original.isAsset, isFalse);
      expect(original.durationHint, const Duration(minutes: 5));
      expect(fallback, isNot(original));
    },
  );
}
