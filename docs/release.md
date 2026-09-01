# リリース手順

ストアに出すまでにやることと、その手順。鍵とアカウントが要るものは、こちらでは触れないので
手元で実行する。

## アイコンとスプラッシュ

素材は持ち込まず、テーマと同じ色で描き出している。作り直すときは:

```bash
flutter test tool/generate_app_icon.dart   # assets/icon/ に書き出す
dart run flutter_launcher_icons             # 各サイズのアイコンを生成
dart run flutter_native_splash:create       # スプラッシュを生成
```

図案は玉手箱を横から見た形で、もとの SVG は `assets/icon/icon-*.svg`（dark / light / mono）。
`tool/generate_app_icon.dart` はこの SVG と同じ図形（円と横棒）を描き直しているので、
図案を変えるときは両方を直す。色は背景 `#1B1F2A`、図案 `#C4A87C`。

## Android のリリース署名

鍵はリポジトリに入れない。`android/key.properties` があればそれを使い、無ければデバッグ鍵の
ままビルドが通るようにしてある（`android/app/build.gradle`）。

1. 鍵を作る。パスワードは自分で決めて、鍵ごと安全な場所に保管する

    ```bash
    keytool -genkey -v -keystore ~/tamate-upload.jks \
      -keyalg RSA -keysize 2048 -validity 10000 -alias upload
    ```

2. `android/key.properties` を作る（このファイルは `.gitignore` 済み）

    ```properties
    storePassword=<作成時に決めたパスワード>
    keyPassword=<同上>
    keyAlias=upload
    storeFile=/Users/<自分>/tamate-upload.jks
    ```

3. ビルドする

    ```bash
    flutter build appbundle --release
    ```

    出力: `build/app/outputs/bundle/release/app-release.aab`

鍵を無くすと同じアプリとして更新できなくなる。Play Console の「アプリ署名」を使うと、
アップロード鍵を無くしても再登録できるので有効にしておく。

## iOS の実機確認とビルド

1. `open ios/Runner.xcworkspace` で Xcode を開く
2. Runner → Signing & Capabilities → Team に自分の Apple Developer アカウントを指定する
   （Bundle ID は `net.bamgrove.tamate`）
3. 実機を繋いで Xcode から実行する。または

    ```bash
    flutter run --release -d <device-id>
    ```

4. 提出用は Xcode の Product → Archive から。または

    ```bash
    flutter build ipa --release
    ```

CocoaPods が壊れている場合は `brew upgrade cocoapods` で直る（Homebrew の ruby を上げたまま
cocoapods を入れ直していないと、gem の解決に失敗する）。

## リリースの流れ

`wageria` と同じ形にしてある。バージョンを決めるのは GitHub Actions、ビルドと配信は
Codemagic、その間をつなぐのが「リリース用のプルリクエスト」。

```
   main
    │  Actions: Release を手動で実行（種類 major/minor/patch を選ぶ）
    ├─ 解析とテスト
    ├─ pubspec.yaml のバージョンとビルド番号を更新して push
    ├─ タグ <version> を打つ / ドラフトのリリースノートを作る
    ├─ release/<version> ブランチを作る
    └─ release/<version> → release/ios へ PR を作る
                            │  Codemagic が PR を見てビルド開始
                            ├─ 解析・テスト・ipa
                            ├─ TestFlight へ配信
                            └─ 中身を確かめて PR をマージする
```

- **リリース用のブランチを分けている理由**: リリース中でも `main` にマージしてよくするため。
  リリースは `release/<version>` の内容で固定される
- **PR が1つだけである理由**: デプロイ用ブランチに複数の PR があると、どれをマージすべきか
  分からなくなる。新しいリリースを作ると、古い PR は自動で閉じる
- ビルド番号は Codemagic 側でも TestFlight の最新 + 1 を振るので、番号が重なることはない

### 実行のしかた

1. GitHub の Actions → **Release** → Run workflow
2. `release_type` を選ぶ（バージョンを直接入れる場合は `release_version` に書く）
3. iOS / Android のどちらを出すか選ぶ（Android は Codemagic 側の設定が済むまで off）
4. しばらくすると `[リリース][ios] version: x.y.z` という PR ができる
5. Codemagic のビルドが終わり、TestFlight に届いたのを確認したら PR をマージする
6. ドラフトのリリースノートを整えて公開する

### 一度だけやること

**GitHub 側**

- `release/ios`（Android も出すなら `release/android`）ブランチを作っておく。PR の宛先になる
- ラベル `リリース` / `ios` / `android` を作っておく（PR に付ける）

**Apple 側**

1. **Apple Developer Program に加入する**（年 99 USD）。これが無いと TestFlight に配れない
2. **App Store Connect でアプリを登録する**
   - プラットフォーム: iOS、Bundle ID: `net.bamgrove.tamate`、名前: `tamate`
   - Bundle ID が Developer ポータルに無ければ、Certificates, Identifiers & Profiles で先に作る
3. **App Store Connect API キーを作る**
   - App Store Connect → Users and Access → Integrations → App Store Connect API
   - アクセス権は「App Manager」。発行された `.p8` は一度しか落とせないので保管する

**Codemagic 側**

4. Teams → Integrations → App Store Connect に上のキーを追加する。
   **名前は `tamate` にする**（`codemagic.yaml` がこの名前で参照している。変えるなら
   `environment.integrations.app_store_connect` も直す）
5. Applications からこのリポジトリを追加する。`codemagic.yaml` は自動で読まれる
6. 署名は Codemagic に任せる（`ios_signing.distribution_type: app_store`）。証明書と
   プロビジョニングプロファイルは API キー経由で取得・作成される。手元の鍵は要らない

Android も出すなら、Google Play のサービスアカウント（`GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`）と
アップロード鍵を Codemagic のグループ `google_play` / `tamate_upload` に入れる。

### 注意

- `flutter: 3.27.1` を Codemagic と GitHub Actions の両方で固定してある。上げるときは両方直す
- 輸出コンプライアンスの質問を毎回出さないよう、`Info.plist` に
  `ITSAppUsesNonExemptEncryption = false` を入れてある。通信は書体の取得（HTTPS）だけなので
  この申告で足りる

## ストア提出物

掲載文とプライバシーの回答は `docs/store.md` にまとめてある。

スクリーンショットはシミュレータから撮る。App Store は 6.9 インチ（1320×2868）が必須。

```bash
xcrun simctl boot "iPhone 16 Pro Max"
xcrun simctl launch <udid> net.bamgrove.tamate
xcrun simctl io <udid> screenshot shot.png
```

撮る画面は次の4枚を想定している。

1. 一覧（ロック中・待機中・解錠中が並んだ状態）
2. 待機画面（カウントダウン）
3. 問いかけ
4. 開封の記録（日付 × 時刻の図）
