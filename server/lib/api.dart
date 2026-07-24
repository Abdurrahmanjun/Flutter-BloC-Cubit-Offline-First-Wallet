import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'chaos.dart';
import 'store.dart';

/// Every status code here is load-bearing on the client side — see the notes
/// on 200 and 422 below.
Handler buildHandler({required Store store, required Chaos chaos}) {
  final router = Router();

  router.get('/account', (Request request) async {
    final failure = await _chaosGate(chaos);
    if (failure != null) return failure;

    return _json(200, {
      'id': store.accountId,
      'holderName': store.holderName,
      'balanceCents': store.balanceCents,
      'currency': store.currency,
    });
  });

  router.get('/transactions', (Request request) async {
    final failure = await _chaosGate(chaos);
    if (failure != null) return failure;

    return _json(200, store.ledger.map((t) => t.toLedgerEntry()).toList());
  });

  router.post('/transfers', (Request request) async {
    final failure = await _chaosGate(chaos);
    if (failure != null) return failure;

    final key = request.headers['idempotency-key'];
    if (key == null || key.isEmpty) {
      // Without a key a retry cannot be recognised, so the write is refused
      // outright rather than risking a double debit.
      return _json(400, {
        'code': 'MISSING_IDEMPOTENCY_KEY',
        'message': 'Idempotency-Key header is required',
      });
    }

    // 200, not 409: a replayed key is the EXPECTED result of a retry after an
    // ambiguous timeout, not a conflict. Returning an error here would send
    // the client down its failure path for a transfer that already succeeded,
    // and it would then reverse something that really happened.
    final replay = store.replay(key);
    if (replay != null) return _json(200, replay.toAck());

    final Map<String, Object?> body;
    try {
      body = jsonDecode(await request.readAsString()) as Map<String, Object?>;
    } catch (_) {
      return _json(400, {'code': 'BAD_REQUEST', 'message': 'Invalid JSON'});
    }

    final to = body['toCounterparty'] as String?;
    final amount = body['amountCents'] as int?;
    if (to == null || to.isEmpty || amount == null || amount <= 0) {
      return _json(400, {
        'code': 'BAD_REQUEST',
        'message': 'toCounterparty and a positive amountCents are required',
      });
    }

    if (chaos.rejectTransfers) {
      return _json(422, {
        'code': 'INSUFFICIENT_FUNDS',
        'message': 'Balance too low',
      });
    }

    final applied = store.apply(
      idempotencyKey: key,
      toCounterparty: to,
      amountCents: amount,
    );

    // 422 is terminal: the client marks the transfer rejected and never
    // retries it. Anything retryable must be a 5xx or a dropped connection.
    if (applied == null) {
      return _json(422, {
        'code': 'INSUFFICIENT_FUNDS',
        'message': 'Balance too low',
      });
    }

    // Applied, then the reply is thrown away. The client is left unable to
    // tell this from a request that never arrived — the case the idempotency
    // key exists for, and the one a real server will not reproduce on demand.
    if (chaos.dropAfterApply) {
      return _json(503, {
        'code': 'UNAVAILABLE',
        'message': 'Connection lost after the request was applied',
      });
    }

    return _json(201, applied.toAck());
  });

  return const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);
}

/// Latency and transient failure, applied before any endpoint does work.
Future<Response?> _chaosGate(Chaos chaos) async {
  await chaos.delay();
  if (chaos.shouldFail) {
    return _json(503, {
      'code': 'UNAVAILABLE',
      'message': 'Transient failure',
    });
  }
  return null;
}

Response _json(int status, Object? body) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );
