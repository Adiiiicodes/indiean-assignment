# FocusDesk: Mega Plan for Autonomous Build (Codex)

Goal: build, test, and package a polished Flutter Android app ("FocusDesk") that satisfies the internship assignment, with zero human intervention, by executing `prompts.txt` task by task.

Deadline context: submission is due **10 Oct 2026, 4:00 PM IST**. Everything here is ordered so the mandatory requirements are finished and packaged first, and nice-to-haves come last.

---

## 1. The product (one paragraph)

**FocusDesk** is a task manager built around focus sessions. You manage tasks (local CRUD), import suggested tasks from a public REST API (DummyJSON), start a **Focus Session** on any task (a countdown timer plus a focus music playlist), and watch short productivity videos. It includes auth, search and filter, dark/light theme, and a profile/settings screen.

## 2. The autonomous system: four control files

| File | Created by | Purpose |
|---|---|---|
| `MEGA_PLAN.md` | You (this file) | Strategy, phases, rules. Read once at start. |
| `prompts.txt` | You | The ordered task prompts (T00 to T51). The single source of work. **Never edited by Codex.** |
| `context.md` | Codex (task T00) | Stable project truth: product, stack, architecture, conventions, the **Task Protocol**, media URLs, credentials. Read before every task. |
| `memory.md` | Codex (task T00) | Living state: task checklist, `NEXT_TASK` pointer, file map, decisions, known issues, commands. This is how Codex resumes after a context reset. |
| `logs.md` | Codex (task T00) | Append-only journal: one entry per task (what was done, commands run, results, retries, blockers). |

### Why this works
- `prompts.txt` makes each unit of work small enough to finish and verify in one go.
- `context.md` keeps every prompt short: shared rules live in one place.
- `memory.md` has a `NEXT_TASK` pointer, so if the agent's context is cleared or the session restarts, it re-reads memory and continues exactly where it stopped.
- `logs.md` gives you an audit trail you can read to understand what happened and to prepare for the interview.

## 3. The execution loop (what Codex does, forever, until done)

```
bootstrap: run T00 (create context.md, memory.md, logs.md)
loop:
  1. read context.md, memory.md, tail of logs.md
  2. NEXT_TASK = value in memory.md
  3. open that task's block in prompts.txt, execute it
  4. verify (format, analyze, tests, build when the task says so)
  5. if verification fails -> fix and re-verify (max 4 attempts)
        still failing -> log BLOCKED, apply the simplest fallback, continue
  6. append entry to logs.md
  7. update memory.md (checklist, file map, decisions, NEXT_TASK)
  8. git commit with the task's commit message
  9. go to 1 (no pausing, no questions)
until NEXT_TASK = DONE
```

## 4. Phases and tasks

| Phase | Tasks | Outcome |
|---|---|---|
| 0. Bootstrap | T00-T04 | Control files, Flutter toolchain, project, deps, folders |
| 1. Core | T05-T09 | Theme, constants, validators, shared widgets, storage, routing, DI |
| 2. Auth | T10-T15 | Mock auth, splash, login, sign-up, tests |
| 3. Tasks | T16-T24 | Task model, Hive storage, repository, cubit, home, form, details, tests |
| 4. REST API | T25-T28 | Dio + DummyJSON, suggested tab, import, pagination, tests |
| 5. Audio | T29-T34 | just_audio player, all controls and states, tests |
| 6. Video | T35-T37 | Chewie player, states, fullscreen/orientation |
| 7. Profile | T38-T39 | Theme persistence, profile, logout, clear data |
| 8. Focus Session | T40-T43 | Timer, session log, stats card (the differentiator) |
| 9. Polish and Ship | T44-T48 | Responsive audit, animations, icon/splash, smoke test, **release APK**, optional background audio |
| 10. Docs and Close | T49-T51 | README, interview explainer, final QA |

The mandatory requirements are all covered by T00-T39 and T47 (APK). Focus Session, polish, and background audio come after the mandatory work so a time cut-off never costs required features.

## 5. Failure policy (so it never gets stuck)

1. Fix and retry, up to **4 attempts** per failing verification.
2. If still failing, write `BLOCKED` in `logs.md`, apply the **simplest fallback** that still meets the acceptance criteria (for example, replace a fancy widget with a plain one), and move on.
3. Never delete or weaken tests to make them pass. Fix the code.
4. Never ask the human a question. Make a reasonable assumption and record it in `memory.md` under Assumptions.
5. If the whole toolchain is unavailable (no Android SDK, no network), set `BUILD_CAPABILITY` in `memory.md` to the best available level (`full`, `analyze-and-test`, or `code-only`) and continue; tasks adapt their verification to that level (details in T01).
6. If the build or analyzer breaks and the cause is an earlier task, fix it right away and note it in the log.

## 6. Environment fallback

- **Best case:** Flutter and the Android SDK are installed or installable, so Codex builds the APK itself.
- **Middle case:** Flutter works but there is no Android SDK, so Codex runs `flutter analyze` and `flutter test`, and you build the APK yourself with `flutter build apk --release` (README documents it).
- **Worst case:** no Flutter at all, so Codex still writes the code carefully and records the exact commands you need to run in `memory.md` under "Human To-Do".

## 7. What you do (human checkpoints)

1. Put `MEGA_PLAN.md` and `prompts.txt` into an empty folder, `git init`, and open it in Codex.
2. Paste the starter prompt from `STARTER_PROMPT.txt`.
3. Come back, skim `logs.md`, run the app on a phone or emulator, and read `EXPLAINER.md` (generated by T50). The brief says you will be asked to explain every part of the code, so read it.
4. Create the GitHub repo, push, and attach the APK from `release/`. Make the repo public.

## 8. Definition of Done (whole project)

- All 7 required screens work and are connected by navigation.
- `flutter analyze` shows no errors or warnings, and `flutter test` passes.
- Release APK is in `release/` (or the human to-do is recorded).
- README is complete (overview, versions, packages, architecture, test credentials, setup).
- Audio: 3 tracks with Play, Pause, Seek, Previous, Next, position/duration, states.
- Video: Chewie player with play/pause, seek, replay, duration/position, states, fullscreen.
- Git history is clean and meaningful (one commit per task at minimum).
