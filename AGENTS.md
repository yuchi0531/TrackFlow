# AGENTS.md

## Project overview

TrackFlow - ヤマト運輸・佐川急便・日本郵便 統合荷物追跡アプリ。3社の公式HTML追跡ページをスクレイピングして配送状況を取得する Flutter アプリ。個人向け公開APIは存在しない。

**Android only**（iOSディレクトリ削除済み）。

## Setup commands

```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs  # Drift ORMコード生成
flutter build apk --release                                      # リリースAPK (29.8MB)
```

Flutter SDK パス: `/home/yuchi0531/flutter`

環境変数:
```bash
export JAVA_HOME=$HOME/jdk17
export ANDROID_HOME=$HOME/android-sdk
export PATH=$HOME/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH
```

## Tech stack

| 層 | 技術 |
|---|---|
| Framework | Flutter 3.44 (Dart 3.12) |
| State | Riverpod 2 (flutter_riverpod) |
| Router | go_router 14 (ShellRoute + NavigationBar) |
| DB | Drift 2.28 (SQLite via NativeDatabase) |
| Theme | Material Design 3 (ColorScheme.fromSeed, #1565C0) |
| HTTP | http 1.6 + html 0.15 |
| Background | workmanager 0.9.0 (registerPeriodicTask, callbackDispatcher) |
| Notifications | flutter_local_notifications |
| Scraping | 日本郵便(GET) / ヤマト(POST, swd.writeln再構築) / 佐川(POST, 装飾文字トリム) |
| Build | R8無効 (isMinifyEnabled=false), desugar_jdk_libs:2.1.4 |

## Project structure

```
lib/
├── main.dart                            # ProviderScope
├── app.dart                             # MaterialApp.router
├── core/
│   ├── theme/app_theme.dart             # CardThemeData (not CardTheme), M3
│   └── constants/carrier_urls.dart      # 3社スクレイピングURL
├── domain/
│   ├── entities/                        # Carrier enum, TrackingInfo, TrackingEvent (freezed不使用)
│   └── repositories/                    # 抽象インターフェース
├── data/
│   ├── scraping/                        # JapanPostTracker, YamatoTracker, SagawaTracker, TrackerFactory
│   ├── local/database.dart              # Drift (SavedTrackings, TrackingHistories, TrackingEventEntries)
│   └── repositories/                    # TrackingRepositoryImpl (キャッシュフォールバック付き)
├── provider/
│   ├── database_provider.dart           # FutureProvider<AppDatabase>
│   ├── tracking_repository_provider.dart
│   ├── tracking_providers.dart          # trackingList, trackingDetail, addTracking, deleteTracking
│   └── background_provider.dart         # Workmanager + 通知 (callbackDispatcher)
└── presentation/
    ├── router/app_router.dart           # ShellRoute + NavigationBar (追跡一覧/設定)
    ├── tracking_list/                   # 一覧 + Dismissibleスワイプ削除 + 色付きインジケーター
    ├── add_tracking/                    # 番号入力 + CarrierSelector + 自動判別
    ├── detail/                          # タイムライン + StatusHeader + DeliveryEstimate
    └── settings/                        # 更新間隔選択 + 通知トグル + プライバシーポリシー
```

## Code conventions

- **非nullSafe全体に注意**: `html/parser.dart` の `parse` が各Trackerの `parse` メソッドと衝突 → `import 'package:html/parser.dart' as html_parser;`
- **ドメインEntity**: freezed 不使用。Driftのgenerated codeと衝突するため。素のDartクラス。
- **Driftテーブル名**: `TrackingEventEntries` を使用（`TrackingEvents` はdomainの `TrackingEvent` と衝突）
- **DB構築**: `AppDatabase.create()` 非同期ファクトリ（`LazyDatabase` 不使用）、フォールバックに `AppDatabase.inMemory()`
- **Provider**: `FutureProvider` + `.future` で非同期DBアクセスを解決
- **ナビゲーション**: タブ外画面は `context.push()`（`context.go()` はスタック破壊）
- **テーマ**: `CardThemeData`（`CardTheme` は Flutter 3.44 でdeprecated）
- **アイコン**: adaptive icon（`drawable/ic_launcher_foreground.png` 円形、`ic_launcher_background.png` #FDFDFD）
- **minSdk**: 24（Flutter/pluginが自動引き上げ）

## Testing instructions

```bash
dart analyze lib/     # 静的解析（コミット前に必須）
flutter build apk --release  # リリースビルド確認
```

## Build gotchas

- **workmanager 0.5.2 は Flutter 3.44 非互換** → 必ず 0.9.0+ を使用
- **Gradleビルドキャッシュ破損**: ディスク空き容量不足時（100% full）に不完全APKが生成される。最低2GB確保
- **デバッグビルド**: `isCoreLibraryDesugaringEnabled=true` と `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")` が必須
- **ProGuard**: `isMinifyEnabled=false`（Drift/Workmanager生成コード破壊防止）

## Carrier scraping details

| 会社 | HTTP | URL |
|------|------|-----|
| 日本郵便 | GET | `trackings.post.japanpost.jp/services/srv/search/direct?reqCodeNo1=XXX&locale=ja` |
| ヤマト運輸 | POST | `toi.kuronekoyamato.co.jp/cgi-bin/tneko` (body: `number00=1&number01=XXX`) |
| 佐川急便 | POST | `k2k.sagawa-exp.co.jp/p/web/okurijosearch.do` (body: `okurijoNo=XXX`) |

- ヤマト: JS組立てページ → `swd.writeln('...')` 正規表現抽出 → `\<` → `<` エスケープ解除
- 佐川: ステータス装飾文字（`↓⇒\u3000`）トリム
- 日本郵便: `table.tableType01` 2つ目からtrパース
- User-Agent: `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15`
- 追跡番号自動判定: 11-13桁 → 日本郵便, 12桁 → ヤマト

## Android manifest

必須パーミッション: `INTERNET`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`

## Security

- 個人情報非収集、全データは端末内 SQLite のみ
- ネットワーク通信は配送会社公式サイトのみ
- APIキー不要（全て公開ページのHTMLスクレイピング）
- HTML構造変更により追跡失敗の可能性あり → TrackerException でエラーハンドリング
