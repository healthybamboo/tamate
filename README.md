# tamate

開けないメモアプリ。書いたメモはすぐには読めず、開こうとしてから一定時間待って初めて本文が表示される。
待ち時間や再ロックの決まりは [docs/spec.md](docs/spec.md) にまとめてある。

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
│   ├── clock/                 # 現在時刻の取得口（テストで差し替える）
│   ├── notifications/         # ローカル通知。interface + 実装
│   ├── providers/             # 全体で使う Provider（SharedPreferences など）
│   ├── router/                # go_router のルート定義
│   └── theme/                 # Material 3 テーマ
├── features/
│   └── memo/
│       ├── domain/            # モデルと解錠ルール。Flutter に依存しない
│       ├── data/              # 永続化。interface + 実装
│       ├── application/       # 状態と操作（Riverpod Notifier）
│       └── presentation/      # 画面・ウィジェット
└── l10n/                      # .arb ファイル（generated/ は生成物なので追跡しない）
```

依存の向きは `presentation → application → data → domain` の一方向。domain は他の層を参照しない。

## 技術選定

| 領域 | 採用 | 補足 |
| --- | --- | --- |
| 状態管理・DI | `flutter_riverpod` | コード生成なしの手書き Provider |
| ルーティング | `go_router` | パスは `AppRoutes` に集約 |
| 永続化 | `shared_preferences` | `MemoRepository` の裏に隠しているので差し替え可能 |
| 多言語化 | `flutter_localizations` + `gen-l10n` | 日本語がテンプレート、英語も用意 |
| ローカル通知 | `flutter_local_notifications` + `timezone` | 解錠時刻ちょうどに知らせる。Android は正確なアラームを使い、許可が無ければ精度を落とす |
| Lint | `flutter_lints` + `riverpod_lint` | |

## 実装済みのもの

- メモの一覧・作成・削除、解錠中のみの編集
- 作成時に待機時間（1分 / 3分 / 5分 / 10分）を選択
- 「開く」から始まる待機と、1秒ごとに更新されるカウントダウン
- 待機画面を見ている間だけ進む待機（離れると止まり、戻れば続きから）
- 解錠から5分後の再ロック
- 解錠時刻のローカル通知と、通知タップで対象のメモを開くこと
- 4桁のコードの生成（スクリーンタイムなど外部のパスコード用。保存すると読み直すには待つ）
- 開封した回数と日時の記録。日付 × 時刻のグラフでの振り返り
- 開きすぎているメモへの提案（待機時間をのばす / 内容の見直し・削除）

解錠条件は `UnlockRule` として抽象化してあり、別の仕掛け（場所、回数など）を足すときは
実装を1つ増やして `UnlockRule.fromJson` に分岐を書けばよい。

## まだやっていないこと

- アプリアイコンとスプラッシュは Flutter の既定のまま
- Android のリリース署名は未設定（デバッグ鍵で署名される Flutter の初期状態のまま）。
  鍵と `key.properties` はリポジトリに含めない
- ストア提出物の準備

## ライセンス

MIT License（[LICENSE](LICENSE)）。依存パッケージはいずれも MIT / BSD 系のライセンス。
