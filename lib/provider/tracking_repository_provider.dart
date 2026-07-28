import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackflow/data/repositories/tracking_repository_impl.dart';
import 'package:trackflow/domain/repositories/tracking_repository.dart';
import 'database_provider.dart';

final trackingRepositoryProvider = FutureProvider<TrackingRepository>((ref) async {
  final database = await ref.watch(databaseProvider.future);
  return TrackingRepositoryImpl(database);
});
