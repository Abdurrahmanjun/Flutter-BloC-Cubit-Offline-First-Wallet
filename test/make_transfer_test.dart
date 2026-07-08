import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_first_wallet/core/error/failures.dart';
import 'package:offline_first_wallet/domain/entities/transaction.dart';
import 'package:offline_first_wallet/domain/repositories/wallet_repository.dart';
import 'package:offline_first_wallet/domain/usecases/make_transfer.dart';

class MockRepo extends Mock implements WalletRepository {}

void main() {
  late MockRepo repo;
  late MakeTransfer usecase;

  setUp(() {
    repo = MockRepo();
    usecase = MakeTransfer(repo);
  });

  test('rejects a non-positive amount without hitting the repository', () async {
    final result = await usecase(toCounterparty: 'A', amountCents: 0);
    expect(result, isA<Left<Failure, WalletTransaction>>());
    verifyNever(() => repo.transfer(
        toCounterparty: any(named: 'toCounterparty'),
        amountCents: any(named: 'amountCents')));
  });
}
