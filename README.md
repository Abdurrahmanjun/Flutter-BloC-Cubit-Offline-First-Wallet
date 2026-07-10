# 💳 Offline-First Wallet — Flutter + Native Android Biometrics

A clean-architecture mobile wallet demonstrating **offline-first data**, **safe money movement**, and a **hand-written Flutter↔Kotlin biometric bridge**

> **Why this repo is different:** most Flutter wallet demos stop at the UI. This one crosses the native boundary (a custom `MethodChannel` to Android `BiometricPrompt`, no `local_auth` plugin) and treats money with the correctness a bank expects (integer cents, atomic DB writes, double-spend protection).

---

## 📱 Screenshots

Captured on a physical Android device (Samsung Galaxy A55, Android 16).

| Biometric unlock | Dashboard (light) | Dashboard (dark) |
|:---:|:---:|:---:|
| <img src="assets/screenshots/01_auth.png" width="240" alt="Native biometric unlock screen" /> | <img src="assets/screenshots/02_dashboard_light.png" width="240" alt="Dashboard in light theme" /> | <img src="assets/screenshots/03_dashboard_dark.png" width="240" alt="Dashboard in dark theme" /> |

| Send money | Payment sent (offline) |
|:---:|:---:|
| <img src="assets/screenshots/04_transfer.png" width="240" alt="Send money screen with amount and recipient" /> | <img src="assets/screenshots/05_success.png" width="240" alt="Payment sent, queued offline for sync" /> |

> The success screen — *"Queued offline · syncs when you reconnect"* — is the offline-first promise made visible: the transfer is durable on-device the instant you tap Send, network or not.

---

## ✨ Highlights

- **🔐 Native biometric unlock** — Dart calls a custom `MethodChannel` into Kotlin `BiometricPrompt`. Written by hand to prove native Android capability, not just plugin usage. → [`biometric_authenticator.dart`](lib/core/platform/biometric_authenticator.dart) · [`MainActivity.kt`](android/app/src/main/kotlin/com/abdurrahman/wallet/MainActivity.kt)
- **📴 Offline-first** — the local SQLite DB is the single source of truth. Transfers are durable even with no network; unsynced rows are flagged `pending sync` for later reconciliation.
- **💸 Double-spend safe** — the transfer flow uses **Bloc with `droppable()`** so a double-tap on *Send* can never fire two transfers. A test proves the use case runs exactly once.
- **🧮 Money done right** — amounts are integer **cents**, never `double`. Balance debit + transaction insert happen in one atomic SQLite transaction.
- **🧱 Clean architecture** — `domain` (entities, use cases, repo interfaces) / `data` (sources, models, repo impl) / `presentation` (Cubit + Bloc). Dependencies point inward only.
- **🎨 Considered UI** — a token-driven design system (`WalletTokens`) with a first-class **light & dark** theme, gradient balance card, and micro-interactions (pulsing unlock ring, press-scale actions). Fintech polish, not a scaffold.

## 🧠 State management — deliberate, not default

| Flow | Tool | Why |
|------|------|-----|
| Biometric unlock, dashboard load | **Cubit** | Linear flows; no event log needed |
| Money transfer | **Bloc + `droppable()`** | Event layer gives concurrency control → no double spend |

This "Cubit for the simple 80%, Bloc for the risky 20%" split is a decision I can defend in an interview.

## 🏗️ Architecture

Three layers, one rule: **dependencies point inward.** `presentation` and `data` both depend on `domain`; `domain` depends on nothing. It knows only its own entities and repository *interfaces* — never Flutter, sqflite, or the network.

```
┌─ presentation ───────────────────────────────┐
│  AuthCubit · DashboardCubit · TransferBloc   │  UI + state
└──────────────────────┬───────────────────────┘
                       │ calls use cases
┌──────────────────────▼────────────────────────┐
│                   domain                      │  pure Dart, no deps
│  use cases · entities · repository interface  │  ◀── the contract
└──────────────────────▲────────────────────────┘
                       │ implements the interface
┌──────────────────────┴────────────────────────┐
│                    data                       │  fulfills the contract
│  WalletRepositoryImpl                         │
│    ├─ local  → sqflite   ◀── source of truth  │
│    └─ remote → mock API  (background sync)    │
└───────────────────────────────────────────────┘

core/platform → MethodChannel → Kotlin BiometricPrompt   (native bridge)
```

**Why it's built this way:** the repository interface lives in `domain`, but its implementation lives in `data`. So the transfer use case depends on an abstraction, not on SQLite — swap the data source (or mock it in a test) and `domain` never changes. That's the inversion that keeps money logic testable and framework-free.

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
