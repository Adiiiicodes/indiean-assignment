import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';

/// Owns one lazy player for every route and observes lifecycle without reading it.
class AudioLifecycleBinding extends StatefulWidget {
  const AudioLifecycleBinding({
    required this.repository,
    required this.serviceFactory,
    required this.child,
    super.key,
  });

  final AudioRepository repository;
  final AudioPlayerService Function() serviceFactory;
  final Widget child;

  /// Logout stops an existing decoder without initializing an unused playlist.
  static Future<void> stopIfCreated(BuildContext context) =>
      context
          .findAncestorStateOfType<_AudioLifecycleBindingState>()
          ?._audio
          ?.stopForLogout() ??
      Future<void>.value();

  @override
  State<AudioLifecycleBinding> createState() => _AudioLifecycleBindingState();
}

class _AudioLifecycleBindingState extends State<AudioLifecycleBinding>
    with WidgetsBindingObserver {
  AudioCubit? _audio;
  bool get _active {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final audio = _audio;
    if (audio != null) {
      unawaited(audio.setAppActive(state == AppLifecycleState.resumed));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audio = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocProvider<AudioCubit>(
    create: (_) {
      final audio = _audio = AudioCubit(
        widget.repository,
        widget.serviceFactory(),
      );
      unawaited(audio.setAppActive(_active));
      return audio;
    },
    child: widget.child,
  );
}
