import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/features/video/utils/video_orientation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late VideoOrientation orientation;

  setUp(() {
    calls = [];
    orientation = VideoOrientation();
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

  void expectEnter(int offset) {
    expect(calls[offset].method, 'SystemChrome.setPreferredOrientations');
    expect(calls[offset].arguments, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
    expect(calls[offset + 1].method, 'SystemChrome.setEnabledSystemUIMode');
    expect(calls[offset + 1].arguments, 'SystemUiMode.immersiveSticky');
  }

  void expectExit(int offset) {
    expect(calls[offset].method, 'SystemChrome.setPreferredOrientations');
    expect(calls[offset].arguments, ['DeviceOrientation.portraitUp']);
    expect(calls[offset + 1].method, 'SystemChrome.setEnabledSystemUIOverlays');
    expect(calls[offset + 1].arguments, [
      'SystemUiOverlay.top',
      'SystemUiOverlay.bottom',
    ]);
  }

  test('construction leaves app and tablet orientation policy untouched', () {
    expect(calls, isEmpty);
  });

  test(
    'enter requests both landscape directions before immersive mode',
    () async {
      await orientation.enterFullscreen();
      expect(calls, hasLength(2));
      expectEnter(0);
    },
  );

  test(
    'exit restores portrait up before both visible system overlays',
    () async {
      await orientation.exitFullscreen();
      expect(calls, hasLength(2));
      expectExit(0);
    },
  );

  test(
    'tablet exit defers orientation to the OS and restores both overlays',
    () async {
      await orientation.exitFullscreen(restorePortrait: false);
      expect(calls, hasLength(2));
      expect(calls.first.method, 'SystemChrome.setPreferredOrientations');
      expect(calls.first.arguments, isEmpty);
      expect(calls.last.method, 'SystemChrome.setEnabledSystemUIOverlays');
      expect(calls.last.arguments, [
        'SystemUiOverlay.top',
        'SystemUiOverlay.bottom',
      ]);
    },
  );

  test(
    'rapid enter and exit wait for pending platform work in order',
    () async {
      final gate = Completer<void>();
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        if (calls.length == 1) await gate.future;
        return null;
      });
      final entering = orientation.enterFullscreen();
      final exiting = orientation.exitFullscreen();
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));
      gate.complete();
      await Future.wait([entering, exiting]);
      expect(calls, hasLength(4));
      expectEnter(0);
      expectExit(2);
    },
  );

  test('failed entry is reported and does not block queued cleanup', () async {
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      if (call.arguments == 'SystemUiMode.immersiveSticky') {
        throw PlatformException(code: 'unsupported-mode');
      }
      return null;
    });
    final entering = orientation.enterFullscreen();
    final failure = expectLater(entering, throwsA(isA<PlatformException>()));
    final exiting = orientation.exitFullscreen();
    await failure;
    await exiting;
    expect(calls, hasLength(4));
    expectEnter(0);
    expectExit(2);
  });

  test(
    'failed portrait restoration still restores overlays and reports failure',
    () async {
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          throw PlatformException(code: 'orientation-failed');
        }
        return null;
      });
      await expectLater(
        orientation.exitFullscreen(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, hasLength(2));
      expectExit(0);
    },
  );

  test('failed overlay restoration remains visible to the caller', () async {
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      if (call.method == 'SystemChrome.setEnabledSystemUIOverlays') {
        throw PlatformException(code: 'overlays-failed');
      }
      return null;
    });
    await expectLater(
      orientation.exitFullscreen(),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, hasLength(2));
    expectExit(0);
  });

  test(
    'session can reenter after restoring its previous fullscreen request',
    () async {
      await orientation.enterFullscreen();
      await orientation.exitFullscreen();
      await orientation.enterFullscreen();
      expect(calls, hasLength(6));
      expectEnter(0);
      expectExit(2);
      expectEnter(4);
    },
  );
}
