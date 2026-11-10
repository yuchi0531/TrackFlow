# TrackFlow

ヤマト運輸・佐川急便・日本郵便・エスポ便の4社を統合的に追跡できる荷物追跡アプリ。

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Material_Design-3-757575?logo=material-design" alt="Material Design 3">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/platform-Android-lightgrey" alt="Platform">
</p>

## 機能

| 機能 | 内容 |
|------|------|
| 📦 4社統合追跡 | ヤマト運輸・佐川急便・日本郵便・エスポ便の荷物を1つのアプリで追跡 |
| 🔍 自動判別 | 追跡番号を入力するだけで配送会社を自動判定（`E`+11桁のエスポ便も書式が一意なので判別可能） |
| 🔗 URL貼り付け | 追跡番号の代わりに各社の追跡URLを貼り付けても登録できる |
| 📋 履歴管理 | 追跡した荷物を保存し、一覧で管理。「配達中」と「終了済」に自動で分けて表示 |
| 🔔 バックグラウンド更新 | 定期的に配送状況を自動取得し、変更があれば通知 |
| 🌓 ダークモード | Material Design 3 Dynamic Color 対応 |

## スクリーンショット

| 追跡一覧 | 追跡詳細 | 追跡追加 |
|----------|----------|----------|
| 空の状態 / 一覧表示 | タイムライン表示 | 番号入力 + 自動判別 |

## 技術スタック

- **Framework**: Flutter 3.44 (Dart 3.12)
- **状態管理**: Riverpod 2
- **ルーティング**: go_router (ShellRoute + NavigationBar)
- **データベース**: Drift (SQLite)
- **HTTP**: http 1.3 + html 0.15 + dart:convert（エスポ便の JSON API 用）
- **テーマ**: Material Design 3 (Light / Dark)
- **バックグラウンド**: Workmanager
- **通知**: flutter_local_notifications

## アーキテクチャ

```
lib/
├── core/             # テーマ・定数
├── domain/           # エンティティ・リポジトリインターフェース
├── data/             # スクレイピング + JSON API・DB・リポジトリ実装
├── provider/         # Riverpodプロバイダー
└── presentation/     # UI (router / 画面 / widgets)
```

## スクレイピング

個人向け公開APIは存在しないため、各社の公式追跡ページから情報を取得しています。
日本郵便・ヤマト運輸・佐川急便は **HTMLのスクレイピング**、エスポ便は **ページ内部のJSON API** を利用します。

| 配送会社 | Method | URL |
|----------|--------|-----|
| 日本郵便 | GET | `trackings.post.japanpost.jp` |
| ヤマト運輸 | POST | `toi.kuronekoyamato.co.jp` |
| 佐川急便 | POST | `k2k.sagawa-exp.co.jp` |
| エスポ便 | POST (JSON) | `www.console.espoirer.com/prod/other/status` |

### HTMLスクレイピング（日本郵便・ヤマト運輸・佐川急便）

- **日本郵便**: `reqCodeNo1` / `searchKind` をクエリに付けて GET
- **ヤマト運輸**: `number00=1&number01=<番号>` を POST（JS組み立てページの文字列を抽出）
- **佐川急便**: `okurijoNo=<番号>` を POST

### エスポ便のJSON API

追跡ページ `https://www.console.espoirer.com/express-tracking` は React SPA のため HTML から情報を取得できません。ページが内部で呼び出している `POST https://www.console.espoirer.com/prod/other/status` を直接利用します（**認証不要**）。

- リクエスト: `Content-Type: application/json`、body は **`{"data":{"hawbNoList":["<追跡番号>"]}}`**（`data` でラップする。ラップせずに送ると HTTP 200 のまま `result` が空になり追跡できない）
- レスポンス: ラップされておらず `result[]` がルート直下。各要素の `orderTrackVoList[]` が履歴。HTTP 200 でも `orderTrackVoList` が null の場合は「該当なし」として扱う
- 履歴の各要素は `orderStatus` に日本語のステータス文言がそのまま入っているため、非null・非空ならそれを優先する（空の場合のみ `orderTrackType` のコードから文言を引く）。`createTime`（ISO8601 / `yyyy-MM-dd HH:mm:ss`）の昇順で並べる
- 実際に返る `orderTrackType` は `5001`（集荷）〜`5031`（積込失敗-その他）の5000番台
- 配達予定日は API が返さないため `null` になる

このアプローチは [TsuiseKit](https://github.com/Shakshi3104/TsuiseKit) を参考にDartへ移植したものです（エスポ便は除く）。

## セットアップ

```bash
# 依存関係のインストール
flutter pub get

# コード生成 (Drift ORM)
flutter pub run build_runner build --delete-conflicting-outputs

# デバッグ実行
flutter run

# リリースビルド
flutter build apk --release
```

Android 14以降でビルドする場合、`android/app/build.gradle.kts` に以下が必要です：
```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

## ライセンス

MIT License © 2026 yuchi0531
