# Native app screenshots

These PNGs are unchanged Android screenshots from the verified FocusDesk release
APK during T47, on 10 October 2026. They show Android 15 / API 35 on the
`FocusDesk_API35` emulator: 360 × 640 logical pixels, 720 × 1280 physical pixels,
text scale 1.0. Fullscreen is 1280 × 720 physical pixels.

The sample account name, tasks and statistics are local QA data on the emulator.
They are not seeded into the APK. A fresh installation seeds only the demo account.
The profile name is editable; the fresh account starts as “Demo User”.

| File | State shown |
| --- | --- |
| `login.png` | Dark Login after confirmed logout and a cold restart |
| `tasks.png` | A live API import in My Tasks, with a Suggested badge |
| `suggested.png` | First page of the live DummyJSON feed |
| `focus.png` | Normal 25-minute focus session paused at 24:45; music switch off |
| `music.png` | Remote SoundHelix track decoded, ready and paused at zero |
| `videos.png` | Two-item demo video library, first card in view |
| `video-player.png` | Remote butterfly clip paused at 00:01 after fullscreen exit |
| `fullscreen.png` | Same decoder and 00:01 position in landscape fullscreen |
| `profile.png` | Profile, appearance and default-duration controls |

Phone screens scroll; each image shows the visible viewport, not all content at
once. Video titles are app display names for short public nature demos. They are
not instructional videos. Music display names are aliases for SoundHelix samples.

To replace these with your own device screenshots, navigate to a settled app state,
capture a PNG, and keep the names used by the main README. For example:

```sh
adb shell screencap -p /sdcard/focusdesk-screen.png
adb pull /sdcard/focusdesk-screen.png docs/screenshots/tasks.png
```

Capture only after builds and automated tests finish. Review every image for
loading indicators, keyboard or system overlays before using it in a submission.
