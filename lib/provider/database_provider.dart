import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackflow/data/local/database.dart';

/// データベースの非同期プロバイダー。
/// 失敗時はインメモリDBにフォールバックし、アプリの起動を妨げない。
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  try {
    return await AppDatabase.create();
  } catch (e) {
    // ファイルベースDBが使えない場合（パーミッション不足等）はインメモリにフォールバック
    return AppDatabase.inMemory();
  }
});
