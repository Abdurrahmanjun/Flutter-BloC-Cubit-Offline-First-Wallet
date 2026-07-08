# 💳 Offline-First Wallet — Flutter + Native Android Biometrics

A clean-architecture mobile wallet demonstrating **offline-first data**, **safe money movement**, and a **hand-written Flutter↔Kotlin biometric bridge** — the kind of app a fintech client actually needs.

> **Why this repo is different:** most Flutter wallet demos stop at the UI. This one crosses the native boundary (a custom `MethodChannel` to Android `BiometricPrompt`, no `local_auth` plugin) and treats money with the correctness a bank expects (integer cents, atomic DB writes, double-spend protection).

---

## ✨ Highlights

- **🔐 Native biometric unlock** — Dart calls a custom `MethodChannel` into Kotlin `BiometricPrompt`. Written by hand to prove native Android capability, not just plugin usage. → [`biometric_authenticator.dart`](lib/core/platform/biometric_authenticator.dart) · [`MainActivity.kt`](android/app/src/main/kotlin/com/abdurrahman/wallet/MainActivity.kt)
- **📴 Offline-first** — the local SQLite DB is the single source of truth. Transfers are durable even with no network; unsynced rows are flagged `pending sync` for later reconciliation.
- **💸 Double-spend safe** — the transfer flow uses **Bloc with `droppable()`** so a double-tap on *Send* can never fire two transfers. A test proves the use case runs exactly once.
- **🧮 Money done right** — amounts are integer **cents**, never `double`. Balance debit + transaction insert happen in one atomic SQLite transaction.
- **🧱 Clean architecture** — `domain` (entities, use cases, repo interfaces) / `data` (sources, models, repo impl) / `presentation` (Cubit + Bloc). Dependencies point inward only.

## 🧠 State management — deliberate, not default

| Flow | Tool | Why |
|------|------|-----|
| Biometric unlock, dashboard load | **Cubit** | Linear flows; no event log needed |
| Money transfer | **Bloc + `droppable()`** | Event layer gives concurrency control → no double spend |

This "Cubit for the simple 80%, Bloc for the risky 20%" split is a decision I can defend in an interview.

## 🏗️ Architecture

```
presentation ─▶ domain ◀─ data
  Cubit/Bloc      usecases     repo impl
                  entities     local (sqflite)  ◀─ source of truth
                  repo iface   remote (mock API)
        core/platform ─▶ MethodChannel ─▶ Kotlin BiometricPrompt
```

## ▶️ Run it

This project pins its Flutter SDK with **[FVM](https://fvm.app)** (see [`.fvmrc`](.fvmrc)). Install the pinned version once, then prefix Flutter commands with `fvm`:

```bash
dart pub global activate fvm   # if you don't have FVM
fvm install                    # installs the Flutter version pinned in .fvmrc

fvm flutter create .           # generate platform folders once
# add to android/app/build.gradle:
#   minSdkVersion 23
#   implementation "androidx.biometric:biometric:1.1.0"
# then restore the provided MainActivity.kt + AndroidManifest.xml
fvm flutter pub get
fvm flutter run
```

> Running `fvm use` in the project points your IDE at `.fvm/flutter_sdk`.

Demo account is seeded automatically (clean-room fake data — no real PII).

## ✅ Tests

```bash
fvm flutter test
```

Covers the transfer state machine, the `droppable()` double-tap guarantee, and use-case validation.

## 📦 Tech

Flutter · Dart · flutter_bloc · bloc_concurrency · get_it (DI) · dartz · sqflite · Kotlin (BiometricPrompt) · GitHub Actions CI

---

*Built by Abdurrahman Jundullah M — mobile engineer (Flutter + native Android), 8+ years, fintech/banking background.*
