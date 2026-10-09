# FocusDesk - Memory (living state)

## NEXT_TASK
NEXT_TASK: T01

## BUILD_CAPABILITY
unknown

## Environment

## Task Checklist
- [x] T00 - Create control files (context.md, memory.md, logs.md)
- [ ] T01 - Check and prepare the Flutter/Android toolchain
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
- Flutter SDK and Android emulator system image are missing; provision during T01 before feature work.

## Human To-Do (things the human must do after the build)

## Useful Commands
- Session started: 2026-10-09 19:30:49 IST
- Initial ETA: 10-16 hours including toolchain setup and running-app checks; revise from actual timings.
