import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trackflow/data/local/database.dart';

/// データベースの非同期プロバイダー。
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  try {
    return await AppDatabase.create();
  } catch (e) {
    debugPrint('Database creation failed, falling back to in-memory: $e');
    // ファイルベースDBが使えない場合はインメモリDBにフォールバック
    // 注意: この状態ではデータは永続化されず、アプリ再起動で消失する
    return AppDatabase.inMemory();
  }
});
