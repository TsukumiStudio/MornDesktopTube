# MornDesktopTube 画像素材

- `ogp.psd` / `ogp.png`: 1200 × 630。レイアウト・フォント・文字サイズは MornStorage の `design/ogp.psd` に揃えている。文字・バッジ・ウィンドウは個別レイヤーのまま。
- `icon.psd` / `icon.png`: 1024 × 1024。macOS アイコン規格の角丸スクエア (824px、四隅は透明) をクリーム色 (#FDF7E6) で塗り、その中にオリーブ (#71782C) の角丸タイル + ライム (#C9D249) の再生三角を配置 (MornStorage と同じ配色)。`icon.psd` は画像を収めたラスターレイヤー形式。
- OGP はルート README と GitHub の Social preview に使用。`icon.png` から作成した `Support/AppIcon.icns` を `build.sh` でアプリに同梱する (16・32・128・256・512px と各 2 倍解像度)。アイコン変更時は ICNS も更新する:

```sh
mkdir -p /tmp/icon.iconset
for n in 16 32 128 256 512; do
  sips -z $n $n design/icon.png --out /tmp/icon.iconset/icon_${n}x${n}.png >/dev/null
  sips -z $((n*2)) $((n*2)) design/icon.png --out /tmp/icon.iconset/icon_${n}x${n}@2x.png >/dev/null
done
iconutil -c icns /tmp/icon.iconset -o Support/AppIcon.icns
```
