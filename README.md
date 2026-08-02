# tamate

開けないメモアプリ

## 環境

- Flutter 3.27.1 / Dart 3.6
- 対応プラットフォーム: iOS / Android
- Bundle ID: `net.bamgrove.tamate`

## セットアップ

```bash
flutter pub get
flutter gen-l10n
flutter run
```

## 開発コマンド

| 目的 | コマンド |
| --- | --- |
| 静的解析 | `flutter analyze` |
| テスト | `flutter test` |
| ローカライズ生成 | `flutter gen-l10n` |
| Android デバッグビルド | `flutter build apk --debug` |
| iOS デバッグビルド | `flutter build ios --debug --no-codesign` |

## ディレクトリ構成

feature 単位で切り、各 feature を presentation / application / domain / data の4層に分ける。

```
lib/
├── main.dart                  # エントリポイント。DI の初期化のみ
├── app.dart                   # MaterialApp.router
├── core/                      # 機能横断の基盤
│   ├── providers/             # 全体で使う Provider（SharedPreferences など）
│   ├── router/                # go_router のルート定義
│   └── theme/                 # Material 3 テーマ
├── features/
│   └── memo/
│       ├── domain/            # モデル。外部ライブラリに依存しない
│       ├── data/              # 永続化。interface + 実装
│       ├── application/       # 状態と操作（Riverpod Notifier）
│       └── presentation/      # 画面・ウィジェット
└── l10n/                      # .arb と生成物（generated/）
```

依存の向きは `presentation → application → data → domain` の一方向。domain は他の層を参照しない。

## 技術選定

| 領域 | 採用 | 補足 |
| --- | --- | --- |
| 状態管理・DI | `flutter_riverpod` | コード生成なしの手書き Provider |
| ルーティング | `go_router` | パスは `AppRoutes` に集約 |
| 永続化 | `shared_preferences` | `MemoRepository` の裏に隠しているので差し替え可能 |
| 多言語化 | `flutter_localizations` + `gen-l10n` | 日本語がテンプレート、英語も用意 |
| Lint | `flutter_lints` + `riverpod_lint` | |

## 実装済みのもの

メモの一覧・作成・編集・削除が動く最小の縦切り。アーキテクチャの見本として置いてあるので、
本実装で作り込む際はこの構成に沿って差し替える。
