import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/error/exceptions.dart';
import '../models/account_model.dart';
import '../models/remote_transaction.dart';
import '../models/transfer_ack.dart';
import '../../domain/entities/transaction.dart';
import 'wallet_remote_datasource.dart';

/// Talks to the reference server in `server/`.
///
/// The only interesting logic here is [_translate]: turning HTTP outcomes into
/// the three exception types the sync worker branches on. Getting that mapping
/// wrong is silent and expensive — classify a business rejection as transient
/// and the client retries a doomed transfer forever; classify a timeout as
/// terminal and it reverses a transfer that may have succeeded.
class HttpWalletRemoteDataSource implements WalletRemoteDataSource {
  HttpWalletRemoteDataSource({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<AccountModel> fetchAccount() async {
    final body = await _get('/account') as Map<String, Object?>;
    return AccountModel(
      id: body['id']! as String,
      holderName: body['holderName']! as String,
      confirmedBalanceCents: body['balanceCents']! as int,
      currency: body['currency']! as String,
    );
  }

  @override
  Future<List<RemoteTransaction>> fetchTransactions() async {
    final body = await _get('/transactions') as List<Object?>;
    return body.cast<Map<String, Object?>>().map((row) {
      return RemoteTransaction(
        id: row['id']! as String,
        counterparty: row['counterparty']! as String,
        amountCents: row['amountCents']! as int,
        serverTime: DateTime.fromMillisecondsSinceEpoch(
            row['serverTimestamp']! as int),
        direction: row['direction'] == 'credit'
            ? TxDirection.credit
            : TxDirection.debit,
      );
    }).toList();
  }

  @override
  Future<TransferAck> pushTransfer({
    required String idempotencyKey,
    required String toCounterparty,
    required int amountCents,
  }) async {
    final response = await _send(() => _client.post(
          baseUrl.resolve('/transfers'),
          headers: {
            'content-type': 'application/json',
            // The client-generated transaction id. This is what makes a retry
            // after a lost reply a no-op instead of a second debit.
            'idempotency-key': idempotencyKey,
          },
          body: jsonEncode({
            'toCounterparty': toCounterparty,
            'amountCents': amountCents,
          }),
        ));

    // 201 = applied now, 200 = this key was applied earlier. Both are the same
    // outcome to the client; treating 200 as anything else would be the bug
    // the contract's status codes exist to prevent.
    final body = _translate(response) as Map<String, Object?>;
    return TransferAck(
      id: body['id']! as String,
      balanceCents: body['balanceCents']! as int,
      serverTime:
          DateTime.fromMillisecondsSinceEpoch(body['serverTimestamp']! as int),
    );
  }

  Future<Object?> _get(String path) async =>
      _translate(await _send(() => _client.get(baseUrl.resolve(path))));

  /// Anything that prevents a reply is transient. Notably this includes a
  /// timeout, where the request may well have been applied — the client
  /// cannot know, so it must retry rather than assume failure.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      return throw const NetworkException('Request timed out');
    } on SocketException catch (e) {
      throw NetworkException(e.message);
    } on http.ClientException catch (e) {
      throw NetworkException(e.message);
    }
  }

  Object? _translate(http.Response response) {
    final status = response.statusCode;

    if (status == 200 || status == 201) {
      return response.body.isEmpty ? null : jsonDecode(response.body);
    }

    final message = _messageOf(response) ?? 'HTTP $status';

    // 4xx is the server having looked at the request and refused it. Retrying
    // produces the same answer forever, so it must never go back in the queue.
    if (status == 401 || status == 403) throw AuthExpiredException(message);
    if (status >= 400 && status < 500) throw RejectedException(message);

    // 5xx: the server had a problem. It may or may not have applied the write.
    throw NetworkException(message);
  }

  /// Prefers the contract's machine-readable `code` over prose, since it ends
  /// up stored on the rejected transaction as its reason.
  String? _messageOf(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, Object?>;
      return (body['code'] ?? body['message']) as String?;
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
