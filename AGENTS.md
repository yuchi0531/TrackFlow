# AGENTS.md

## Project overview

TrackFlow - ヤマト運輸・佐川急便・日本郵便 統合荷物追跡アプリ。3社の公式HTML追跡ページをスクレイピングして配送状況を取得する Flutter アプリ。個人向け公開APIは存在しない。

**Android only**（iOSディレクトリ削除済み）。現在のバージョンは 0.0.6（pubspec.yaml の version のみ）。

## Setup commands

```bash
export JAVA_HOME=$HOME/jdk17
export ANDROID_HOME=$HOME/android-sdk
export PATH=$HOME/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH

flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs  # Drift ORMコード生成
flutter test                                                      # 単体テスト 75件
flutter build apk --release                                       # リリースAPK (~32.8MB)
```

Flutter SDK パス: `/home/yuchi0531/flutter`

## Verify before commit

```bash
dart analyze lib/     # No issues found が必須
flutter test          # 全75件パス（DBはインメモリ、ネットワーク不要）
flutter build apk --release  # リリースビルド確認
```

## Tech stack

| 層 | 技術 |
|---|---|
| Framework | Flutter 3.44 (Dart 3.12) |
| State | Riverpod 2 (flutter_riverpod) |
| Router | go_router 14 (ShellRoute + NavigationBar) |
| DB | Drift 2.24 (SQLite via NativeDatabase, drift_flutter) |
| Theme | Material Design 3 (ColorScheme.fromSeed, #1565C0) |
| HTTP | http 1.3 + html 0.15 |
| Background | workmanager 0.9.0 (registerPeriodicTask, callbackDispatcher) |
| Notifications | flutter_local_notifications 18 + permission_handler 11.3 (Android 13+ POST_NOTIFICATIONS) |
| Settings | shared_preferences |
| Links/Share | url_launcher 6.3.2 + share_plus 13.3.0 |
| File (CSV) | file_picker 12.0.0-beta.7（11.x は AGP9 でビルド不能） |
| Home Widget | ネイティブ AppWidgetProvider + RemoteViews（FlutterView 埋め込みではない） |
| Build | R8無効 (isMinifyEnabled=false), desugar_jdk_libs:2.1.4, multiDex有効 |

## Project structure

```
lib/
├── main.dart                            # initBackgroundService→initNotificationChannels→widgetスナップショット→runApp (順序重要)
├── app.dart                             # MaterialApp.router
├── core/
│   ├── theme/app_theme.dart             # CardThemeData (not CardTheme), M3, ライト/ダーク両対応
│   └── constants/carrier_urls.dart      # 3社スクレイピングURL + 共通User-Agent + ブラウザ用URL
├── domain/
│   ├── entities/                        # Carrier enum, TrackingInfo, TrackingEvent (freezed不使用)
│   ├── tracking_number.dart             # TrackingNumberValidator (isValid / detectCarrier)
│   └── repositories/                    # 抽象インターフェース
├── data/
│   ├── scraping/                        # JapanPostTracker, YamatoTracker, SagawaTracker, TrackerFactory, TrackerException
│   ├── csv/                             # csv_export.dart / csv_import.dart (純粋関数)
│   ├── local/database.dart              # Drift (SavedTrackings, TrackingHistories, TrackingEventEntries)
│   └── repositories/                    # TrackingRepositoryImpl (キャッシュフォールバック付き)
├── provider/
│   ├── database_provider.dart           # FutureProvider<AppDatabase> (ファイル失敗時はinMemoryフォールバック)
│   ├── tracking_repository_provider.dart
│   ├── tracking_providers.dart          # trackingList, trackingDetail, addTracking, deleteTracking (+ウィジェットスナップショット更新)
│   ├── settings_provider.dart           # AsyncNotifier<SharedPreferences>、設定キー定数
│   ├── background_provider.dart         # Workmanager + 通知 + isDeliveryToday (callbackDispatcher)
│   └── widget_snapshot_provider.dart    # ウィジェット用JSONスナップショット + MethodChannel
└── presentation/
    ├── router/app_router.dart           # ShellRoute + NavigationBar (追跡一覧/設定)、他はpush
    ├── tracking_list/                   # 絞り込み + 並び替え + 自動アーカイブ + 停滞警告 + Dismissible
    ├── add_tracking/                    # 複数番号一括追加 (maxLines:3) + 配送会社 手動選択必須
    ├── detail/                          # タイムライン + 公式サイトリンク + コピー/共有
    └── settings/                        # 更新間隔 + 通知トグル(配達予定日当日含む) + CSV入出力 + プライバシーポリシー
```

## Code conventions

- **非nullSafe全体に注意**: `html/parser.dart` の `parse` が各Trackerの `parse` メソッドと衝突 → `import 'package:html/parser.dart' as html_parser;`
- **ドメインEntity**: freezed 不使用。Driftのgenerated codeと衝突するため。素のDartクラス。
- **Driftテーブル名**: `TrackingEventEntries` を使用（`TrackingEvents` はdomainの `TrackingEvent` と衝突）
- **DB構築**: `AppDatabase.create()` 非同期ファクトリ（`LazyDatabase` 不使用）。`AppDatabase.inMemory()` はテスト専用。**バックグラウンドIsolateでも必ず `create()` を使う**（過去にinMemory使用でデータ連携が壊れた実績あり）
- **saveHistory の更新ポリシー**: 同一ステータスなら既存レコードを `fetchedAt` 更新のみ、ステータス変化時のみ新規INSERT（テーブル肥大防止＋通知の前回比較に利用）
- **saveEvents は delete→insert**: 同一 `historyId` の既存イベントを全削除してから挿入（重複防止）
- **Provider**: `FutureProvider` + `.future` で非同期DBアクセスを解決
- **ナビゲーション**: タブ外画面は `context.push()`（`context.go()` はスタック破壊）。詳細画面は `/detail/:number?carrier=xxx`
- **テーマ**: `CardThemeData`（`CardTheme` は Flutter 3.44 でdeprecated）
- **アイコン**: adaptive icon（`drawable/ic_launcher_foreground.png` 円形、`ic_launcher_background.png` #FDFDFD）
- **minSdk**: 24（Flutter 3.44 のデフォルト）
- **配送会社は手動選択必須**: 自動判別はUIから削除（ユーザー要望）。未選択なら「配送会社を選択してください」SnackBar で登録しない。`detectCarrier()` は UI 未使用・テスト用に残置
- **一括追加**: 番号フィールドは `maxLines:3` で改行・カンマ・スペース区切り対応。`splitTrackingNumbers()` / `buildAddResultSummary()` はトップレベル公開関数（テスト可能）。配送会社1つを全番号に適用
- **isDeliveredStatus は公開関数**: `@visibleForTesting` を外した。一覧の絞り込み・自動アーカイブとバックグラウンド通知判定の両方で使用

## Background / notification gotchas (重要)

- `main()` では `await initBackgroundService()` → `await initNotificationChannels()` → `runApp()` の順。awaitしないとプロセスkill時に定期タスクが登録されない（起動時のウィジェットスナップショット更新は fire-and-forget）
- **通知IDは追跡番号からハッシュ安定生成**: `notificationIdFor(number)`（**FNV-1a 32bit を自前実装** → `& 0x7FFFFFFF` → `% 2000000000 + 1`）。Dart の `String.hashCode` はプロセスをまたぐ同一性が保証されないため、workmanager の別プロセス起動でも同一IDになるよう自前実装。Android の NotificationManager は32bit intのためビットマスク必須
- **通知チャンネル2種**: `delivery_channel`(配達完了, Importance.high) / `status_channel`(ステータス変更, default)。callbackDispatcher内でも作成必須
- **設定キーは文字列定数**: `notify_delivery`, `notify_status_change`, `delivery_day_notify`, `update_interval`。背景IsolateはProviderを読めないため callbackDispatcher は `SharedPreferences.getInstance()` を直接読む
- **配達完了判定**: `isDeliveredStatus()` が「配達完了/お届け済み/投函完了/配達済み/お届け完了」の5キーワードで判定（各社表現が異なるため文字列contains）
- **配達予定日当日通知 (v0.0.6)**: 設定キー `delivery_day_notify`（デフォルト true）。**zonedSchedule は不使用・timezone パッケージ追加なし**。callbackDispatcher 内で `isDeliveryToday(estimatedDelivery)` 判定（`YYYY/MM/DD` 優先、年なし `M/D` は現在年仮定+未来なら年を1つ戻す）。**1日1回制御**: `delivery_day_notified_<追跡番号>` = `YYYY/MM/DD` を保存し、同一日は再通知しない。配達完了済みは通知しない。チャンネルは status_channel 再利用、通知IDは notificationIdFor
- **更新間隔**: `'15分'|'30分'|'1時間'|'3時間'` を `intervalToDuration()` でDuration変換。設定変更時は `updateBackgroundTaskInterval()` で cancel→再登録
- **trackingListProvider はN+1回避のバッチ取得**: `getAllLatestHistories()`（id.max() GROUP BY）+ `getEventsForHistories()` を1回ずつ
- **履歴なしの追跡はプレースホルダー表示**: `history == null` の場合は `currentStatus: '情報を取得できませんでした'` の TrackingInfo を返す（一覧から消えないようにする仕様。削除しないこと）
- **addTracking は先にfetch成功時のみ登録**: 取得失敗時は登録せず例外をthrow（「登録されたが履歴が空」の中途半端な状態を防ぐ）。一括追加時も番号ごとに適用され、失敗分は `buildAddResultSummary()` で集計
- **キャッシュフォールバック**: `TrackingRepositoryImpl.fetchTracking` は TrackerException/TimeoutException 時に最新キャッシュを返し、キャッシュなしの場合のみ例外throw

## Widget / CSV (v0.0.6)

### ホーム画面ウィジェット

- **実装**: ネイティブ `AppWidgetProvider` + `RemoteViews`（`TrackingWidgetProvider.kt`）。FlutterView 埋め込みではない
- **データ共有**: Flutter 側が SharedPreferences に JSON スナップショットを保存（キー `trackflow_widget_snapshot`）。ネイティブは shared_preferences プラグインのファイル `FlutterSharedPreferences` から **`flutter.trackflow_widget_snapshot`** を読む（`flutter.` プレフィックスに注意）
- **スナップショット形式**: `{"total": N, "items": [{trackingNumber, carrier, carrierDisplay, currentStatus, nickname, lastUpdated}]}`。items は最大4件（`kWidgetMaxItems`、登録順=createdAt 降順の先頭）+ total に総数
- **更新タイミング**: `trackingListProvider` の build()/delete() 完了時（`unawaited(updateWidgetSnapshot(db: db))`）、callbackDispatcher 完了時（**MethodChannel不可のため保存のみ** `notifyNative: false`。反映は次回フォアグラウンド更新時）、main 起動時
- **MethodChannel**: Dart `WidgetSnapshotChannel` → ネイティブ `WidgetSnapshotChannel.kt` → `TrackingWidgetProvider.updateAllWidgets()`。MainActivity.configureFlutterEngine で登録。MethodChannel は UI Isolate のみのため、例外は握りつぶしてクラッシュさせない
- **manifest**: `<receiver android:name=".TrackingWidgetProvider" android:exported="true">`（ランチャーのウィジェットピッカーがバインドするため exported=true が安全）
- **res/xml/tracking_widget_info.xml**: 4x2、`updatePeriodMillis=0`（30分最小制約を回避。更新はスナップショット保存時 + MethodChannel 経由のみ）

### CSV エクスポート/インポート

- `lib/data/csv/csv_export.dart`: `buildTrackingsCsv()` 純粋関数。アクティブな追跡のみ出力、RFC 4180風エスケープ（`"` `,` 改行は引用符 + `""`）
- `lib/data/csv/csv_import.dart`: `parseTrackingsCsv()` 純粋関数。BOM対応、引用符内カンマ/改行対応、無効行（番号不正・キャリア不一致）はスキップ
- インポートは **fetch しない**（バックグラウンドの定期タスクが後で取得）。重複は `findByTrackingNumber` でスキップ
- **file_picker は ^12.0.0-beta.7 必須**: 11.x は AGP9 + `android.builtInKotlin=false` 環境でビルド不能。12-beta は builtInKotlin 対応。win32 ^6 競合も回避

## Carrier scraping details

| 会社 | HTTP | URL / パラメータ |
|------|------|-----|
| 日本郵便 | GET | `https://trackings.post.japanpost.jp/services/srv/search/direct` ?`reqCodeNo1=XXX&searchKind=S004&locale=ja` |
| ヤマト運輸 | POST | `https://toi.kuronekoyamato.co.jp/cgi-bin/tneko` (body: `number00=1&number01=XXX`) |
| 佐川急便 | POST | `https://k2k.sagawa-exp.co.jp/p/web/okurijosearch.do` (body: `okurijoNo=XXX`) |

- 全トラッカー共通: **15秒タイムアウト**、User-Agent は `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15`
- ヤマト: JS組立てページ → `swd.writeln('...')` 正規表現抽出 → `\<`→`<`, `\>`→`>`, `\/`→`/` エスケープ解除 → DOCTYPE/html/head/body/title/style/script/コメント削除
- 佐川: ステータス装飾文字（`↓⇒\u3000`）trim、配達予定日は `配達予定日` ラベル以降の文字列を抽出
- 日本郵便: `table.tableType01` が2つ必要（1つ目=商品種別、2つ目=履歴）。無ければ notFound
- 日付パース: ヤマト/佐川は現在年を仮定し、**未来日時は年を1つ戻す**（年跨ぎ対応）。日本郵便は `YYYY/MM/DD HH:MM` 形式
- **追跡番号自動判定は UI 未使用**: `detectCarrier()` は 11桁/13桁 → 日本郵便、12桁 → ヤマト（**佐川も12桁なので判別不能 → 佐川は手動選択必須**）。有効桁数は10-14桁。UIからは削除済みでテスト用に残置
- **詳細画面の公式サイトリンク**: 日本郵便は番号をURLに埋め込み（`japanPostWebTrackingUrl(number)`）、ヤマト/佐川は POST 専用のためトップページを開く。`launchUrl(..., mode: LaunchMode.externalApplication)`

## Android manifest

必須パーミッション: `INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`

- ウィジェット: `<receiver android:name=".TrackingWidgetProvider" android:exported="true">` + `@xml/tracking_widget_info`（詳細は「Widget / CSV」セクション参照）
- `<queries>` に `PROCESS_TEXT` (text/plain) を追加（share_plus で共有先アプリの可視性を確保）

## Build gotchas

- **workmanager 0.5.2 は Flutter 3.44 非互換** → 必ず 0.9.0+ を使用
- **file_picker は ^12.0.0-beta.7 必須**: 11.x は AGP9 + `android.builtInKotlin=false`（gradle.properties の legacy 設定）で Kotlin がコンパイルされずビルド不能。12.0.0-beta はプロパティを確認して KGP を適用する。12安定版リリース後は自動移行される
- **Gradleビルドキャッシュ破損**: ディスク空き容量不足時（100% full）に不完全APKが生成される。最低2GB確保
- **デバッグ/リリースビルド**: `isCoreLibraryDesugaringEnabled=true` と `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` が必須（workmanager/local_notifications の Java 8+ API 使用）
- **ProGuard/R8**: `isMinifyEnabled=false`（Drift/Workmanager生成コード破壊防止）
- **リリースAPKは debug 署名**: `release { signingConfig = signingConfigs.getByName("debug") }` が意図的設定（ストア公開前の暫定）。変更しない

## Security

- 個人情報非収集、全データは端末内 SQLite のみ
- ネットワーク通信は配送会社公式サイトのみ
- APIキー不要（全て公開ページのHTMLスクレイピング）
- HTML構造変更により追跡失敗の可能性あり → TrackerException でエラーハンドリング

## Release flow

- バージョンは pubspec.yaml の `version` のみ（versionCode は Flutter が自動採番）
- 慣例: `release: bump version to x.y.z` コミットで発行。最後の機能変更コミットは `a5bb732 fix: 通知・自動更新機能のバグ修正と安定化`
