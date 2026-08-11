# AGENTS.md

## Project overview

TrackFlow - ヤマト運輸・佐川急便・日本郵便 統合荷物追跡アプリ。3社の公式HTML追跡ページをスクレイピングして配送状況を取得する Flutter アプリ。個人向け公開APIは存在しない。

**Android only**（iOSディレクトリ削除済み）。現在のバージョンは 0.0.4（pubspec.yaml の version のみ）。

## Setup commands

```bash
export JAVA_HOME=$HOME/jdk17
export ANDROID_HOME=$HOME/android-sdk
export PATH=$HOME/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH

flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs  # Drift ORMコード生成
flutter test                                                      # 単体テスト 35件
flutter build apk --release                                       # リリースAPK (~31MB)
```

Flutter SDK パス: `/home/yuchi0531/flutter`

## Verify before commit

```bash
dart analyze lib/     # No issues found が必須
flutter test          # 全35件パス（DBはインメモリ、ネットワーク不要）
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
| Build | R8無効 (isMinifyEnabled=false), desugar_jdk_libs:2.1.4, multiDex有効 |

## Project structure

```
lib/
├── main.dart                            # initBackgroundService→initNotificationChannels→runApp (順序重要)
├── app.dart                             # MaterialApp.router
├── core/
│   ├── theme/app_theme.dart             # CardThemeData (not CardTheme), M3, ライト/ダーク両対応
│   └── constants/carrier_urls.dart      # 3社スクレイピングURL + 共通User-Agent
├── domain/
│   ├── entities/                        # Carrier enum, TrackingInfo, TrackingEvent (freezed不使用)
│   └── repositories/                    # 抽象インターフェース
├── data/
│   ├── scraping/                        # JapanPostTracker, YamatoTracker, SagawaTracker, TrackerFactory, TrackerException
│   ├── local/database.dart              # Drift (SavedTrackings, TrackingHistories, TrackingEventEntries)
│   └── repositories/                    # TrackingRepositoryImpl (キャッシュフォールバック付き)
├── provider/
│   ├── database_provider.dart           # FutureProvider<AppDatabase> (ファイル失敗時はinMemoryフォールバック)
│   ├── tracking_repository_provider.dart
│   ├── tracking_providers.dart          # trackingList, trackingDetail, addTracking, deleteTracking
│   ├── settings_provider.dart           # AsyncNotifier<SharedPreferences>、設定キー定数
│   └── background_provider.dart         # Workmanager + 通知 (callbackDispatcher)
└── presentation/
    ├── router/app_router.dart           # ShellRoute + NavigationBar (追跡一覧/設定)、他はpush
    ├── tracking_list/                   # 一覧 + Dismissibleスワイプ削除 + ステータス色インジケーター
    ├── add_tracking/                    # 番号入力 + CarrierSelector + 自動判別
    ├── detail/                          # タイムライン + StatusHeader + DeliveryEstimate
    └── settings/                        # 更新間隔選択 + 通知トグル + プライバシーポリシー
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

## Background / notification gotchas (重要)

- `main()` では `await initBackgroundService()` → `await initNotificationChannels()` → `runApp()` の順。awaitしないとプロセスkill時に定期タスクが登録されない
- **通知IDは追跡番号からハッシュ安定生成**: `notificationIdFor(number)`（`hashCode & 0x7FFFFFFF` → `% 2000000000 + 1`）。同一番号に常に同じID→通知の上書き更新が可能。Android の NotificationManager は32bit intのためビットマスク必須。IDを1等にすると作業が危険
- **通知チャンネル2種**: `delivery_channel`(配達完了, Importance.high) / `status_channel`(ステータス変更, default)。callbackDispatcher内でも作成必須
- **設定キーは文字列定数**: `notify_delivery`, `notify_status_change`, `update_interval`。背景IsolateはProviderを読めないため callbackDispatcher は `SharedPreferences.getInstance()` を直接読む
- **配達完了判定**: `isDeliveredStatus()` が「配達完了/お届け済み/投函完了/配達済み/お届け完了」の5キーワードで判定（各社表現が異なるため文字列contains）
- **更新間隔**: `'15分'|'30分'|'1時間'|'3時間'` を `intervalToDuration()` でDuration変換。設定変更時は `updateBackgroundTaskInterval()` で cancel→再登録
- **trackingListProvider はN+1回避のバッチ取得**: `getAllLatestHistories()`（id.max() GROUP BY）+ `getEventsForHistories()` を1回ずつ
- **履歴なしの追跡はプレースホルダー表示**: `history == null` の場合は `currentStatus: '情報を取得できませんでした'` の TrackingInfo を返す（一覧から消えないようにする仕様。削除しないこと）
- **addTracking は先にfetch成功時のみ登録**: 取得失敗時は登録せず例外をthrow（「登録されたが履歴が空」の中途半端な状態を防ぐ）
- **キャッシュフォールバック**: `TrackingRepositoryImpl.fetchTracking` は TrackerException/TimeoutException 時に最新キャッシュを返し、キャッシュなしの場合のみ例外throw

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
- **追跡番号自動判定**: `detectCarrier()` で 11桁/13桁 → 日本郵便、12桁 → ヤマト（**佐川も12桁なので判別不能 → 佐川は手動選択必須**）。有効桁数は10-14桁

## Android manifest

必須パーミッション: `INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`

## Build gotchas

- **workmanager 0.5.2 は Flutter 3.44 非互換** → 必ず 0.9.0+ を使用
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