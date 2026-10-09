# FocusDesk - Memory (living state)

## NEXT_TASK
NEXT_TASK: T02

## BUILD_CAPABILITY
full

## Environment
- Host: Windows, PowerShell; timezone Asia/Calcutta.
- Git: 2.51.0.windows.2.
- Android SDK: C:\Users\DELL\AppData\Local\Android\Sdk; platforms 35, 36, 36.1 and corresponding build tools present.
- Java for Flutter/Gradle: Android Studio bundled JBR 21.0.9 at C:\Program Files\Android\Android Studio\jbr; default global Java is Corretto 25.0.3.
- ADB: 37.0.0; emulator 36.4.10.0; WHPX acceleration installed and usable.
- Native UI automation: Computer Use @oai/sky initializes and lists windows successfully.
- Flutter SDK: C:\Users\DELL\flutter; Flutter 3.47.7 stable, Dart 3.13.5, DevTools 2.60.0; stable commit abaf9c523780a608bd46686fd5e53740a07077f8 (published 2026-10-08). Android SDK and JBR configured; analytics disabled.
- Running device: emulator-5554, FocusDesk_API35, Android 15/API35/default x86_64 revision2; 720x1280 at320dpi (360x640dp), 2GB RAM/2cores, host GPU. Boot completed and launcher/shell/back/home verified.
- Flutter doctor Android toolchain passes (SDK36.1.0, Java21, all licenses accepted). PATH warnings are avoided with the session PATH line below; Visual Studio warning applies to Windows desktop only. First APK/Gradle resolution will be proven by T02.
- Bundled Python for later artifact scripts: C:\Users\DELL\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe.
- Original prompt SHA256: STARTER_PROMPT.txt A885E2421E4E672BF2C4DE994EE74419CB1CFD623B829FE4E87F3A864F58C809; MEGA_PLAN.md 51F49C4F859523C34445C8761C1B7871BB0E832E7B77AD3C0C2D87AA1F14A2C3; prompts.txt 587ED5202BEB8DFE1727557D85E78748B34F3F16E77B7926B05932005B407083.

## Task Checklist
- [x] T00 - Create control files (context.md, memory.md, logs.md)
- [x] T01 - Check and prepare the Flutter/Android toolchain
- [ ] T02 - Create the Flutter project and Android basics
- [ ] T03 - Add dependencies
- [ ] T04 - Folder structure and lint rules
- [ ] T05 - Theme system (colors, text styles, light/dark)
- [ ] T06 - Constants, validators, exceptions, utils
- [ ] T07 - Shared reusable widgets
- [ ] T08 - Local storage services (Hive + SharedPreferences)
- [ ] T09 - Routing and screen placeholders
- [ ] T10 - User model, auth datasource and repository (mock)
- [ ] T11 - AuthCubit and states
- [ ] T12 - Splash screen with session redirect
- [ ] T13 - Login screen
- [ ] T14 - Sign-up screen
- [ ] T15 - Auth flow integration check
- [ ] T16 - Task model and priority enum
- [ ] T17 - Task local datasource and repository
- [ ] T18 - TaskCubit with search, filter and undo
- [ ] T19 - Home shell with bottom navigation
- [ ] T20 - Tasks tab UI (header, search, filters, list)
- [ ] T21 - TaskCard widget with Hero and checkbox
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

## Decisions
- User instructions take precedence over prompt fallbacks: every completed feature must pass automated verification and an actual running-app user flow before committing and advancing. No unverified feature counts as complete.
- Git author is local-only: Adiiiicodes <nalawadeaditya017@gmail.com>. Plain prompt-specified commit subjects, no co-author or AI attribution trailers.
- Use Windows PowerShell equivalents for the shell commands in prompts. Keep tasks strictly sequential; agents may assist within the current task.
- Progress heartbeat: focusdesk-30-minute-progress-and-eta, every 30 minutes in this chat. Report completed/remaining out of 52, pace, remaining duration and completion time in Asia/Calcutta; pause on completion.

## Assumptions
- The actual folder named flutter-app is the user's Flutter app folder. Source prompts remain under prompts/ and are never edited.
- The user authorized SDK installation, emulator provisioning, all implementation and local test/commit steps without further clarification.

## Known Issues / BLOCKED items
- No active blockers. First debug APK and actual app launch are the T02 completion gate.

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
