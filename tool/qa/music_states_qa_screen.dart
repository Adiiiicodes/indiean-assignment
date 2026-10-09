// Development-only scenarios render the actual production Music screen.
import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/track_model.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/audio/widgets/audio_lifecycle_binding.dart';

enum MusicQaScenario { local, decoderFailureThenRetry, remote }

class MusicStatesQaScreen extends StatelessWidget {
  const MusicStatesQaScreen({required this.scenario, super.key});

  final MusicQaScenario scenario;

  @override
  Widget build(BuildContext context) {
    const catalog = AudioRepository();
    final repository = switch (scenario) {
      MusicQaScenario.local => _LocalCatalog(catalog),
      MusicQaScenario.decoderFailureThenRetry => _RetryCatalog(catalog),
      MusicQaScenario.remote => catalog,
    };
    return AudioLifecycleBinding(
      repository: repository,
      serviceFactory: () => JustAudioPlayerService(
        loadTimeout: scenario == MusicQaScenario.remote
            ? const Duration(seconds: 4)
            : const Duration(seconds: 15),
      ),
      child: const MusicScreen(),
    );
  }
}

class _LocalCatalog extends AudioRepository {
  _LocalCatalog(AudioRepository catalog)
    : _tracks = List.unmodifiable([
        for (final track in catalog.focusTracks)
          track.copyWith(source: MediaUrls.fallbackAudioAsset),
      ]);

  final List<TrackModel> _tracks;

  @override
  List<TrackModel> get focusTracks => _tracks;
}

class _RetryCatalog extends AudioRepository {
  _RetryCatalog(this.catalog);
  final AudioRepository catalog;
  bool _firstRead = true;

  @override
  List<TrackModel> get focusTracks {
    final fails = _firstRead;
    _firstRead = false;
    return List.unmodifiable([
      for (final track in catalog.focusTracks)
        track.copyWith(
          source: fails
              ? 'assets/audio/missing-music-qa.mp3'
              : MediaUrls.fallbackAudioAsset,
        ),
    ]);
  }
}
