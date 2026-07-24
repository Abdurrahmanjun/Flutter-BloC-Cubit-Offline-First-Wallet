import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:offline_first_wallet/core/error/failures.dart';
import 'package:offline_first_wallet/domain/entities/transaction.dart';
import 'package:offline_first_wallet/domain/entities/tx_status.dart';
import 'package:offline_first_wallet/domain/usecases/make_transfer.dart';
import 'package:offline_first_wallet/presentation/transfer/bloc/transfer_bloc.dart';

class MockMakeTransfer extends Mock implements MakeTransfer {}

void main() {
  late MockMakeTransfer makeTransfer;

  setUp(() => makeTransfer = MockMakeTransfer());

  final tx = WalletTransaction(
    id: 't1',
    counterparty: 'Alice',
    amountCents: 1000,
    direction: TxDirection.debit,
    timestamp: DateTime(2026, 1, 1),
  );

  blocTest<TransferBloc, TransferState>(
    'a transfer the server confirmed does not report itself as queued',
    build: () {
      when(() => makeTransfer(
            toCounterparty: any(named: 'toCounterparty'),
            amountCents: any(named: 'amountCents'),
          )).thenAnswer((_) async => Right(tx.copyWith(status: const Synced())));
      return TransferBloc(makeTransfer);
    },
    act: (bloc) => bloc.add(
        const TransferSubmitted(toCounterparty: 'Alice', amountCents: 1000)),
    expect: () => [
      const TransferInProgress(),
      const TransferSucceeded(queued: false),
    ],
  );

  blocTest<TransferBloc, TransferState>(
    'a transfer that only reached the outbox is still a success, but queued',
    build: () {
      when(() => makeTransfer(
            toCounterparty: any(named: 'toCounterparty'),
            amountCents: any(named: 'amountCents'),
          )).thenAnswer((_) async => Right(tx));
      return TransferBloc(makeTransfer);
    },
    act: (bloc) => bloc.add(
        const TransferSubmitted(toCounterparty: 'Alice', amountCents: 1000)),
    expect: () => [
      const TransferInProgress(),
      const TransferSucceeded(queued: true),
    ],
  );

  blocTest<TransferBloc, TransferState>(
    'emits [submitting, failure] when the use case fails',
    build: () {
      when(() => makeTransfer(
            toCounterparty: any(named: 'toCounterparty'),
            amountCents: any(named: 'amountCents'),
          )).thenAnswer(
          (_) async => const Left(TransferFailure('Insufficient balance')));
      return TransferBloc(makeTransfer);
    },
    act: (bloc) => bloc.add(
        const TransferSubmitted(toCounterparty: 'Bob', amountCents: 999999)),
    expect: () => [
      const TransferInProgress(),
      const TransferFailed('Insufficient balance'),
    ],
  );

  blocTest<TransferBloc, TransferState>(
    'droppable(): a rapid double-submit runs the use case only ONCE',
    build: () {
      when(() => makeTransfer(
            toCounterparty: any(named: 'toCounterparty'),
            amountCents: any(named: 'amountCents'),
          )).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return Right(tx);
      });
      return TransferBloc(makeTransfer);
    },
    act: (bloc) => bloc
      ..add(const TransferSubmitted(toCounterparty: 'Alice', amountCents: 1000))
      ..add(const TransferSubmitted(toCounterparty: 'Alice', amountCents: 1000)),
    wait: const Duration(milliseconds: 80),
    verify: (_) {
      verify(() => makeTransfer(
            toCounterparty: any(named: 'toCounterparty'),
            amountCents: any(named: 'amountCents'),
          )).called(1); // second tap dropped — no double spend
    },
  );
}
