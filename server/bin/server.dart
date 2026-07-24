import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;
import 'package:wallet_server/api.dart';
import 'package:wallet_server/chaos.dart';
import 'package:wallet_server/store.dart';

/// Reference wallet backend.
///
///     dart run bin/server.dart
///     PORT=8081 CHAOS_DROP_AFTER_APPLY=true dart run bin/server.dart
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;

  final store = Store(
    balanceCents: int.tryParse(env['INITIAL_BALANCE_CENTS'] ?? '') ?? 250000,
  );
  final chaos = Chaos.fromEnvironment(env);

  final server = await io.serve(
    buildHandler(store: store, chaos: chaos),
    InternetAddress.anyIPv4,
    port,
  );

  stdout.writeln('wallet server on http://${server.address.host}:${server.port}');
  if (chaos.failureRate > 0 || chaos.dropAfterApply || chaos.rejectTransfers) {
    stdout.writeln('chaos: failureRate=${chaos.failureRate} '
        'dropAfterApply=${chaos.dropAfterApply} '
        'rejectTransfers=${chaos.rejectTransfers}');
  }
}
