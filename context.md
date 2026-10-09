# FocusDesk - Context (stable truth; read before every task)

## Product
FocusDesk is a task manager built around focus sessions. Users manage tasks (local CRUD), import suggested tasks from a public API (DummyJSON), start a Focus Session on a task (countdown timer + focus music), and watch short productivity videos. Built as an internship technical assignment (Flutter, Android). Pitch: "FocusDesk helps you finish tasks by turning each one into a focus session: pick a task, start a timer, get a soundtrack, and track what you completed."

## Assignment requirements (must all be satisfied)
Auth (login/sign-up with validation, mocked), Home list with search/filter, REST API via Dio, local CRUD, consistent state management (flutter_bloc Cubit), navigation across auth/home/details/add-edit/media/profile, local storage, loading/success/validation/empty/error states, responsive UI without overflow on common Android sizes. Audio player screen: 3 tracks, play, pause, seek, previous, next, position and duration, title/artwork, states loading/playing/paused/completed/error. Video player screen: at least 1 video, play/pause, seek/progress, replay, duration and position, portrait OK, fullscreen bonus, states loading/buffering/completed/error. Centralized theme/colors/text styles, model classes with JSON parsing, null-safety, clean folders, exception handling, meaningful git commits, README, installable APK. Bonus targeted: dark/light theme, fullscreen video, debounced search, pull-to-refresh, pagination, repository pattern and DI, unit/widget tests, background audio (optional, late).

## Stack (do not swap packages without logging a decision)
State: flutter_bloc + equatable (one Cubit per feature). Network: dio. Local storage: hive + hive_flutter (tasks and focus sessions, stored as JSON strings in boxes, NO code generation) and shared_preferences (session, users, theme, settings). Audio: just_audio. Video: video_player + chewie. Misc: intl, uuid. Dev: bloc_test, mocktail, flutter_launcher_icons, flutter_native_splash. Dependency injection: plain constructor injection through RepositoryProvider/BlocProvider (no get_it). Routing: named routes via a central AppRouter (onGenerateRoute). Add packages with `flutter pub add` (do not hard-pin versions manually).

## Architecture
lib/
  core/ { theme/ (app_colors.dart, app_text_styles.dart, app_theme.dart), constants/ (app_strings.dart, app_constants.dart, media_urls.dart), utils/ (validators.dart, debouncer.dart, date_utils.dart), errors/ (app_exception.dart, failure mapping), router/ (app_router.dart, routes.dart) }
  data/ { models/, datasources/ { local/, remote/ }, repositories/ }
  features/ { auth, tasks, suggested, audio, video, profile, focus, home }  each with cubit/ (if needed), view/, widgets/
  shared/widgets/ (AppButton, AppTextField, EmptyView, ErrorView, LoadingView, SectionHeader, PriorityChip ...)
  main.dart, app.dart
Rules: UI never touches datasources directly; UI -> Cubit -> Repository -> Datasource. Repositories and services are abstract-friendly so tests can use fakes. Audio goes through an AudioPlayerService wrapper (interface + just_audio implementation).

## Conventions
Null-safe Dart, small files, readable names, no hard-coded colors/text styles/strings in widgets (use core/theme and core/constants), const constructors where possible, no print() (use debugPrint sparingly), all async calls wrapped with error handling that maps to AppException. Material 3, seed color indigo/violet, 16px card radius, light and dark themes. Every screen handles loading, empty, error, and success. Use SafeArea, Expanded/Flexible, SingleChildScrollView, and LayoutBuilder so nothing overflows at 320x568 up to tablets, and at text scale 1.3.

## Test credentials (mock auth)
Seeded demo user: demo@focusdesk.app / Focus@123 (name: Demo User). Sign-up stores new users locally in shared_preferences (mock only, not secure; document this in the README).

## Media (verify with curl -I before relying on them; log results)
Audio (3 tracks): https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3 ("Lo-fi Drift"), https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3 ("Ambient Bloom"), https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3 ("Piano Focus"). Titles are display names only.
Video: https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4 and https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4 (display names "Deep Work Basics", "Beat Procrastination"). If any URL fails, find an alternative public https sample and log it.
Fallbacks: bundle 1 small local audio and 1 small local video in assets/ if downloading is possible.
REST API: https://dummyjson.com/todos?limit=20&skip=0 returns {"todos":[{"id":1,"todo":"...","completed":false,"userId":1}],"total":254,"skip":0,"limit":20}.

## TASK PROTOCOL (applies to every task in prompts.txt)
1. Read context.md, memory.md, tail of logs.md. NEXT_TASK in memory.md says which task to run.
2. Locate that task's block in prompts.txt and execute it fully. Stay in scope.
3. Verify: `dart format .`, `flutter analyze` (must have 0 errors and 0 warnings; fix infos when cheap), `flutter test` (all pass), plus any task-specific verification. Adapt to BUILD_CAPABILITY in memory.md.
4. On failure: diagnose, fix, re-verify, up to 4 attempts. Then log BLOCKED, choose the simplest fallback that still meets the acceptance criteria, and continue. Never weaken or delete tests just to pass. Never loop forever.
5. Append to logs.md using the log format below.
6. Update memory.md: tick the checklist, update File Map, Decisions, Assumptions, Known Issues, and set NEXT_TASK to the following task (or DONE).
7. Commit: `git add -A && git commit -m "<task COMMIT message>"`.
8. Immediately continue to the next task. Never ask the human questions or wait for approval; make reasonable assumptions and record them in memory.md.
9. Never edit prompts.txt or MEGA_PLAN.md. Never put secrets in the repo.

## Log entry format (logs.md, append only)
### [T##] <title> - <STATUS: DONE | DONE_WITH_NOTES | BLOCKED>
- Time: <timestamp>
- Summary: what was built/changed (2-5 lines)
- Files: created/modified list
- Commands & results: key commands with pass/fail
- Retries: number and what fixed it
- Notes/Assumptions/Next: anything relevant

## Definition of done (project)
All 7 screens working and connected; analyze clean; tests passing; release APK built into release/ (or Human To-Do recorded); README complete; audio and video features per requirements; clean git history.
