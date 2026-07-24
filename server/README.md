# Reference wallet server

A minimal wallet backend for the Flutter client in this repo.

It exists for one reason: idempotency and reconciliation are **contracts**, and
a contract has two sides. Mocking both in the same process is self-fulfilling —
you cannot discover that the key never survived JSON, or that a status code was
classified into the wrong retry behaviour. These are the bugs that only appear
across a process boundary.

It is deliberately **not** production shaped: in-memory, no auth, no database,
no deployment. Restarting it is the reset button.

## Run

```sh
cd server
dart pub get
dart run bin/server.dart          # http://localhost:8080
```

| Variable | Default | Effect |
| --- | --- | --- |
| `PORT` | `8080` | Listen port |
| `INITIAL_BALANCE_CENTS` | `250000` | Starting balance |
| `CHAOS_LATENCY_MS` | `0` | Delay before every response |
| `CHAOS_FAILURE_RATE` | `0` | `0`–`1` chance of a 503 |
| `CHAOS_REJECT_TRANSFERS` | `false` | Always 422 — the terminal case |
| `CHAOS_DROP_AFTER_APPLY` | `false` | **Apply the transfer, then fail** |

`CHAOS_DROP_AFTER_APPLY` is the interesting one. The transfer is applied and
the client is then told the request failed, so it cannot distinguish "never
arrived" from "arrived and the reply was lost". Its only safe move is to retry
— and the idempotency key is what stops that retry becoming a second debit.

```sh
CHAOS_DROP_AFTER_APPLY=true dart run bin/server.dart
```

## Tests

The Flutter app's integration suite boots this server itself:

```sh
flutter test --tags integration --run-skipped     # from the repo root
```

They are excluded from the default `flutter test` run, which uses the
in-process fake instead — faster, deterministic, and needs nothing installed.

## Pointing the app at it

The app runs against `FakeWalletRemoteDataSource` by default. Swap the
registration in `lib/core/di/injector.dart`:

```dart
sl.registerLazySingleton<WalletRemoteDataSource>(
  () => HttpWalletRemoteDataSource(baseUrl: Uri.parse('http://10.0.2.2:8080')),
);
```

`10.0.2.2` is the host machine from an Android emulator; use `localhost` for
iOS simulator or desktop. Nothing above the datasource changes — that is the
point of the interface.
