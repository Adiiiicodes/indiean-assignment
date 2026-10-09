import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/track_model.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';

class _Player extends Mock implements AudioPlayer {}

TrackModel _track(String id, {bool asset = false}) => TrackModel(
  id: id,
  title: 'Track $id',
  artist: 'FocusDesk',
  source: asset ? 'assets/audio/$id.mp3' : 'https://example.com/$id.mp3',
);

TypeMatcher<MediaException> _friendlyError() => isA<MediaException>()
    .having((error) => error.message, 'message', AppStrings.mediaError)
    .having(
      (error) => error.toString(),
      'private plugin detail',
      isNot(contains('private-player-detail')),
    );

void main() {
  group('pure player status mapping', () {
    for (final entry in {
      ProcessingState.idle: AppPlayerStatus.idle,
      ProcessingState.loading: AppPlayerStatus.loading,
      ProcessingState.buffering: AppPlayerStatus.buffering,
      ProcessingState.completed: AppPlayerStatus.completed,
    }.entries) {
      test('${entry.key.name} takes precedence over the playing flag', () {
        for (final playing in [false, true]) {
          for (final hasPlayed in [false, true]) {
            expect(
              mapPlayerStatus(entry.key, playing, hasPlayed: hasPlayed),
              entry.value,
            );
          }
        }
      });
    }

    test('first loaded and stopped ready state is ready', () {
      expect(
        mapPlayerStatus(ProcessingState.ready, false),
        AppPlayerStatus.ready,
      );
    });

    test('ready becomes playing regardless of earlier playback history', () {
      for (final hasPlayed in [false, true]) {
        expect(
          mapPlayerStatus(ProcessingState.ready, true, hasPlayed: hasPlayed),
          AppPlayerStatus.playing,
        );
      }
    });

    test('stopped ready state after playback is paused', () {
      expect(
        mapPlayerStatus(ProcessingState.ready, false, hasPlayed: true),
        AppPlayerStatus.paused,
      );
    });

    test('explicit failure dominates every processing and playback state', () {
      for (final processing in ProcessingState.values) {
        for (final playing in [false, true]) {
          expect(
            mapPlayerStatus(
              processing,
              playing,
              hasPlayed: true,
              hasError: true,
            ),
            AppPlayerStatus.error,
          );
        }
      }
    });
  });

  group('injected just_audio wrapper', () {
    late _Player player;
    late StreamController<PlayerState> playerStates;
    late StreamController<PlayerException> playerErrors;
    late JustAudioPlayerService service;

    setUpAll(() {
      registerFallbackValue(<AudioSource>[]);
      registerFallbackValue(Duration.zero);
      registerFallbackValue(LoopMode.off);
    });

    setUp(() {
      player = _Player();
      playerStates = StreamController<PlayerState>.broadcast();
      playerErrors = StreamController<PlayerException>.broadcast();
      when(() => player.playerStateStream)
          .thenAnswer((_) => playerStates.stream);
      when(() => player.errorStream).thenAnswer((_) => playerErrors.stream);
      when(() => player.processingState).thenReturn(ProcessingState.ready);
      when(() => player.playing).thenReturn(false);
      when(() => player.currentIndex).thenReturn(0);
      when(() => player.duration).thenReturn(const Duration(seconds: 10));
      when(() => player.positionStream)
          .thenAnswer((_) => Stream.value(Duration.zero));
      when(() => player.durationStream)
          .thenAnswer((_) => Stream.value(const Duration(seconds: 10)));
      when(() => player.currentIndexStream).thenAnswer((_) => Stream.value(0));
      when(() => player.pause()).thenAnswer((_) async {});
      when(() => player.play()).thenAnswer((_) async {});
      when(() => player.dispose()).thenAnswer((_) async {});
      when(() => player.seek(any(), index: any(named: 'index')))
          .thenAnswer((_) async {});
      when(() => player.seekToNext()).thenAnswer((_) async {});
      when(() => player.seekToPrevious()).thenAnswer((_) async {});
      when(() => player.setLoopMode(any())).thenAnswer((_) async {});
      when(
        () => player.setAudioSources(
          any(),
          initialIndex: any(named: 'initialIndex'),
          initialPosition: any(named: 'initialPosition'),
        ),
      ).thenAnswer((_) async => const Duration(seconds: 10));
      service = JustAudioPlayerService(player: player);
    });

    tearDown(() async {
      await service.dispose();
      await playerStates.close();
      await playerErrors.close();
    });

    test(
      'remote failure replaces only the selected index with local audio',
      () async {
        final sources = <List<AudioSource>>[];
        final indices = <int?>[];
        when(
          () => player.setAudioSources(
            any(),
            initialIndex: any(named: 'initialIndex'),
            initialPosition: any(named: 'initialPosition'),
          ),
        ).thenAnswer((invocation) async {
          sources.add(
            invocation.positionalArguments.first as List<AudioSource>,
          );
          indices.add(invocation.namedArguments[#initialIndex] as int?);
          if (sources.length == 1) {
            throw PlayerException(0, 'private-player-detail', 1);
          }
          return const Duration(seconds: 10);
        });
        await service.setPlaylist([
          _track('one'),
          _track('two'),
        ], initialIndex: 1);
        expect(indices, [1, 1]);
        expect(sources, hasLength(2));
        expect((sources.first[0] as UriAudioSource).uri.scheme, 'https');
        expect((sources.first[1] as UriAudioSource).uri.scheme, 'https');
        expect((sources.last[0] as UriAudioSource).uri.scheme, 'https');
        final recovered = sources.last[1] as UriAudioSource;
        expect(recovered.uri.scheme, 'asset');
        expect(recovered.uri.path, '/${MediaUrls.fallbackAudioAsset}');
        expect(recovered.tag, 'two');
        expect(await service.playerStateStream.first, AppPlayerStatus.ready);
      },
    );

    test(
      'later indexed playback error recovers once and then fails safely',
      () async {
        final sources = <List<AudioSource>>[];
        when(
          () => player.setAudioSources(
            any(),
            initialIndex: any(named: 'initialIndex'),
            initialPosition: any(named: 'initialPosition'),
          ),
        ).thenAnswer((invocation) async {
          sources.add(
            invocation.positionalArguments.first as List<AudioSource>,
          );
          return const Duration(seconds: 10);
        });
        await service.setPlaylist([_track('one'), _track('two')]);
        playerErrors.add(PlayerException(0, 'private-player-detail', 1));
        await Future<void>.delayed(Duration.zero);
        expect(sources, hasLength(2));
        expect((sources.last[0] as UriAudioSource).uri.scheme, 'https');
        expect((sources.last[1] as UriAudioSource).uri.scheme, 'asset');
        expect(await service.playerStateStream.first, AppPlayerStatus.ready);
        playerErrors.add(PlayerException(0, 'private-player-detail', 1));
        await Future<void>.delayed(Duration.zero);
        expect(sources, hasLength(2));
        expect(await service.playerStateStream.first, AppPlayerStatus.error);
      },
    );

    test(
      'recovered decoder releases Next while the original seek stays pending',
      () async {
        final pendingSeek = Completer<void>();
        final sources = <List<AudioSource>>[];
        final indices = <int?>[];
        addTearDown(() {
          if (!pendingSeek.isCompleted) pendingSeek.complete();
        });
        when(() => player.seekToNext()).thenAnswer((_) => pendingSeek.future);
        when(
          () => player.setAudioSources(
            any(),
            initialIndex: any(named: 'initialIndex'),
            initialPosition: any(named: 'initialPosition'),
          ),
        ).thenAnswer((invocation) async {
          sources.add(
            invocation.positionalArguments.first as List<AudioSource>,
          );
          indices.add(invocation.namedArguments[#initialIndex] as int?);
          return const Duration(seconds: 10);
        });
        await service.setPlaylist([_track('one'), _track('two')]);
        final next = service.next();
        playerErrors.add(PlayerException(0, 'private-player-detail', 1));
        await next.timeout(const Duration(seconds: 1));
        expect(pendingSeek.isCompleted, isFalse);
        expect(indices, [0, 1]);
        expect(sources, hasLength(2));
        expect((sources.last[0] as UriAudioSource).uri.scheme, 'https');
        expect((sources.last[1] as UriAudioSource).uri.scheme, 'asset');
        expect(await service.playerStateStream.first, AppPlayerStatus.ready);
        await service.play();
        verify(() => player.play()).called(1);
        pendingSeek.complete();
      },
    );

    test(
      'failed decoder recovery releases pending Next with a friendly error',
      () async {
        final pendingSeek = Completer<void>();
        addTearDown(() {
          if (!pendingSeek.isCompleted) pendingSeek.complete();
        });
        when(() => player.seekToNext()).thenAnswer((_) => pendingSeek.future);
        var loads = 0;
        when(
          () => player.setAudioSources(
            any(),
            initialIndex: any(named: 'initialIndex'),
            initialPosition: any(named: 'initialPosition'),
          ),
        ).thenAnswer((_) async {
          loads++;
          if (loads > 1) throw PlayerException(0, 'private-player-detail', 1);
          return const Duration(seconds: 10);
        });
        await service.setPlaylist([_track('one'), _track('two')]);
        final next = service.next();
        playerErrors.add(PlayerException(0, 'private-player-detail', 1));
        await expectLater(
          next.timeout(const Duration(seconds: 1)),
          throwsA(_friendlyError()),
        );
        expect(pendingSeek.isCompleted, isFalse);
        expect(loads, 2);
        expect(await service.playerStateStream.first, AppPlayerStatus.error);
        await expectLater(service.play(), throwsA(_friendlyError()));
        pendingSeek.complete();
      },
    );

    test(
      'asset failure cannot recurse and exposes only a friendly error',
      () async {
        when(
          () => player.setAudioSources(
            any(),
            initialIndex: any(named: 'initialIndex'),
            initialPosition: any(named: 'initialPosition'),
          ),
        ).thenThrow(PlayerException(0, 'private-player-detail', 0));
        await expectLater(
          service.setPlaylist([_track('local', asset: true)]),
          throwsA(_friendlyError()),
        );
        verify(
          () => player.setAudioSources(
            any(),
            initialIndex: 0,
            initialPosition: Duration.zero,
          ),
        ).called(1);
        expect(await service.playerStateStream.first, AppPlayerStatus.error);
      },
    );

    test(
      'invalid playlists and absent playlist controls are rejected',
      () async {
        await expectLater(service.setPlaylist([]), throwsA(_friendlyError()));
        await expectLater(
          service.setPlaylist([_track('one')], initialIndex: -1),
          throwsA(_friendlyError()),
        );
        await expectLater(
          service.setPlaylist([_track('one')], initialIndex: 1),
          throwsA(_friendlyError()),
        );
        await expectLater(service.play(), throwsA(_friendlyError()));
        await expectLater(
          service.seek(Duration.zero),
          throwsA(_friendlyError()),
        );
        verifyNever(
          () => player.setAudioSources(
            any(),
            initialIndex: any(named: 'initialIndex'),
            initialPosition: any(named: 'initialPosition'),
          ),
        );
      },
    );

    test(
      'seek clamps bounds and indexed, adjacent and loop controls delegate',
      () async {
        await service.setPlaylist([_track('one'), _track('two')]);
        await service.seek(const Duration(seconds: -2));
        await service.seek(const Duration(seconds: 20));
        await service.seek(const Duration(seconds: 4));
        await service.skipTo(1);
        await service.next();
        await service.previous();
        await service.setLoopMode(AppAudioLoopMode.all);
        await service.setLoopMode(AppAudioLoopMode.off);
        verify(() => player.seek(Duration.zero)).called(1);
        verify(() => player.seek(const Duration(seconds: 10))).called(1);
        verify(() => player.seek(const Duration(seconds: 4))).called(1);
        verify(() => player.seek(Duration.zero, index: 1)).called(1);
        verify(() => player.seekToNext()).called(1);
        verify(() => player.seekToPrevious()).called(1);
        verify(() => player.setLoopMode(LoopMode.all)).called(1);
        verify(() => player.setLoopMode(LoopMode.off)).called(1);
        await expectLater(service.skipTo(2), throwsA(_friendlyError()));
        await expectLater(service.skipTo(-1), throwsA(_friendlyError()));
      },
    );

    test('play returns while native playback remains pending and replays completion', () async {
      final playback = Completer<void>();
      when(() => player.play()).thenAnswer((_) => playback.future);
      addTearDown(() {
        if (!playback.isCompleted) playback.complete();
      });
      await service.setPlaylist([_track('one')]);
      when(() => player.processingState).thenReturn(ProcessingState.completed);
      await service.play().timeout(const Duration(seconds: 1));
      expect(playback.isCompleted, isFalse);
      verify(() => player.seek(Duration.zero)).called(1);
      verify(() => player.play()).called(1);
      playback.complete();
    });

    test('superseded load failure cannot damage a newer playlist', () async {
      final oldLoad = Completer<Duration?>();
      var calls = 0;
      when(
        () => player.setAudioSources(
          any(),
          initialIndex: any(named: 'initialIndex'),
          initialPosition: any(named: 'initialPosition'),
        ),
      ).thenAnswer((_) {
        calls++;
        return calls == 1
            ? oldLoad.future
            : Future.value(const Duration(seconds: 10));
      });
      final oldOperation = service.setPlaylist([_track('old')]);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      await service.setPlaylist([_track('new')]);
      oldLoad.completeError(PlayerException(0, 'private-player-detail', 0));
      await oldOperation;
      expect(calls, 2);
      expect(await service.playerStateStream.first, AppPlayerStatus.ready);
      await service.play();
      verify(() => player.play()).called(1);
    });

    test('late load failure after disposal does not retry or throw', () async {
      final pending = Completer<Duration?>();
      when(
        () => player.setAudioSources(
          any(),
          initialIndex: any(named: 'initialIndex'),
          initialPosition: any(named: 'initialPosition'),
        ),
      ).thenAnswer((_) => pending.future);
      final loading = service.setPlaylist([_track('one')]);
      await Future<void>.delayed(Duration.zero);
      await service.dispose();
      pending.completeError(PlayerException(0, 'private-player-detail', 0));
      await loading;
      verify(
        () => player.setAudioSources(
          any(),
          initialIndex: 0,
          initialPosition: Duration.zero,
        ),
      ).called(1);
      verify(() => player.dispose()).called(1);
    });

    test(
      'dispose cancels player subscriptions exactly once and rejects controls',
      () async {
        await service.setPlaylist([_track('one')]);
        expect(playerStates.hasListener, isTrue);
        expect(playerErrors.hasListener, isTrue);
        await service.dispose();
        await service.dispose();
        expect(playerStates.hasListener, isFalse);
        expect(playerErrors.hasListener, isFalse);
        verify(() => player.dispose()).called(1);
        await expectLater(service.play(), throwsA(_friendlyError()));
        await expectLater(service.pause(), throwsA(_friendlyError()));
        await expectLater(
          service.setPlaylist([_track('one')]),
          throwsA(_friendlyError()),
        );
      },
    );
  });
}
