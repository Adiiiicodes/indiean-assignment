// Development-only probe. Production main.dart never imports this file.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/track_model.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';

class AudioServiceQaScreen extends StatefulWidget {
  const AudioServiceQaScreen({super.key, this.service, this.repository});

  final AudioPlayerService? service;
  final AudioRepository? repository;

  @override
  State<AudioServiceQaScreen> createState() => _AudioServiceQaScreenState();
}

class _AudioServiceQaScreenState extends State<AudioServiceQaScreen> {
  late final AudioPlayerService _service;
  late final AudioRepository _repository;
  final _subscriptions = <StreamSubscription<Object?>>[];
  AppPlayerStatus _status = AppPlayerStatus.idle;
  List<TrackModel> _tracks = const [];
  int? _index;
  int _positionSeconds = 0;
  int? _durationSeconds;
  bool _loaded = false;
  bool _repeat = false;
  bool _closing = false;
  String? _busy;
  String? _error;
  String _result = 'Load remote tracks or the three local fallback tracks.';
  String _sources = 'None';

  bool get _live => mounted && !_closing;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? JustAudioPlayerService();
    _repository = widget.repository ?? const AudioRepository();
    _subscriptions.addAll([
      _service.playerStateStream.listen((status) {
        if (_live && status != _status) setState(() => _status = status);
      }, onError: _streamError),
      _service.currentIndexStream.listen((index) {
        if (_live && index != _index) setState(() => _index = index);
      }, onError: _streamError),
      _service.positionStream.listen((position) {
        final seconds = position.inSeconds;
        if (_live && seconds != _positionSeconds) {
          setState(() => _positionSeconds = seconds);
        }
      }, onError: _streamError),
      _service.durationStream.listen((duration) {
        final seconds = duration?.inSeconds;
        if (_live && seconds != _durationSeconds) {
          setState(() => _durationSeconds = seconds);
        }
      }, onError: _streamError),
    ]);
  }

  void _streamError(Object error) {
    if (!_live) return;
    setState(() => _error = mapException(error).message);
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (!_live || _busy != null) return;
    setState(() {
      _busy = label;
      _error = null;
      _result = 'Running: $label';
    });
    try {
      await action();
      if (_live) setState(() => _result = 'PASS: $label');
    } catch (error) {
      if (_live) {
        setState(() {
          _error = mapException(error).message;
          _result = 'ERROR: $label';
        });
      }
    } finally {
      if (_live) setState(() => _busy = null);
    }
  }

  Future<void> _load({required bool local}) async {
    final tracks = _repository.focusTracks;
    final playlist = local
        ? [
            for (final track in tracks)
              track.copyWith(source: MediaUrls.fallbackAudioAsset),
          ]
        : tracks;
    setState(() => _loaded = false);
    await _service.setPlaylist(playlist, initialIndex: 0);
    if (!_live) return;
    setState(() {
      _tracks = playlist;
      _loaded = true;
      _sources = local ? 'Local assets' : 'Remote with local fallback';
    });
  }

  Future<void> _toggleRepeat() async {
    final next = !_repeat;
    await _service.setLoopMode(
      next ? AppAudioLoopMode.all : AppAudioLoopMode.off,
    );
    if (_live) setState(() => _repeat = next);
  }

  String _time(int? seconds) {
    if (seconds == null) return '--:--';
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _button(
    String label,
    Future<void> Function() action, {
    bool requiresPlaylist = true,
  }) => AppButton(
    label: label,
    fullWidth: false,
    variant: AppButtonVariant.outlined,
    isLoading: _busy == label,
    onPressed: _busy != null || (requiresPlaylist && !_loaded)
        ? null
        : () => unawaited(_run(label, action)),
  );

  Future<void> _close() async {
    try {
      await Future.wait(
        _subscriptions.map((subscription) => subscription.cancel()),
      );
    } catch (_) {
      // Continue closing the player even if a subscription cannot cancel.
    } finally {
      try {
        await _service.dispose();
      } catch (_) {
        // The probe is already gone; disposal must not leave an unhandled Future.
      }
    }
  }

  @override
  void dispose() {
    _closing = true;
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    final current = index != null && index >= 0 && index < _tracks.length
        ? _tracks[index]
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Audio service')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _button(
                  'Load playlist',
                  () => _load(local: false),
                  requiresPlaylist: false,
                ),
                _button(
                  'Load local playlist',
                  () => _load(local: true),
                  requiresPlaylist: false,
                ),
                _button('Play', _service.play),
                _button('Pause', _service.pause),
                _button(
                  'Seek 5s',
                  () => _service.seek(const Duration(seconds: 5)),
                ),
                _button('Next', _service.next),
                _button('Previous', _service.previous),
                _button('Select third', () => _service.skipTo(2)),
                _button(_repeat ? 'Repeat: all' : 'Repeat: off', _toggleRepeat),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Status: ${_status.name}',
              key: const ValueKey('audio-service-status'),
            ),
            Text('Index: ${index ?? '-'} / Tracks: ${_tracks.length}'),
            Text(
              'Position: ${_time(_positionSeconds)} / Duration: ${_time(_durationSeconds)}',
            ),
            Text('Requested sources: $_sources'),
            if (current != null) ...[
              const SizedBox(height: 8),
              Text('${current.title} · ${current.artist}'),
              Text('ID: ${current.id} / Mood: ${current.mood}'),
            ],
            const SizedBox(height: 12),
            Text(_result, key: const ValueKey('audio-service-result')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Back closes the streams and player. Local tracks share one bundled clip.',
            ),
          ],
        ),
      ),
    );
  }
}
