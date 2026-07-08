import 'package:get_it/get_it.dart';
import '../platform/biometric_authenticator.dart';
import '../../data/datasources/wallet_local_datasource.dart';
import '../../data/datasources/wallet_remote_datasource.dart';
import '../../data/repositories/wallet_repository_impl.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../../domain/usecases/get_account.dart';
import '../../domain/usecases/get_transactions.dart';
import '../../domain/usecases/make_transfer.dart';
import '../../presentation/auth/cubit/auth_cubit.dart';
import '../../presentation/dashboard/cubit/dashboard_cubit.dart';
import '../../presentation/transfer/bloc/transfer_bloc.dart';

final sl = GetIt.instance;

Future<void> initInjector() async {
  // Platform
  sl.registerLazySingleton(BiometricAuthenticator.new);

  // Data sources
  sl.registerLazySingleton(WalletLocalDataSource.new);
  sl.registerLazySingleton(WalletRemoteDataSource.new);

  // Repository
  sl.registerLazySingleton<WalletRepository>(
    () => WalletRepositoryImpl(local: sl(), remote: sl()),
  );

  // Use cases
  sl.registerLazySingleton(() => GetAccount(sl()));
  sl.registerLazySingleton(() => GetTransactions(sl()));
  sl.registerLazySingleton(() => MakeTransfer(sl()));

  // Blocs / Cubits (factory: fresh instance per screen)
  sl.registerFactory(() => AuthCubit(sl()));
  sl.registerFactory(() => DashboardCubit(getAccount: sl(), getTransactions: sl()));
  sl.registerFactory(() => TransferBloc(sl()));
}
