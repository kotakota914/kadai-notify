# CLAUDE.md(このリポジトリで作業する Claude 向けメモ)

自分専用の iOS アプリ「KadaiNotify(課題通知)」。大学の提出物の締め切りをローカル通知で知らせる。
仕様は `docs/REQUIREMENTS.md`、使い方は `README.md`。

## 作業の決まり
- 応答は日本語。ユーザーはプログラミング学習中の大学 1 年生なので、コードを変えたら何をしたかを初学者向けに短く説明し、専門用語は初出時に一言補足する。
- 追加のライブラリは使わない(SwiftUI / SwiftData / UserNotifications / WidgetKit のみ)。iOS 18 以上、Swift 5 モード。
- 画面に依存しない計算は `Packages/KadaiCore` に置き、テストを書く。
- 仕様を変えたら `docs/REQUIREMENTS.md` の該当箇所と「11. 決定事項の記録」も更新する。
- 公開リポジトリになる予定。個人情報(氏名・学籍番号・メールアドレス・実在の課題データ)や `DEVELOPMENT_TEAM` の変更をコミットしない。

## ビルド・確認(Mac のみ)
- テスト: `cd Packages/KadaiCore && swift test`
- シミュレーターで起動して画面を撮る: `scripts/run-simulator.sh --sample`
  - 成功すると `build/simulator.png` ができるので、Read で画像を見て確認する。
  - 失敗したら `build/xcodebuild.log` の `error:` 行を見て直し、もう一度実行する。
  - `--sample` はサンプルの提出物を入れて起動する(データが空のときだけ)。
- 実機への転送は Xcode の ▶ で行う(署名に Apple ID が必要なため、ユーザーが操作する)。

## 構成
- `Packages/KadaiCore/` … 通知の計算(`NotificationPlanner`)、取り込みの読み取り(`ImportParser`)、繰り返し(`RecurrenceGenerator`)、表示の文字(`DeadlineText`)
- `Shared/` … SwiftData のモデル。アプリとウィジェットの両方でコンパイルされる
- `KadaiNotify/` … アプリ本体。データが変わったら必ず `Refresher.refresh(context)` を呼ぶ(通知の予約し直し・バッジ・ウィジェット更新)
- `KadaiNotifyWidget/` … ウィジェット
- `KadaiNotify.xcodeproj` … フォルダ同期型(objectVersion 77)。ファイルを足すだけでターゲットに入る
