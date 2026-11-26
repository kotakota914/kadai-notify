#!/bin/bash
# iOS シミュレーター(Mac の中の仮想 iPhone)でアプリをビルド・起動し、画面を撮る。Mac 専用。
#
#   scripts/run-simulator.sh            # 空のデータで起動
#   scripts/run-simulator.sh --sample   # サンプルの提出物を入れて起動
#
# 結果: build/simulator.png(スクリーンショット)、build/xcodebuild.log(ビルドのログ)
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="io.github.kotakota914.KadaiNotify"
LAUNCH_ARGS=()
if [ "${1:-}" = "--sample" ]; then LAUNCH_ARGS=(-seedSampleData); fi

# 使える iPhone シミュレーターの最初の 1 台を選ぶ(行の例: "    iPhone 16 (UDID) (Shutdown)")
LINE=$(xcrun simctl list devices available | grep -E '^ +iPhone' | head -1)
UDID=$(echo "$LINE" | grep -Eo '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
NAME=$(echo "$LINE" | sed -E 's/^ +//; s/ \(.*//')
if [ -z "$UDID" ]; then
  echo "iPhone のシミュレーターが見つかりません。Xcode > Settings > Components で iOS を入れてください。" >&2
  exit 1
fi
echo "シミュレーター: $NAME ($UDID)"

mkdir -p build
echo "ビルド中…(初回は数分かかります)"
if ! xcodebuild -project KadaiNotify.xcodeproj -scheme KadaiNotify -configuration Debug \
     -destination "id=$UDID" -derivedDataPath build/DerivedData build > build/xcodebuild.log 2>&1; then
  echo "ビルドに失敗しました。エラー:" >&2
  grep -E 'error:' build/xcodebuild.log | sort -u | head -40 >&2
  exit 1
fi
echo "ビルド成功"

xcrun simctl boot "$UDID" 2>/dev/null || true
# Simulator アプリの窓を開く。Xcode の版によっては Simulator.app が無いが、
# 窓が無くてもシミュレーター自体は動くので、失敗しても先へ進む。
open -a Simulator 2>/dev/null || echo "(Simulator アプリが見つからないため、窓は開かずに続けます)"
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl install "$UDID" build/DerivedData/Build/Products/Debug-iphonesimulator/KadaiNotify.app
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" ${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}
sleep 4
xcrun simctl io "$UDID" screenshot build/simulator.png > /dev/null
echo "スクリーンショット: build/simulator.png"
