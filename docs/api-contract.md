# Wallet API contract

The client is offline-first: the local database is the source of truth and the
network is background reconciliation. That puts three obligations on the
server, and the client's correctness depends on all three.

1. **Dedupe on the idempotency key.** The client cannot tell a lost request
   from a lost response, so it retries. The server must make the retry a no-op.
2. **Return the authoritative balance on every write.** The client never
   computes what a debit did to the server's balance — it writes what the
   server reports.
3. **Make errors classifiable.** "Never arrived" and "arrived and was refused"
   demand opposite responses: retry forever vs. never retry. A generic 500 for
   both is unimplementable on the client.

---

## `POST /transfers`

```http
POST /transfers
Idempotency-Key: <client-generated transaction id>
Content-Type: application/json

{ "toCounterparty": "alice", "amountCents": 10000 }
```

| Status | Meaning | Client response |
| --- | --- | --- |
| `201` | Applied | Mark `Synced`, write `balanceCents` as the confirmed balance |
| `200` | Key already applied — same body as the original `201` | Identical to `201`. This is a success, not an error |
| `422` | Business rule refused it (see `code`) | Mark `Rejected`. **Never retry** |
| `401` | Credentials expired | Park the queue, prompt re-auth. Do not burn attempts |
| `503`, timeout, connection failure | Transient | Stay `Pending`, retry with backoff |

Success body:

```json
{ "id": "tx_17…", "balanceCents": 240000, "serverTimestamp": 1700000000000 }
```

`422` body:

```json
{ "code": "INSUFFICIENT_FUNDS", "message": "Balance too low" }
```

### Why `200` and not `409`

A replayed idempotency key is the **expected** outcome of a retry after an
ambiguous timeout, not a conflict. Returning an error status would push the
client down its failure path for a transfer the server has already applied —
and the client would then reverse a transfer that really happened. Returning
the original result makes the retry a no-op, which is the entire point.

Keys are retained for at least 24h. A key seen after that window is treated as
new, so clients must not retry indefinitely.

### Ordering

The client drains its outbox serially and stops at the first transient failure,
so the server sees one in-flight transfer per client at a time and never has to
reorder. It may still reject on its own balance check — the client's local
check is optimistic, not authoritative.

---

## `GET /account`

```json
{ "id": "acc_demo", "holderName": "Jamie Carter",
  "balanceCents": 250000, "currency": "USD" }
```

`balanceCents` is authoritative and excludes anything the server has not
applied. The client subtracts its own still-pending transfers to get the
spendable figure.

---

## `GET /transactions`

```json
[ { "id": "tx_17…", "counterparty": "alice",
    "amountCents": 10000, "serverTimestamp": 1700000000000 } ]
```

Reconciliation is by **id**, not by arithmetic. On refresh the client promotes
any local `Pending` row whose id appears here to `Synced` *before* it writes the
new confirmed balance — otherwise it would subtract a pending debit the server
had already applied and show a balance that is too low.

This is why transaction ids are generated on the client: the same value is the
idempotency key on write and the reconciliation key on read.
