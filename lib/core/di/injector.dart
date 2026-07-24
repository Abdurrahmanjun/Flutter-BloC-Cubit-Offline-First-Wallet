import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get_it/get_it.dart';
import '../platform/biometric_authenticator.dart';
import '../../data/datasources/wallet_local_datasource.dart';
import '../../data/datasources/fake_wallet_remote_datasource.dart';
import '../../data/datasources/wallet_remote_datasource.dart';
import '../../data/repositories/wallet_repository_impl.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../../domain/repositories/wallet_sync.dart';
import '../../domain/usecases/get_account.dart';
import '../../domain/usecases/get_transactions.dart';
import '../../domain/usecases/make_transfer.dart';
import '../../domain/usecases/refresh_wallet.dart';
import '../../presentation/auth/cubit/auth_cubit.dart';
import '../../presentation/dashboard/cubit/dashboard_cubit.dart';
import '../../presentation/transfer/bloc/transfer_bloc.dart';

final sl = GetIt.instance;

Future<void> initInjector() async {
  // Platform
  sl.registerLazySingleton(BiometricAuthenticator.new);

  // Data sources
  sl.registerLazySingleton(WalletLocalDataSource.new);
  // The app runs against the in-process fake so it works with nothing else
  // installed. Point this at HttpWalletRemoteDataSource to drive the
  // reference server in `server/` instead — nothing above this line changes.
  sl.registerLazySingleton<WalletRemoteDataSource>(
      FakeWalletRemoteDataSource.new);

  // Repository
  sl.registerLazySingleton<WalletRepository>(
    () => WalletRepositoryImpl(local: sl(), remote: sl()),
  );

  // Outbox worker. Singleton: one drain loop for the whole app, or two
  // triggers would race on the same rows.
  sl.registerLazySingleton(
    () => SyncService(
      local: sl(),
      remote: sl(),
      // Connectivity is not reachability — a captive portal reports "online".
      // A failed push just re-queues, so an optimistic trigger is fine.
      onOnline: Connectivity().onConnectivityChanged.map(
            (result) => result != ConnectivityResult.none,
          ),
    ),
  );

  // Presentation talks to the worker through the domain abstraction; only
  // main() needs the concrete type, for start-up and lifecycle hooks.
  sl.registerLazySingleton<WalletSync>(() => sl<SyncService>());

  // Use cases
  sl.registerLazySingleton(() => GetAccount(sl()));
  sl.registerLazySingleton(() => GetTransactions(sl()));
  sl.registerLazySingleton(() => MakeTransfer(sl()));
  sl.registerLazySingleton(() => RefreshWallet(sl()));

  // Blocs / Cubits (factory: fresh instance per screen)
  sl.registerFactory(() => AuthCubit(sl()));
  sl.registerFactory(() => DashboardCubit(
        getAccount: sl(),
        getTransactions: sl(),
        refreshWallet: sl(),
        sync: sl(),
      ));
  sl.registerFactory(() => TransferBloc(sl()));
}
