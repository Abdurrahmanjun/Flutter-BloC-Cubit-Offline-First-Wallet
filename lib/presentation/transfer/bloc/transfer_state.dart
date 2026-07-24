part of 'transfer_bloc.dart';

/// Sealed so the UI's `switch` is exhaustiveness-checked at compile time —
/// add a new state and every consumer stops compiling until it handles it.
sealed class TransferState extends Equatable {
  const TransferState();
  @override
  List<Object?> get props => [];
}

/// Nothing in flight; the initial state.
class TransferIdle extends TransferState {
  const TransferIdle();
}

/// A transfer is running. `droppable()` drops taps that land in this state.
class TransferInProgress extends TransferState {
  const TransferInProgress();
}

/// The transfer committed successfully.
class TransferSucceeded extends TransferState {
  const TransferSucceeded();
}

/// The transfer failed; [message] is user-facing.
class TransferFailed extends TransferState {
  const TransferFailed(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
