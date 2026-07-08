part of 'transfer_bloc.dart';

enum TransferStatus { idle, submitting, success, failure }

class TransferState extends Equatable {
  const TransferState({this.status = TransferStatus.idle, this.message = ''});
  final TransferStatus status;
  final String message;

  TransferState copyWith({TransferStatus? status, String? message}) =>
      TransferState(status: status ?? this.status, message: message ?? this.message);

  @override
  List<Object?> get props => [status, message];
}
