part of 'transfer_bloc.dart';

abstract class TransferEvent extends Equatable {
  const TransferEvent();
  @override
  List<Object?> get props => [];
}

class TransferSubmitted extends TransferEvent {
  const TransferSubmitted({required this.toCounterparty, required this.amountCents});
  final String toCounterparty;
  final int amountCents;
  @override
  List<Object?> get props => [toCounterparty, amountCents];
}
