# FocusDesk - Memory (living state)

## NEXT_TASK
NEXT_TASK: T22

## BUILD_CAPABILITY
full

## Environment
- NDK28.2.13676358 (r28c) and CMake3.22.1 now installed and debug-build proven. App SDK defaults min24/compile36/target36 satisfy resolved plugins.
- Host: Windows, PowerShell; timezone Asia/Calcutta.
- Git: 2.51.0.windows.2.
- Android SDK: C:\Users\DELL\AppData\Local\Android\Sdk; platforms 35, 36, 36.1 and corresponding build tools present.
- Java for Flutter/Gradle: Android Studio bundled JBR 21.0.9 at C:\Program Files\Android\Android Studio\jbr; default global Java is Corretto 25.0.3.
- ADB: 37.0.0; emulator 36.4.10.0; WHPX acceleration installed and usable.
- Native UI automation: Computer Use @oai/sky initializes/lists windows, but its occluded emulator screenshot showed the desktop. Use Android ADB screencap/pull and actual touch/text/back commands for reliable native user-flow verification; device screenshot720x1280 was visually checked.
- Flutter SDK: C:\Users\DELL\flutter; Flutter 3.47.7 stable, Dart 3.13.5, DevTools 2.60.0; stable commit abaf9c523780a608bd46686fd5e53740a07077f8 (published 2026-10-08). Android SDK and JBR configured; analytics disabled.
- Running device: emulator-5554, FocusDesk_API35, Android 15/API35/default x86_64 revision2; 720x1280 at320dpi (360x640dp), 2GB RAM/2cores, host GPU. Boot completed and launcher/shell/back/home verified.
- Flutter doctor Android toolchain passes (SDK36.1.0, Java21, all licenses accepted). PATH warnings are avoided with the session PATH line below; Visual Studio warning applies to Windows desktop only. First APK/Gradle resolution will be proven by T02.
- Bundled Python for later artifact scripts: C:\Users\DELL\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe.
- Original prompt SHA256: STARTER_PROMPT.txt A885E2421E4E672BF2C4DE994EE74419CB1CFD623B829FE4E87F3A864F58C809; MEGA_PLAN.md 51F49C4F859523C34445C8761C1B7871BB0E832E7B77AD3C0C2D87AA1F14A2C3; prompts.txt 587ED5202BEB8DFE1727557D85E78748B34F3F16E77B7926B05932005B407083.

## Task Checklist
- [x] T00 - Create control files (context.md, memory.md, logs.md)
- [x] T01 - Check and prepare the Flutter/Android toolchain
- [x] T02 - Create the Flutter project and Android basics
- [x] T03 - Add dependencies
- [x] T04 - Folder structure and lint rules
- [x] T05 - Theme system (colors, text styles, light/dark)
- [x] T06 - Constants, validators, exceptions, utils
- [x] T07 - Shared reusable widgets
- [x] T08 - Local storage services (Hive + SharedPreferences)
- [x] T09 - Routing and screen placeholders
- [x] T10 - User model, auth datasource and repository (mock)
- [x] T11 - AuthCubit and states
- [x] T12 - Splash screen with session redirect
- [x] T13 - Login screen
- [x] T14 - Sign-up screen
- [x] T15 - Auth flow integration check
- [x] T16 - Task model and priority enum
- [x] T17 - Task local datasource and repository
- [x] T18 - TaskCubit with search, filter and undo
- [x] T19 - Home shell with bottom navigation
- [x] T20 - Tasks tab UI (header, search, filters, list)
- [x] T21 - TaskCard widget with Hero and checkbox
- [ ] T22 - Add/Edit task form screen
- [ ] T23 - Task details screen
- [ ] T24 - Wire up tasks end-to-end and test
- [ ] T25 - Suggested tasks: model, Dio client, remote datasource
- [ ] T26 - Suggested repository and cubit (pagination + refresh)
- [ ] T27 - Suggested tab UI and tab bar in Tasks
- [ ] T28 - API flow verification
- [ ] T29 - Verify media URLs and add local fallbacks
- [ ] T30 - Track model and AudioPlayerService (just_audio wrapper)
- [ ] T31 - AudioCubit
- [ ] T32 - Music player screen UI
- [ ] T33 - Audio states, errors and Android config
- [ ] T34 - Audio integration test with fake service
- [ ] T35 - Video player screen (Chewie, network)
- [ ] T36 - Video states: buffering, completion/replay, error/retry, time labels
- [ ] T37 - Fullscreen and orientation handling
- [ ] T38 - ThemeCubit and settings persistence
- [ ] T39 - Profile / Settings screen
- [ ] T40 - Focus session model, datasource, repository
- [ ] T41 - TimerCubit
- [ ] T42 - Focus Session screen UI
- [ ] T43 - Stats card on Home and Profile
- [ ] T44 - Responsive and accessibility audit
- [ ] T45 - Motion polish, app icon and native splash
- [ ] T46 - Full app smoke test
- [ ] T47 - Release APK build and verification
- [ ] T48 - OPTIONAL stretch: background audio and media notification
- [ ] T49 - README.md
- [ ] T50 - EXPLAINER.md (interview preparation)
- [ ] T51 - Final QA, cleanup and final report

## File Map
- features/tasks/widgets/task_card.dart: themed rounded interactive card, built-in animated checkbox, Hero title, completion strike, description and wrapped priority/date/import badges; test/features/tasks/task_card_test.dart10 cases; TasksTab uses it within existing swipe/undo.
- features/tasks/view/tasks_tab.dart: time/name greeting,400ms search, combined horizontal filters, lazy sliver list, refresh/loading/empty/error/add routes and swipe/undo retry; test/features/tasks/tasks_tab_test.dart covers20 cases. Shared EmptyView compact option keeps phone CTA visible.
- features/home/view/home_shell.dart: four IndexedStack tabs, phone NavigationBar, rail at720dp, preserved state across resize and Back-to-Tasks handling; HomeScreen retains auth/logout; media/profile placeholders support embedded bodies and standalone routes; test/features/home/home_shell_test.dart.
- features/tasks/cubit/{task_state,task_cubit}.dart: immutable task state, combined synchronous search/filters, CRUD/undo, friendly errors and stale-operation reset guards; app.dart binds shared task loading/reset to auth identity; test/features/tasks/{task_cubit,task_session}_test.dart and native Cubit QA.
- data/datasources/local/task_local_datasource.dart and data/repositories/task_repository.dart: strict-identity Hive JSON task CRUD, newest-first reads, serialized mutations, exact undo snapshots and friendly storage errors; test/data/task_repository_test.dart and tool/qa/task_repository_qa_screen.dart.
- data/models/task_model.dart: immutable UUID task, priority/source enums, tolerant JSON and calendar helpers; test/data/task_model_test.dart; tool/qa/task_model_qa_screen.dart native model probe.
- test/features/auth/auth_flow_test.dart: real-repository first-launch/signup/logout/demo-login and fresh-session restore; temporary Home auth logout action enables actual production flow before Home shell task.
- features/auth/view/signup_screen.dart: keyboard-safe validated signup, confirmation, duplicate feedback, loading/back guards and correct Login/Home navigation; test/features/auth/signup_screen_test.dart.
- features/auth/view/login_screen.dart: validated keyboard-safe Login, demo autofill, loading/failure feedback and guarded stack-clearing navigation; test/features/auth/login_screen_test.dart.
- features/auth/view/splash_screen.dart: animated themed brand, minimum display timer and session redirect; dedicated timing/disposal/widget checks.
- features/auth/cubit/{auth_state,auth_cubit}.dart: shared app-level authentication transitions, friendly failures and lifecycle/duplicate guards; test/features/auth and native Cubit QA gallery.
- lib/data/models/user_model.dart: immutable JSON/Equatable user; local/auth_local_datasource.dart: seeded accounts/hash/session; repositories/auth_repository.dart: validated injectable-delay auth operations.
- test/data/{user_model,auth_repository}_test.dart and tool/qa/auth_repository_qa_screen.dart: model/auth tests and actual native account flow.
- lib/core/router/{routes,app_router}.dart: ten named routes, argument forwarding, fade/slide transitions and safe fallback; ten feature screen placeholders; test/core/router_test.dart and native routing gallery.
- lib/bootstrap.dart: binding/storage initialization, AppDependencies and friendly startup Retry; app root provides dependencies via RepositoryProvider.
- lib/data/datasources/local/{prefs_service,hive_service}.dart: injectable friendly storage wrappers; test/data covers disk persistence, failures and startup.
- tool/qa/storage_qa_screen.dart: actual native write/cold-reopen/read/delete verification.
- lib/shared/widgets/: themed buttons/fields, loading/empty/error views, section headers, priority chips and snackbar/undo helper; test/shared covers controls and state actions in both themes.
- tool/qa/shared_qa_screen.dart: native actual-touch gallery for reusable components.
- lib/core/constants/: AppStrings UI copy, AppConstants settings/storage/validation/network values, MediaUrls declared sources.
- lib/core/utils/: validators, disposable Debouncer and local-calendar/date/duration formatting.
- lib/core/errors/: sealed friendly exceptions and transport/storage mapping.
- test/core/: validators, date/debounce, exception mappings and themes; tool/qa/core_qa_screen.dart: actual native input/probe surface.
- lib/core/theme/{app_colors,app_text_styles,app_theme}.dart: shared semantic palette, typography, Material3 light/dark components and system-bar styling.
- test/core/theme_test.dart: system theme selection and narrow/large-text control tests.
- lib/core/: themes, constants, utilities, errors and router.
- lib/data/: models, local/remote datasources and repositories.
- lib/features/{auth,tasks,suggested,audio,video,profile,focus,home}/{cubit,view,widgets}: feature state/UI/components.
- lib/shared/widgets/: common UI; empty planned folders tracked with .gitkeep until filled.
- analysis_options.yaml: Flutter lints plus const, avoid_print and package-import rules.
- pubspec.yaml/lock: resolved runtime/test/media/storage packages; assets/audio, video, images prepared.
- tool/native_qa.dart: separate actual-touch native dependency verification entrypoint; no production debug controls.
- lib/main.dart: production entrypoint; lib/app.dart: FocusDeskApp root; test/widget_test.dart: app smoke test.
- android/: Android com.focusdesk.focusdesk configuration; main manifest Internet permission and cleartext disabled.
- .gitignore: generated Flutter exclusions, with release APK deliverables allowed.

## Decisions
- TasksTab uses CustomScrollView with SliverList.builder (equivalent lazy builder) so greeting/search/filters can scroll above a small keyboard. Compact empty content fits first phone fold; keyboard metrics observer hides FAB while typing because outer Home Scaffold consumes MediaQuery insets. Undo remains retryable after failed restore. Native slow/failing first reads exist only in development QA launcher and use actual Hive afterward.
- TaskModel defaults: medium priority/local source/pending/empty description/Untitled task; invalid calendar dates do not normalize silently. Both due getters apply to pending tasks in local calendar days. copyWith(clearDueDate:true) explicitly clears the nullable date; clock helper methods enable deterministic tests.
- Auth architecture: bootstrap seeds AuthRepository; one app-level AuthCubit remains across named routes. Splash owns session lookup; current-screen Login/Signup/Home listeners perform stack-clearing auth navigation. Home placeholder has a real Logout action for T15, retained when replacing shell until Profile provides final controls. Tests inject repository delay zero; production600ms stays. Native cold-reopen verifies actual prefs, not mock storage.
- Mock passwords stored only as SHA-256 through crypto3.0.7; this is assignment demo authentication, not production security. Email normalized; input password kept exact; corrupt accounts fail without overwriting. Default auth delay600ms, injectable zero in tests.
- Use current Flutter ThemeData APIs (CardThemeData, InputDecorationThemeData, AppBarThemeData). Native QA root switches through normal widget state; avoid calling runApp again from gesture callbacks. System-bar contrast is explicitly coordinated with the scheme.
- Added SDK integration_test dev dependency for real Android flows. tool/native_qa.dart is a development-only entrypoint for touching real components before production screens exist; production lib/main.dart never imports it. Foundation probes and ordinary app checks are recorded separately.
- Gradle uses the already-cached 9.3.1 bin distribution; heap 3GB/workers4 fit the host with its emulator. NDK27.1.12297006 passed the scaffold build; T03 added JNI native compilation through path_provider, so app now uses default NDK28.2.13676358.
- User instructions take precedence over prompt fallbacks: every completed feature must pass automated verification and an actual running-app user flow before committing and advancing. No unverified feature counts as complete.
- Git author is local-only: Adiiiicodes <nalawadeaditya017@gmail.com>. Plain prompt-specified commit subjects, no co-author or AI attribution trailers.
- Use Windows PowerShell equivalents for the shell commands in prompts. Keep tasks strictly sequential; agents may assist within the current task.
- Progress heartbeat: focusdesk-30-minute-progress-and-eta, every 30 minutes in this chat. Report completed/remaining out of 52, pace, remaining duration and completion time in Asia/Calcutta; pause on completion.

## Assumptions
- The actual folder named flutter-app is the user's Flutter app folder. Source prompts remain under prompts/ and are never edited.
- The user authorized SDK installation, emulator provisioning, all implementation and local test/commit steps without further clarification.

## Known Issues / BLOCKED items
- No active blockers. Completed task automated/native evidence is in logs.md.

## Human To-Do (things the human must do after the build)

## Useful Commands
- Session started: 2026-10-09 19:30:49 IST
- Initial ETA: 10-16 hours including toolchain setup and running-app checks; revise from actual timings.


- Flutter commands use --no-version-check to avoid an unnecessary first-run fetch of historical SDK Git tags.
- Session PATH: $env:PATH = 'C:\Users\DELL\flutter\bin;C:\Users\DELL\AppData\Local\Android\Sdk\platform-tools;' + $env:PATH
- Android app cache command: flutter --no-version-check precache --android_gen_snapshot --android_maven --universal
- SDK source confirms broad --android also fetches internal Flutter build binaries. Supported narrower flags skip about525MB of remaining internal-only archives; no cache stamps modified. Actual Maven/Gradle build remains verified in T02.
- ADB executable: C:\Users\DELL\AppData\Local\Android\Sdk\platform-tools\adb.exe
- Bundled artifact Python/Pillow verified: Python3.12.14.





- Resident native QA tty session35753, target tool/native_qa.dart, PID13828; production app open, Demo logged in. Three marker tasks remain for form verification: Gamma imported/pending; Beta high/done/pastdue; Alpha low/pending/today. Actual device/font/night mode restored. Use --no-dds; lowercase r reload succeeds, uppercase R intermittently loses connection leaving prior app state; cold build/run resets launcher. Actual accounts/probes remain emulator-only. Task state loads once per identity and logout/replacement invalidates old reads.














