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
