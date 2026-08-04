import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/catalog_repository.dart';
import '../data/order_repository.dart';
import '../data/print_repository.dart';
import 'api_client.dart';
import 'local_store.dart';

/// Diisi lewat `overrides` di `main()` setelah SharedPreferences siap.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider harus di-override di main()'),
);

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(supabase: ref.watch(supabaseProvider));
  ref.onDispose(client.dispose);
  return client;
});

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(ref.watch(apiClientProvider)),
);

final printRepositoryProvider = Provider<PrintRepository>(
  (ref) => PrintRepository(ref.watch(apiClientProvider)),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(apiClientProvider)),
);

final activityLogRepositoryProvider = Provider<ActivityLogRepository>(
  (ref) => ActivityLogRepository(ref.watch(apiClientProvider)),
);
