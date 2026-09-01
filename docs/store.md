# ストア掲載物

App Store / Google Play に出すときの文面と、プライバシーの回答。

## 名前

- アプリ名: tamate
- サブタイトル: 開けないメモ

## 説明文（日本語）

書いたメモが、すぐには読めなくなるメモ帳です。

開こうとしても、決めた時間だけ画面の前で待たないと本文は出てきません。待っている間に
画面を離れると、待機は最初からやり直しになります。時間の代わりに、あるいは時間に加えて、
「今これを開いて後悔しないか」という問いを自分に投げてから開くこともできます。

思いついたことをすぐ引き出せるメモ帳の逆で、引き出しにくくするための道具です。

- 待機時間は 1分・3分・5分・10分から選べます
- 待つ前に自分へ投げる問いを、メモごとに何問でも登録できます
- スクリーンタイムのパスコードのように「覚えていては意味がない」値のために、4桁のコードを
  生成して預けられます
- いつ何回開いたかが記録され、日付 × 時刻の図で振り返れます
- 開きすぎているメモには、待機時間を延ばすか見直すかを提案します

データは端末の中だけに保存されます。アカウントの登録も、外部への送信もありません。

## 説明文（英語）

A notepad that makes what you wrote hard to read again.

Opening a memo starts a wait: the body stays hidden until you have spent that time on the
waiting screen. Leave the screen and the wait starts over. Instead of — or in addition to —
waiting, you can set questions to ask yourself before it opens.

It is the opposite of a notepad built for quick capture. It is a tool for putting things
out of reach.

## キーワード

メモ, 待つ, 集中, スクリーンタイム, 先延ばし, セルフコントロール, パスコード, 記録

## プライバシー

- **収集するデータ: なし。** メモの内容・開封の記録はすべて端末内（`SharedPreferences`）に
  保存され、外部に送信されない
- アカウント登録なし、広告なし、解析ツールなし
- 通信は書体の取得のみ。`google_fonts` が初回起動時に Google Fonts（`fonts.gstatic.com`）から
  フォントを取得してキャッシュする。ユーザーのデータは送信しない
- 権限の要求なし（通知・カメラ・位置情報など、いずれも使わない）

App Store のプライバシー質問には「データを収集しない」で回答する。Google Play のデータ
セーフティも同様に、収集も共有もなしで申告する。

## 対応環境

- iOS 12.0 以降
- Android 5.0 (API 21) 以降
- 対応言語: 日本語 / 英語
