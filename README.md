# MornDesktopTube

アプリ内の専用ブラウザでYouTubeを再生し、そのままmacOSのデスクトップ背景へ表示します。macOS 14以降。外部ブラウザ・画面収録権限・外部ライブラリは不要です。

## 起動

ビルドにはXcodeまたはSwiftを含むCommand Line Toolsが必要です。

```sh
zsh build.sh
open dist/MornDesktopTube.app
```

1. メニューバーのアイコンを押し、ダッシュボードの「YouTube画面」を開きます。動画URLを入力して直接開くこともできます。
2. アプリ内で動画を選んで再生し、「背景に表示」を押します。
3. 音量・再生／一時停止・表示先・拡大・停止はダッシュボードで操作します。

Dockにはアイコンを表示しません。「YouTube画面」で背景のプレーヤーを操作ウィンドウへ戻せます。同じWebViewを移動するため、切り替え時に動画を再読み込みしません。操作ウィンドウを閉じると再生を停止します。背景に移した後は操作ウィンドウを開いておく必要はありません。

## GoogleログインとPremium

アプリ専用のWebKit永続データストアを利用します。ログインできた場合のCookieなどのサイトデータはアプリ内に保持されます。SafariやChromeのログイン状態は引き継ぎません。パスワードや既存ブラウザのCookieを取り込む機能はありません。

**Googleログインの成功とPremiumの適用は保証できません。** [Googleは埋め込みブラウザからのログインを制限しています](https://developers.googleblog.com/en/guidance-to-developers-affected-by-our-effort-to-block-less-secure-browsers-and-applications/)。アプリ内でログインが拒否された場合、セッションを保存する仕組みだけでは解決できません。外部ブラウザでOAuth認証しても、そのトークンをYouTubeのWebログインとして流用することはできません。

Premium契約のあるアカウントでログインできた場合は、[YouTubeのPremium特典](https://support.google.com/youtube/answer/6308116?hl=ja)が適用対象になります。アプリに広告ブロックや認証制限の回避機能はありません。

## 操作と制限

- 音量バーは**このアプリの動画だけ**を調整します。Mac全体やほかのアプリの音量は変更しません。0%で消音します。音量はダッシュボードの設定を優先し、YouTube側の音量復元による上書きを防ぎます。
- 「背景と再生を停止」は背景を隠し、実際のメディア再生も停止します。アプリ終了時も再生が終了します。
- 背景へのクリックは透過するため、デスクトップのアイコンを操作できます。
- 1つのプレーヤーを1台のディスプレイへ表示します。画質はYouTube側の設定に従います。
- 背景表示はYouTubeのHTMLプレーヤーを画面サイズに合わせます。YouTubeのページ構造が変わると調整が必要になる場合があります。動画内の広告やプレーヤーのエラーもそのまま表示されます。
- アプリ内のリンクは同じウィンドウで開きます。独立したタブやポップアップはありません。https以外へのページ移動は拒否します。
- 再起動後は動画を開き直します。配布用署名・公証・自動起動は含みません。

以前の外部ウィンドウのミラーリングとMac全体の音量調整は、単独再生への変更に伴い削除しました。

## 検証

```sh
swift test
zsh build.sh
codesign --verify --deep --strict dist/MornDesktopTube.app
```

ローカルの無音MP4をWebKitで実際に再生し、再生時間の進行、動画音量、WebViewの背景への移動、停止後の時間停止、URL検証、ダッシュボードの描画を確認します。macOSのWindowServerが必要です。テストは非永続データストアを使い、Googleアカウントへのログインや実際のYouTube認証は自動化しません。ダッシュボードのプレビューは `.build/dashboard-preview.png` に保存します。

テスト用の青色・無音動画 `Tests/MornDesktopTubeTests/Fixtures/blue.mp4` はFFmpegの `color=c=blue:s=64x36:r=10` から生成した2秒のH.264動画です。テスト実行時にFFmpegは不要です。
