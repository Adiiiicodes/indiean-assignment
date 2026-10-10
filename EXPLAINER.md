# FocusDesk: technical walkthrough

Use this guide to explain the implementation, then open the linked source to show the evidence. [README.md](README.md) covers installation, screenshots, commands, and the review APK. The explanations below describe the shipped code, including its limits.

## 1. The 60-second project pitch

> FocusDesk is a Flutter Android app that connects task planning to focused work. Users can create, search, filter, edit, complete, and delete local tasks, or import suggestions from a paginated public API. A task can launch a focus timer with shared music, and accepted sessions feed a progress summary. Music has a three-track playlist; video has two clearly disclosed demo clips, custom playback controls, and fullscreen playback. Profile saves theme and duration preferences and manages local account actions.
>
> I separated business operations into Cubits, repositories, and datasources, with immutable states and constructor/provider injection. Hive stores task/session JSON; SharedPreferences stores mock accounts, session, and preferences. The app handles loading, validation, empty states, errors, retries, lifecycle changes, and repeated actions. Verification includes 804 automated tests, a 100-case responsive matrix, and separate Android release QA. This is an assignment implementation: authentication is local mock auth, data is device-wide, playback is foreground-only, and the review APK uses a debug signing certificate.

## 2. Architecture walkthrough with actual files

Start at [main.dart](lib/main.dart), then [bootstrap.dart](lib/bootstrap.dart). `bootstrap()` initializes the two Hive boxes, loads preferences, creates `AppDependencies`, and calls `AuthRepository.initialize()` to seed the demo account. Saved theme/default duration are captured before the first Flutter frame. Initialization failure closes available Hive resources and presents `BootstrapErrorApp` with Retry.

[FocusDeskApp](lib/app.dart) supplies repository instances through `MultiRepositoryProvider` and feature Cubits through `MultiBlocProvider`. `AppDependencies` is the composition root: tests can replace storage, HTTP, media, or repositories without a global service locator. Provider-created Cubits are closed by their providers; dependencies supplied with `.value` retain external ownership.

```text
main -> bootstrap -> AppDependencies -> FocusDeskApp / providers
                                           |
View -> Cubit -> Repository -> Local datasource -> Hive / prefs
                         +--> Remote datasource -> Dio -> DummyJSON

AudioCubit -> AudioRepository (catalog)
           +-> AudioPlayerService -> just_audio

Cubit emits immutable state -> BlocBuilder / BlocConsumer -> View
Video widget owns its native controller and presentation state.
```

| Area | Files to open / ownership |
| --- | --- |
| Auth | [AuthCubit](lib/features/auth/cubit/auth_cubit.dart) → [AuthRepository](lib/data/repositories/auth_repository.dart) → [AuthLocalDatasource](lib/data/datasources/local/auth_local_datasource.dart). App-scoped session state. |
| Tasks | [TasksTab](lib/features/tasks/view/tasks_tab.dart), [TaskCubit](lib/features/tasks/cubit/task_cubit.dart), [TaskRepository](lib/data/repositories/task_repository.dart), [TaskLocalDatasource](lib/data/datasources/local/task_local_datasource.dart). |
| Suggested | [SuggestedView](lib/features/suggested/view/suggested_view.dart), [SuggestedCubit](lib/features/suggested/cubit/suggested_cubit.dart), [SuggestedRepository](lib/data/repositories/suggested_repository.dart), remote datasource. Imports use the same TaskCubit as My Tasks. |
| Music | [MusicScreen](lib/features/audio/view/music_screen.dart), [AudioCubit](lib/features/audio/cubit/audio_cubit.dart), [AudioRepository](lib/data/repositories/audio_repository.dart), audio service. [AudioLifecycleBinding](lib/features/audio/widgets/audio_lifecycle_binding.dart) supplies one lazy app-scoped Cubit/decoder. |
| Focus/stats | [FocusScreen](lib/features/focus/view/focus_screen.dart) owns its [TimerCubit](lib/features/focus/cubit/timer_cubit.dart). Shared [FocusRepository](lib/data/repositories/focus_repository.dart) persists sessions and reads tasks; [StatsCubit](lib/features/focus/cubit/stats_cubit.dart) supplies the summary. |
| Profile | [ProfileCubit](lib/features/profile/cubit/profile_cubit.dart) → [ProfileRepository](lib/data/repositories/profile_repository.dart); [ThemeCubit](lib/features/profile/cubit/theme_cubit.dart) and [SettingsCubit](lib/features/profile/cubit/settings_cubit.dart) use prefs. |
| Video | [VideoPlayerScreen](lib/features/video/view/video_player_screen.dart) contains [FocusVideoPlayer](lib/features/video/widgets/focus_video_player.dart); local controller state uses a pure mapper, not a business Cubit. |
| Navigation/design | [AppRouter](lib/core/router/app_router.dart), [HomeShell](lib/features/home/view/home_shell.dart), [AppTheme](lib/core/theme/app_theme.dart), [AppStrings](lib/core/constants/app_strings.dart), and [shared widgets](lib/shared/widgets). |

`HomeShell` keeps tabs mounted in an `IndexedStack`, preserving state and scroll positions. Music decoder creation and Suggested requests remain lazy on activation. Navigation changes from bottom bar to rail at 720 logical pixels. Typed route guards accept the expected `String`, `TaskModel`, or `VideoModel` arguments and safely handle invalid routes.

`_TaskSessionBinding` in `app.dart` loads tasks on a new authenticated session and resets task/suggestion/stats caches on logout. Successful task changes refresh stats; Tasks/Profile activation and accepted Focus saves also refresh them. Resetting caches does not delete device-wide saved records.

## 3. Why Cubit, and the exact Add task trace

Cubit fits these command-driven features: methods such as `add`, `pause`, or `setMode` are easy to call from widgets and test without introducing an event class for every action. Equatable states make value comparisons explicit. A `BlocBuilder` renders state; listeners handle navigation or feedback. This is a design choice, not a claim that every Flutter app needs Bloc: the video controller and form draft remain local widget state.

The public widget is `TaskFormScreen`; `_save()` and `_candidate()` belong to its private `_TaskFormScreenState`. The exact successful create path is:

1. [TasksTab._addTask](lib/features/tasks/view/tasks_tab.dart) pushes `Routes.taskForm`. Its navigation guard prevents a second form before the first frame/result.
2. [TaskFormScreen state._save](lib/features/tasks/view/task_form_screen.dart) rejects busy/discard/date-picker/pop work and calls `FormState.validate()`. [Validators](lib/core/utils/validators.dart) enforces title length 3–80 and description maximum 300.
3. `_candidate()` trims title/description. For a new task, `_draft ??= TaskModel(title: title)` retains one UUID across retries, then `copyWith` applies the fields. Editing instead copies the original task and explicitly clears a removed due date.
4. `await TaskCubit.add(candidate)` calls `_change(() => _repository.addTask(task))`, then `_run(...)`. `_run` checks `_busy`/closed state, captures `_generation`, and emits `TaskStatus.loading` with the previous task/filter state retained.
5. [TaskRepository.addTask](lib/data/repositories/task_repository.dart) calls `_mutate(() => _insert(task))`. `_mutate` serializes writes; `_insert` checks `getById(task.id)` and rejects an existing ID before writing.
6. [TaskLocalDatasource.put](lib/data/datasources/local/task_local_datasource.dart) calls `jsonEncode(task.toJson())`, then `HiveService.put(AppConstants.tasksBox, task.id, json)`.
7. [HiveService.put](lib/data/datasources/local/hive_service.dart) obtains the opened `Box<String>` and awaits `Box.put`. It converts storage failures to `StorageException`.
8. Back in `TaskCubit._run`, `TaskRepository.getTasks()` calls `TaskLocalDatasource.getTasks()`, which uses `HiveService.readAll`, decodes records, and checks stored key/model-ID consistency. The repository sorts by newest `createdAt`, then ID for ties.
9. `_run` verifies its generation is still active and emits `TaskStatus.success` with the refreshed, unmodifiable task list. Query/filters remain current; [TaskState.visibleTasks](lib/features/tasks/cubit/task_state.dart) derives the visible subset.
10. The form verifies success **and matching saved ID/fields**, then `_leave(saved)` pops the actual `TaskModel`. `TasksTab._addTask` handles success feedback; `BlocBuilder` displays the list and the app listener refreshes stats.

```text
_save -> _candidate -> TaskCubit.add -> _change -> _run (loading)
 -> TaskRepository.addTask -> _mutate -> _insert
 -> TaskLocalDatasource.put -> HiveService.put -> Box<String>.put
 -> getTasks -> HiveService.readAll -> decode/sort
 -> TaskState.success -> form verification/pop -> rebuilt TasksTab
```

Important failure case: a write can commit and the later list reread can fail. The form keeps its draft UUID and marks `_verifyCreate`; Retry first loads tasks, then updates that ID if it exists instead of creating a duplicate. Cubit generation checks stop late results updating a reset/closed view; they do not undo a write already committed to disk. Repository queues recover after failed operations.

## 4. API flow: setup, parsing, recovery, and import

[ApiClient](lib/data/datasources/remote/api_client.dart) configures injected/new Dio with `https://dummyjson.com`, JSON responses, and 10-second connect/receive timeouts. Its debug-only `_MetadataLogger` records method/path, response status, or error type; it excludes bodies, headers, and query data. Logger failures cannot interrupt requests, and release does not install this logger.

`SuggestedView` activates lazily. `SuggestedCubit.load()` → `_fetch(more: false)` → `SuggestedRepository.fetch()` → [SuggestedRemoteDatasource.fetchTodos](lib/data/datasources/remote/suggested_remote_datasource.dart) issues `GET /todos?limit=20&skip=0`.

The datasource checks HTTP 2xx even if an injected Dio accepts other statuses. [SuggestedTaskModel.fromJson](lib/data/models/suggested_task_model.dart) requires positive integer IDs/user IDs, a nonblank title, and a boolean completed flag. [SuggestedPageModel](lib/data/models/suggested_page_model.dart) validates types, counts, metadata, and unique IDs. Returned skip must match the request; a returned limit smaller than requested is valid for a clamped last page. Malformed data is a friendly invalid-response error, not an empty-success result.

[mapException](lib/core/errors/exception_mapper.dart) preserves existing `AppException`s, distinguishes Dio timeouts/network/bad-response/cancellation, gives HTTP 429 a rate-limit message, and maps `FormatException` to invalid response. Widgets show friendly Retry without raw response/exception dumps.

Pagination uses `_nextSkip = page.skip + page.todos.length`, **not** `skip + 20`. `_pageBusy` prevents overlapping fetches; `hasMore` compares actual progress with total. Cross-page IDs are deduplicated; all-duplicate/no-progress pages fail. Generation checks ignore results after reset/close. Near-bottom loading is active-gated, and a failed page waits for an explicit retry rather than looping on every scroll notification.

`SuggestedCubit.importTask()` guards the same remote ID and queues distinct imports. It waits for TaskCubit hydration, builds `suggested-<id>` through `SuggestedTaskModel.toTask()`, and verifies the local saved result. Defaults are Medium priority, no due date, API completion preserved, and `TaskSource.imported`; the visible badge says **Suggested**. Imported IDs derive from persisted task state, so deletion/Undo changes Added correctly. There are no server writes, and API `userId` provides no local account isolation. Unimported pages are not a disk offline cache.

## 5. Audio implementation deep dive

Open [audio_player_service.dart](lib/data/datasources/media/audio_player_service.dart), then [AudioCubit](lib/features/audio/cubit/audio_cubit.dart) and [MusicScreen](lib/features/audio/view/music_screen.dart).

`AudioPlayerService` isolates plugin types and exposes `positionStream`, nullable `durationStream`, `currentIndexStream`, and `playerStateStream`, plus playlist/play/pause/seek/skip/loop/dispose commands. `JustAudioPlayerService` owns `just_audio.AudioPlayer`, plugin state/error subscriptions, and a broadcast status stream. `setPlaylist()` validates tracks/index and loads `setAudioSources` with a timeout.

`mapPlayerStatus()` maps native processing plus playing/history/error into idle, loading, buffering, ready, playing, paused, completed, and error. Ready means initialized but not played; paused is distinct through `hasPlayed`. AudioCubit listens to all four streams; it bounds positions, validates indexes, resets position on an index change, and combines status with busy/error/repeat state.

Seeking has two protections. The slider uses local `_dragPosition` during a drag and commits once in `_finishSeek`; `_dragTrackId` must still match the current track. Cubit/service clamp the target to zero/known duration. Busy controls prevent overlapping commands. A native failed seek can leave its Future pending while the decoder is replaced: service `_operation()` races command completion with its recovery signal, then checks failure and releases its temporary subscription. This keeps recovery from permanently disabling controls.

The plugin's `play()` Future lasts until pause/end, so the wrapper starts it without awaiting the entire playback and catches asynchronous failure. The UI regains controls promptly. Generation/disposal checks discard stale loading/recovery results. Cubit `init()` shares an in-flight load; Retry preserves the current index and recovers paused without autoplay.

For Previous, position greater than three seconds restarts the current track; otherwise it selects the previous track. `_finishPlaylist()` pauses and selects index zero. Repeat-all can play again if the app is active; repeat-off retains completed state and offers **Replay playlist**. Status retention prevents a lifecycle pause overwriting that completion prompt.

[AudioRepository](lib/data/repositories/audio_repository.dart) supplies three immutable tracks from [MediaUrls](lib/core/constants/media_urls.dart): SoundHelix Song 1/2/3 displayed as Lo-fi Drift, Ambient Bloom, and Piano Focus. Names/moods are display aliases, not verified genres. Eligible remote failures replace the failed index with the same bundled `fallback.mp3`; measured duration is approximately 19.17 seconds despite the source sample-15s filename. Metadata can remain while fallback audio plays. If recovery fails, a friendly media error/Retry remains.

[AudioLifecycleBinding](lib/features/audio/widgets/audio_lifecycle_binding.dart) observes lifecycle without eagerly creating a decoder. On leaving `resumed`, `AudioCubit.setAppActive(false)` cancels play intent, waits for in-flight work, and pauses; a late playing event triggers another pause. Foreground return enables actions, never autoplay. Music/Focus share this player; Focus departure pauses without disposing it. `stopIfCreated()` lets logout pause/reset an existing player without creating an unused one. `AudioCubit.close()` detaches subscriptions, guards late emissions, and disposes the service; service disposal cancels plugin subscriptions and closes controllers.

Optional background audio (T48) was deliberately **skipped**. There is no media notification, lock-screen control, or background audio service.

## 6. Video implementation deep dive

[VideoRepository](lib/data/repositories/video_repository.dart) holds two immutable demo models. [VideoScreen](lib/features/video/view/video_screen.dart) opens a typed `Routes.videoPlayer`; More videos uses replacement navigation so Back returns to the library rather than every visited clip. The displayed titles describe aliases; the descriptions/demo labels disclose actual butterfly/bee nature footage.

[FocusVideoPlayer](lib/features/video/widgets/focus_video_player.dart) creates `VideoPlayerController.networkUrl` or `.asset`, attaches `_onVideoChanged`, and awaits initialization with a timeout. `_generation`/mounted checks reject stale work. Source changes release old controllers; a set of released controllers prevents duplicate disposal. Chewie is created only after successful initialization and any needed background pause.

[mapVideoViewState](lib/features/video/cubit/video_view_state.dart) is a pure function. Precedence is **error → uninitialized loading → buffering → completed → playing → ready/paused**. Completion uses explicit completion or a positive duration reached by position; a zero-duration uninitialized clip is not falsely complete. `hasPlayed` separates first-ready from paused. Nullable duration displays `--:--`; negative time clamps to zero and minutes can exceed 59.

Chewie provides the inline frame with `autoPlay: false`, `showControls: false`, and `disableFullScreenRoute: true`. [VideoPlaybackControls](lib/features/video/widgets/video_playback_controls.dart) supplies FocusDesk play/pause, seek, elapsed/total time, mute, and fullscreen controls. Loading/buffering overlay a spinner and disable commands; completion overlays Replay. Error Retry initializes the bundled `fallback.mp4` rather than repeatedly relying on a failed host. The short video sample is approximately 7.54 seconds.

Fullscreen is an app-owned route rendering the **same VideoPlayerController**, not a second decoder. Inline rendering is suppressed while fullscreen; a revision notifier updates fullscreen controls/status. [VideoOrientation](lib/features/video/utils/video_orientation.dart) serializes landscape-left/right then immersive-sticky requests. Exit restores portrait-up for compact phones or unrestricted orientations for tablets, then visible overlays in `finally`, even if orientation restoration fails. Entry/exit do not globally lock tablets. Android 16/API 36+ and large-screen policies can limit requests; native verification used API 35.

`_run` guards busy/inactive/error/loading/buffering actions; seeks clamp to duration. `WidgetsBindingObserver` pauses after pending load/action work and catches late playing events. `allowBackgroundPlayback: true` disables the plugin's automatic lifecycle resume policy so **the app can enforce pause and manual resume**, not promise background video. Disposal increments generation, removes the observer/listener, releases Chewie/video controllers, restores orientation, removes an active fullscreen route, and disposes its notifier.

## 7. Local storage decisions

[HiveService](lib/data/datasources/local/hive_service.dart) opens `Box<String>` for `tasks` and `focus_sessions`. JSON strings make persistence explicit and inspectable and avoid generated adapters for this small schema. Datasources encode/decode models and validate identities; repositories enforce ordering, duplicate rules, and serialized mutations. This is simple to explain and test, but a larger app needs explicit schema migrations, indexing, and perhaps transactional relational storage.

[PrefsService](lib/data/datasources/local/prefs_service.dart) is appropriate for small settings/session values and turns failed writes or typed-read errors into `StorageException`. Theme/duration writes are serialized and change the selected state only after successful persistence. Unsupported stored values fall back to System/25 minutes; a type/read failure is not silently treated as missing.

Mock auth stores registered-user JSON with **unsalted SHA-256** hashes and an active user ID in unencrypted preferences. SHA-256 here demonstrates equality checking; it is not a password KDF or secure production credential storage. Production auth would use a backend, properly protected tokens, server-side access rules, and account-owned data. These local accounts share all tasks/sessions on the installation; logout removes session/caches, not records.

[TimerCubit](lib/features/focus/cubit/timer_cubit.dart) measures active wall-clock segments, preserving fractions across pause/resume and avoiding countdown increases after backward-clock changes. Production durations are 15/25/45 minutes. Natural completion saves a completed session; confirmed Leave saves a partial only when active seconds exceed ten. Reset discards the unfinished session. A failed save retains the exact UUID/model; `FocusRepository.addSession()` accepts an identical stored retry, rejects a conflict, and serializes writes/read-after-write access.

Timer state is **memory-only**. Backgrounding does not explicitly pause its countdown; if the process survives, its next tick catches up elapsed time. There is no reliable background alarm/service/wakelock or process-death restoration. Paused gaps count in timestamps but not `actualSeconds`.

Stats group sessions by local `startedAt` day, count partials, floor aggregated active seconds to minutes, and compute positive-duration day streaks. Tasks done today means currently Done with today's `updatedAt`, not a separate completion timestamp. Profile Clear data queues task/session clears but is not a cross-box transaction; partial failure is reported. Accounts/session/theme/duration remain.

## 8. Testing strategy and evidence boundaries

The recorded suite has **804 passing tests**, clean formatting, and zero analyzer issues. Test value comes from failure/race coverage and realistic journeys, not just the number.

| Layer | Examples / what they establish |
| --- | --- |
| Models/remote | [Suggested datasource tests](test/data/datasources/suggested_remote_datasource_test.dart): malformed types, HTTP errors, exact skip, clamped last pages. Model tests check round trips/defaults. |
| Storage/repos | [Task repository tests](test/data/task_repository_test.dart), [Focus repository tests](test/data/focus_repository_test.dart), [timer storage flow](test/features/focus/timer_storage_flow_test.dart): real temporary Hive, disk reopen, queued writes, idempotent committed-write retry. |
| Cubits | [Audio](test/features/audio/audio_cubit_test.dart), [Timer](test/features/focus/timer_cubit_test.dart), [Tasks](test/features/tasks/task_cubit_test.dart): transitions, pending work, retry/reset/close, active-time accounting. |
| User journeys | [Task CRUD](test/features/tasks/task_crud_flow_test.dart), [shared music](test/features/audio/music_player_flow_test.dart), [Focus UI](test/features/focus/focus_screen_test.dart), and [stats](test/features/focus/stats_flow_test.dart) test actual user actions. |
| Whole app | [app_smoke_test.dart](test/app_smoke_test.dart): real app/router/Cubits/repos from Splash through login/add/details/focus completion/music/video/theme/logout. Only storage/network/decoder/clock boundaries are fake. |
| Layout/semantics | [responsive_test.dart](test/responsive_test.dart): ten screens × five sizes × scales 1.0/1.3 = 100 cases; [accessibility_test.dart](test/accessibility_test.dart): three actual-screen label/tap-target checks. Additional theme, keyboard, dialog, and reduced-motion tests. |
| Native QA | Separately verifies actual decoding, release install/restart, live API, system bars, orientation/fullscreen position, and background pause. [Screenshot notes](docs/screenshots/README.md) and [logs](logs.md) record context. |

The smoke test uses an immutable optional `FocusTimerFactory` seam in app/router and an injected clock/ticker/seconds converter. It finishes in three test seconds while production remains minutes × 60. Native timer checks exercised normal-duration start/pause/resume/qualifying partials; they did not claim a 25-minute natural completion run. Widget decoder fakes do not prove Android media behavior, and memory storage fakes do not replace real-Hive reopen tests.

Run `dart format .`, `flutter analyze`, and `flutter test` sequentially. Focused examples are `flutter test test/app_smoke_test.dart` and `flutter test test/responsive_test.dart`. Do not run generators/builds or native QA concurrently with tests. Development probes in `tool/native_qa.dart` are separate from the normal `lib/main.dart` release entry.

## 9. Likely interview questions and concise answers

1. **Why Cubit instead of full Bloc?** These features are commands with state transitions; direct methods keep the code small without an event-class layer. I would reconsider event-based Bloc for more complex event coordination.
2. **Why not put everything in setState?** Forms and video presentation use local state, but repositories/session/media/timer business operations need shared ownership and isolated tests.
3. **What does the repository add?** It owns business persistence rules, mutation queues, duplicate checks, sorting, and friendly storage failures; widgets do not manipulate Hive.
4. **Why use IndexedStack?** It retains mounted tab state and scroll position. Active flags still gate expensive Music/Suggested work; the trade-off is retained widget memory.
5. **Where is dependency injection?** `AppDependencies` composes services/repos and `app.dart` supplies repository/Cubit providers. Constructors accept controlled boundaries for tests.
6. **How does Add avoid duplicate writes?** The form keeps one UUID; repository insertion rejects an existing ID. After an uncertain write/readback, Retry loads and updates the existing draft rather than generating another ID.
7. **How are rapid actions handled?** UI/Cubit busy/navigation guards stop overlapping operations; repository write queues serialize accepted mutations. These mechanisms have distinct scopes.
8. **Can reset cancel a disk write?** No. Generation invalidation suppresses stale state emissions; already committed storage remains. Reload reconciles it.
9. **How does Undo work?** TaskCubit retains the exact deleted snapshot and repository restore preserves it while rejecting ID conflicts. UI Undo lasts six seconds and waits for other busy task work.
10. **What happens if the API fails?** A mapped friendly failure with Retry is shown; retained pages can remain. It does not erase saved local tasks or fabricate successful empty data.
11. **Why advance by returned count?** The final response may clamp its limit. Advancing by the requested 20 could skip results or misrepresent progress.
12. **How are bad API responses detected?** Strict item/page types, positive IDs, count/metadata/duplicate validation, request-skip matching, and non-progress checks.
13. **Is importing idempotent?** Deterministic `suggested-<id>` keys, saved-state verification, and per-ID/queue guards avoid duplicate local records; a committed uncertain write can reconcile on retry.
14. **Does API userId isolate accounts?** No. It is remote metadata only; local tasks/sessions are installation-wide across mock accounts.
15. **Why wrap just_audio?** Plugin types stay outside UI/state, commands/status mapping have one owner, and a fake decoder can test Cubit/journeys deterministically.
16. **Why not await plugin play until it finishes?** That Future can last the whole playback. The wrapper starts it, handles async errors, and returns promptly so pause/seek remain usable.
17. **How do you avoid seeking the wrong track?** Music records the drag's track ID and checks it at commit; index changes reset the drag. Cubit/service also bound the target.
18. **How do you avoid stream leaks?** AudioCubit owns and cancels four subscriptions; the service cancels plugin listeners and disposes the decoder/controllers. Closed/generation guards reject late callbacks.
19. **What happens at playlist completion?** It resets to track zero; repeat-all replays when active, repeat-off stays completed until explicit Replay playlist.
20. **Can audio continue in the background?** No supported background service. T48 was optional and skipped; non-resumed lifecycle pauses and return requires Play.
21. **Why Chewie if controls are custom?** It provides inline presentation, while custom controls/fullscreen give consistent state, responsive layout, and ownership. Its stock controls/route are disabled.
22. **Does fullscreen recreate the video?** No. A custom route uses the same controller and position, suppressing the inline renderer. Serialized orientation/overlay cleanup restores the session policy.
23. **Why set allowBackgroundPlayback for video?** To prevent the plugin's automatic resume policy; the widget implements its own pause-on-background/manual-resume policy. It does not enable a background-video feature.
24. **How does the timer handle delayed ticks?** It derives elapsed active time from clock segments instead of subtracting one second per callback. Paused gaps are excluded; next ticks catch up if the process survives.
25. **Can a focus session survive process death?** Saved sessions can; an active timer cannot. I would persist checkpoints and define OS/background scheduling behavior for that requirement.
26. **What if saving a session committed but reported failure?** The pending model/UUID stays fixed; an identical stored retry succeeds without a second record. Conflicting contents fail safely.
27. **How secure is auth?** It is intentionally mock auth: unsalted SHA-256 and unencrypted local preferences. Real auth needs a backend, protected token storage, expiry/revocation, and ownership checks.
28. **Are themes persisted before UI startup?** Flutter's saved mode is loaded before its first frame. Native splash follows OS theme, so it can briefly differ from a saved explicit app mode.
29. **What do 804 tests not prove?** All real devices/OS versions, native codec/network behavior through fake boundaries, production security, or store signing. Separate Android QA supplies narrower native evidence.
30. **What would you improve with more time?** Real auth/account isolation, timer restoration/background design, accurate licensed content, migrations/sync, transactional clear, completion timestamps, physical-device coverage, and production signing.

## 10. Package and SDK glossary: purpose and where

This covers every direct dependency/development package in [pubspec.yaml](pubspec.yaml). [pubspec.lock](pubspec.lock) records transitive platform implementations; those are resolved support libraries rather than additional app-level architecture choices.

| Package / SDK | What it means here / where to show it |
| --- | --- |
| Flutter SDK | Material widgets, Navigator, semantics, animations, lifecycle, SystemChrome; views, `app.dart`, video orientation. Verified Flutter 3.47.7. |
| Dart SDK | Null safety, Futures/Streams/Timer, JSON, collections; all source and `TimerCubit`. Verified Dart 3.13.5, constraint `^3.13.5`. |
| `flutter_bloc` | Cubit and provider/builder/listener widgets; feature Cubits and `app.dart`. |
| `equatable` | Value-based equality for models/states; `TaskModel`, `TaskState`, `AudioState`, API models. |
| `dio` | HTTP options, interceptor, injectable adapters; `ApiClient`, Suggested remote datasource/error mapper. |
| `hive` | Key/value `Box<String>` persistence and injected `HiveInterface`; `HiveService`, real-disk tests. |
| `hive_flutter` | `initFlutter()` integration locating app storage; `HiveService.init`. |
| `shared_preferences` | Small persisted settings/mock session/accounts; `PrefsService`, `bootstrap`, mock-pref tests. |
| `just_audio` | Native playlist/seek/loop/status decoder; `JustAudioPlayerService`, not widgets directly. |
| `video_player` | VideoPlayerController/VideoPlayer and native values; `FocusVideoPlayer`. |
| `chewie` | Inline player presentation around that controller; `FocusVideoPlayer`, custom controls/fullscreen retained. |
| `intl` | Date formatting through [AppDateUtils](lib/core/utils/date_utils.dart). |
| `uuid` | Stable new user/task/session IDs; model/auth construction. |
| `crypto` | SHA-256 in `AuthLocalDatasource`; demonstration hash comparison, not secure password storage. |
| `flutter_test` (SDK) | Unit/widget testers, pumping, finders, semantics; `test/`, whole-app and responsive flows. |
| `flutter_lints` | Baseline analysis rules in [analysis_options.yaml](analysis_options.yaml). |
| `bloc_test` | Cubit state-sequence assertions/MockCubit; focused Cubit tests and fixtures. |
| `mocktail` | Stub/verify mocked boundaries; repository/remote/widget fixtures. |
| `flutter_launcher_icons` | Generates checked-in Android launcher/adaptive resources from pubspec branding config. |
| `flutter_native_splash` | Generates Android launch/day/night/Android 12 resources; postprocessed by the branding script. |

Python/Pillow is optional tooling for [generate_app_icon.py](tool/generate_app_icon.py), not a Dart package or runtime dependency. Regeneration is Python → launcher generator → splash generator → Python `--fix-splash-themes`, sequentially; normal builds use committed resources.

## 11. Honest trade-offs and known limitations

- **Mock security/data model:** no backend, token expiry/password recovery, encrypted storage, or account ownership. All local accounts share tasks/sessions. Clear data affects the installation, not just the current user.
- **Foreground media:** background audio is skipped; no notification/lock-screen controls. App return does not autoplay. Public media availability and decoder/device support vary; fallback samples are short and can retain original metadata.
- **Demo content:** audio names/moods are SoundHelix aliases, not verified genres; video titles are aliases for nature samples, not productivity lessons. Suggested content changes externally and is not an offline disk cache.
- **Timer reliability:** active timers are in memory, no process-death restoration/background alarm guarantee. Next surviving tick catches elapsed time; Reset discards and confirmed Leave saves only qualifying partials.
- **Persistence/stats:** JSON has no explicit migration framework; complete local collections are read. Clear is not cross-box atomic. Done-today uses updatedAt as an approximation; sessions use their start day.
- **Platform scope:** Android is verified; iOS/web/desktop and broad physical-device coverage are not. Target API 36 does not mean native QA covered every API 36 orientation/system-bar restriction; QA used API 35.
- **Distribution:** the kept release APK is non-debuggable, version 1.0.0+1, min API 24/target 36, three ABIs, 59.34 MiB, but signed with an **Android Debug certificate**. It is an installable assignment review artifact, not store-ready signing/security.

Explain improvements as separate work, not completed features: production auth/per-account access, restoreable timers with defined background policy, migrations/indexing/sync/backup, dedicated completion time, licensed content, transactional clear, and release signing. The [README](README.md) contains exact setup/build commands and artifact metadata.

## 12. How to demo in three minutes

Prepare a network-connected Android device with the normal `lib/main.dart` build and speakers enabled. Start logged out; avoid an existing active focus route. Saved QA records may differ from screenshots. Use production minutes; do not claim a natural 25-minute completion inside this demo.

| Time | Actual actions / explanation |
| --- | --- |
| 0:00–0:20 | Let Splash finish. Tap **Try the demo account**, then **Log in** (`demo@focusdesk.app` / `Focus@123`). Explain local mock session persistence and the four Home tabs. |
| 0:20–0:50 | Tap **Add a task**; enter Title `Prepare interview`, a short Description, and High priority; **Save**. Open its card. Show full details, Edit if time permits, and explain the UI → Cubit → repository → Hive trace. |
| 0:50–1:25 | Tap **Start focus**, select **15 min**, turn **Play music with session** off for a deterministic quiet timer, and tap **Start**. Explain active-time accounting while it runs for at least 11 seconds. Tap **Pause**, **Resume**, then Back → **Leave**. Show the saved partial/progress; sub-minute focus can correctly display zero aggregated minutes. Back to Tasks if Details remains on top. |
| 1:25–1:45 | Open **Suggested**, wait for the first page, tap **Add** on an unimported item and show **Added**. Return to My Tasks and point out its **Suggested** badge. Explain paging/duplicate protection; if the host fails, show **Retry** honestly. |
| 1:45–2:10 | Open **Music**; tap **Play**, drag seek, tap **Next track**, then **Pause**. State that track aliases are demo metadata and Music/Focus share one decoder. If loading fails, demonstrate Retry/fallback rather than asserting remote playback. |
| 2:10–2:35 | Open **Videos**, select a **Demo clip**, tap Play, seek, enter fullscreen, exit, and pause. Show the retained position, same controller, and honest nature-clip description. |
| 2:35–3:00 | Open **Profile**, choose **Dark** and a default duration; show progress/name edit if time permits. Tap **Log out** and confirm **Log out**. Login replaces the stack, the player stops/resets, and saved task/session data remains. Finish with test/release evidence from README. |

Natural completion and **Great focus! → Yes** are demonstrated by the deterministic whole-app smoke test (or a real-duration session), not by an accelerated production build. If three minutes is strict, skip editing/extra media seeks rather than rush confirmation or hide an error.
