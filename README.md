# TrackFlow

ヤマト運輸・佐川急便・日本郵便の3社を統合的に追跡できる荷物追跡アプリ。

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart" alt="Dart">
  <img src="https://img.shields.io/badge/Material_Design-3-757575?logo=material-design" alt="Material Design 3">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey" alt="Platform">
</p>

## 機能

| 機能 | 内容 |
|------|------|
| 📦 3社統合追跡 | ヤマト運輸・佐川急便・日本郵便の荷物を1つのアプリで追跡 |
| 🔍 自動判別 | 追跡番号を入力するだけで配送会社を自動判定 |
| 📋 履歴管理 | 追跡した荷物を保存し、一覧で管理 |
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
- **テーマ**: Material Design 3 (Light / Dark)
- **バックグラウンド**: Workmanager
- **通知**: flutter_local_notifications

## アーキテクチャ

```
lib/
├── core/             # テーマ・定数
├── domain/           # エンティティ・リポジトリインターフェース
├── data/             # スクレイピング・DB・リポジトリ実装
├── provider/         # Riverpodプロバイダー
└── presentation/     # UI (router / 画面 / widgets)
```

## スクレイピング

各社とも個人向け公開APIが存在しないため、公式追跡ページのHTMLをスクレイピングしています。

| 配送会社 | Method | URL |
|----------|--------|-----|
| 日本郵便 | GET | `trackings.post.japanpost.jp` |
| ヤマト運輸 | POST | `toi.kuronekoyamato.co.jp` |
| 佐川急便 | POST | `k2k.sagawa-exp.co.jp` |

このアプローチは [TsuiseKit](https://github.com/Shakshi3104/TsuiseKit) を参考にDartへ移植したものです。

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
