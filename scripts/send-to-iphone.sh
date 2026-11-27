#!/bin/bash
# 取り込みテキスト(「#kadai v1」で始まるファイル)を Mac から iPhone のアプリへ直接送る。Mac 専用。
# クリップボードの共有(ユニバーサルクリップボード)がうまく働かないときの代わりの道。
#
#   scripts/send-to-iphone.sh                 # build/kadai-import.txt を、つないだ iPhone へ送る
#   scripts/send-to-iphone.sh 課題.txt        # 送るファイルを指定する
#   scripts/send-to-iphone.sh --simulator     # 起動中のシミュレーターへ送る(動作確認用)
#
# 送ったあとアプリを開くと、取り込みの確認画面が出る。
# 前提: iPhone が Mac にケーブルでつながっていて、ロックが解除されていること。
#       アプリは Xcode か xcodebuild で入れたもの(開発用の署名)であること。
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="io.github.kotakota914.KadaiNotify"
INBOX_NAME="import.txt"   # アプリ側の ImportInbox.fileName と同じ名前にする

TARGET="device"
FILE="build/kadai-import.txt"
for ARG in "$@"; do
  case "$ARG" in
    --simulator) TARGET="simulator" ;;
    *) FILE="$ARG" ;;
  esac
done

if [ ! -f "$FILE" ]; then
  echo "ファイルが見つかりません: $FILE" >&2
  exit 1
fi
# 1 行目が目印でなければ、アプリが読めないので送らない
if ! grep -v '^[[:space:]]*$' "$FILE" | head -1 | grep -q '^#kadai v1'; then
  echo "1 行目が「#kadai v1」ではありません: $FILE" >&2
  exit 1
fi
COUNT=$(grep -v '^[[:space:]]*$' "$FILE" | grep -vc '^#' || true)
echo "送るファイル: $FILE(提出物 $COUNT 行)"

if [ "$TARGET" = "simulator" ]; then
  # シミュレーターは Mac の中のフォルダなので、そのままコピーできる
  DATA=$(xcrun simctl get_app_container booted "$BUNDLE_ID" data)
  mkdir -p "$DATA/Documents"
  cp "$FILE" "$DATA/Documents/$INBOX_NAME"
  xcrun simctl terminate booted "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch booted "$BUNDLE_ID" > /dev/null
  echo "シミュレーターへ送りました。取り込みの確認画面が出ているはずです。"
  exit 0
fi

# つながっている実機を探す(行の例: "名前  00000000-0000000000000000  available (paired)  iPhone 15 ...  physical")
# 環境変数 KADAI_DEVICE に識別子を入れておくと、それを使う(実機が 2 台以上つながっているとき用)
DEVICE="${KADAI_DEVICE:-}"
if [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | grep 'physical' | grep -v 'unavailable' | grep -E 'available|connected' \
    | grep -Eo '[0-9A-F]{8}-[0-9A-F]{16}' | head -1 || true)
fi
if [ -z "$DEVICE" ]; then
  echo "つながっている iPhone が見つかりません。ケーブルでつなぎ、ロックを解除してからもう一度実行してください。" >&2
  exit 1
fi

# アプリの書類フォルダ(Documents)に import.txt として置く
xcrun devicectl device copy to --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --source "$FILE" --destination "Documents/$INBOX_NAME" --quiet
echo "iPhone へ送りました。"

# アプリを開く(ロック中などで開けなくても、次に手で開いたときに確認画面が出る)
if xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" --quiet 2>/dev/null; then
  echo "アプリを開きました。取り込みの確認画面を見てください。"
else
  echo "アプリを自動では開けませんでした。iPhone で「課題通知」を開くと、取り込みの確認画面が出ます。"
fi
