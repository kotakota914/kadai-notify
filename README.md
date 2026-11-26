# KadaiNotify(課題通知)

大学の提出物(課題・レポート)を登録しておくと、締め切りが近づいたときに iPhone に通知が来るアプリです。自分専用で、サーバーは使いません。

- 締め切りの **3 日前・1 日前の 21:00** に通知(科目ごと・課題ごとに変更できる)
- 未完了の課題がある限り、**毎晩 21:00 にまとめて通知**(完了チェックを付けると止まる)
- 学生ポータルの課題を Mac の Claude in Chrome で探して、**コピー&貼り付けでまとめて登録**
- 科目ごとの色分け、毎週の繰り返し課題、アイコンの数字(未完了の件数)、ホーム画面ウィジェット

詳しい仕様は [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)(要件定義書)にあります。

```
学生ポータル ──(Mac の Claude in Chrome が探す)──▶ 「#kadai v1」形式の文字
                                                      │ Mac でコピー → iPhone で貼り付け
                                                      ▼
                                         KadaiNotify(iPhone)──▶ ローカル通知・バッジ・ウィジェット
```

> **注意:** このコードは Xcode のない Linux マシン(DGX)で書いたので、まだ一度もビルドしていません。
> 最初のビルドでエラーが出たら、エラー文をそのまま Claude に貼って直してもらってください。

---

## 1. 必要なもの

| もの | 説明 |
|---|---|
| Mac | macOS 15(Sequoia)以降がおすすめ |
| Xcode | Mac の App Store から無料で入れる(16 以降。10GB 以上あるので時間がかかる) |
| iPhone | iOS 18 以降。USB ケーブル |
| Apple ID | いつもの Apple ID でよい。**有料の Developer Program(年 99 ドル)は不要** |

---

## 2. コードを Mac に持ってくる

コードの最新版は DGX にあり、GitHub を通して Mac とそろえます。

```bash
git clone https://github.com/kotakota914/kadai-notify.git
```

2 回目からは、そのフォルダの中で次のコマンドを実行すると最新になります。

```bash
git pull
```

---

## 3. Xcode で開いて署名を設定する(最初の 1 回だけ)

1. Finder で `KadaiNotify.xcodeproj` をダブルクリックして Xcode で開く。
   - 左の一覧に `KadaiCore`(パッケージ)が出るまで少し待つ。
2. Xcode のメニュー **Xcode > Settings… > Accounts** の左下「+」から、自分の Apple ID を追加する。
3. 左の一覧の一番上の青いアイコン「KadaiNotify」をクリック → 中央の **TARGETS** で `KadaiNotify` を選ぶ → 上のタブ **Signing & Capabilities**。
   - 「Automatically manage signing」にチェック
   - **Team** で「(自分の名前) (Personal Team)」を選ぶ
4. **TARGETS** の `KadaiNotifyWidgetExtension` でも、3 と同じように Team を選ぶ。

> **署名(しょめい)とは:** 「このアプリは誰が作ったか」を Apple の仕組みで証明すること。iPhone は署名のないアプリを動かしません。

### 「Failed to register bundle identifier」と出たとき

バンドル ID(アプリの世界で 1 つだけの名前)が、ほかの人と重なっています。次の **6 か所** を、同じ別の名前に変えてください(例: `io.github.kotakota914` → `io.github.kotakota914.app`)。

| 場所 | 変える値 |
|---|---|
| TARGETS `KadaiNotify` > Signing & Capabilities > Bundle Identifier | `….KadaiNotify` |
| TARGETS `KadaiNotifyWidgetExtension` > 同じ所 | `….KadaiNotify.Widget`(アプリの ID + `.Widget` にする) |
| `Config/KadaiNotify.entitlements` | `group.….KadaiNotify` |
| `Config/KadaiNotifyWidget.entitlements` | `group.….KadaiNotify` |
| `Shared/SharedStore.swift` の `AppGroup.identifier` | `group.….KadaiNotify` |
| (確認)Signing & Capabilities の App Groups 欄 | 上と同じ名前にチェックが入っていること |

> **App Group とは:** アプリとウィジェットが同じデータを読むための共有フォルダ。

---

## 4. iPhone に入れる

1. iPhone を USB ケーブルで Mac につなぐ。iPhone に「このコンピュータを信頼しますか?」と出たら **信頼**。
2. iPhone で **設定 > プライバシーとセキュリティ > デベロッパモード** をオン → 再起動 → もう一度オンにする。
3. Xcode の上部中央(実行先)で、自分の iPhone を選ぶ。
4. 左上の **▶(Run)** ボタンを押す。初回はビルドに数分かかる。
5. iPhone に「信頼されていないデベロッパ」と出たら:
   **設定 > 一般 > VPN とデバイス管理** → 「Apple Development: (自分の Apple ID)」→ **信頼**。もう一度 ▶。
6. アプリが開いたら「通知を送信します」の確認で **許可** を押す。
7. **設定** タブ → 「テスト通知を送る(5 秒後)」でホーム画面に戻り、通知が来るか確かめる。

### ウィジェットを置く

ホーム画面の何もない所を長押し → 左上の「編集」→「ウィジェットを追加」→「課題通知」→ 小か中を選ぶ。

---

## 5. 7 日ごとの入れ直し(無料の Apple ID の場合)

無料の Apple ID で入れたアプリは、**入れてから 7 日で開けなくなります**。

- 期限の前日 21:00 にアプリが「明日期限が切れます」と通知します。期限は **設定 > アプリの署名** でも見られます。
- 入れ直しは、Mac で Xcode を開いて **▶ を押すだけ**。**登録した課題は消えません**。
- **アプリを iPhone から削除すると、データは全部消えます**。削除はしないでください。
- ケーブルなしで入れたい場合: Xcode の **Window > Devices and Simulators** で iPhone を選び「Connect via network」にチェック。以後は同じ Wi-Fi にいれば ▶ で入ります。

---

## 6. 学生ポータルの課題を取り込む

1. iPhone のアプリの **設定** タブ → 「Claude への頼み方をコピー」(内容は [docs/REQUIREMENTS.md の 7.4](docs/REQUIREMENTS.md#74-claude-in-chrome-への頼み方テンプレート) と同じ)。
2. Mac の Chrome で学生ポータルを開き、Claude in Chrome に 1 の文を渡す。次のような文字が出てくる:
   ```
   #kadai v1
   情報システム | 第8回レポート | 2026-12-03 17:00 | A4 2枚、Moodleに提出
   PD入門 | 振り返りシート | 2026-12-05 | 
   ```
3. Mac でその文字をコピー(⌘C)。
4. iPhone のアプリで **提出物** タブ左上の「取り込み」→「ペースト」。
5. 確認画面で内容を見て(登録済みのものは最初からチェックが外れています)、右上の「◯件を登録」。

> Mac でコピーしたものを iPhone で貼り付けられるのは、Apple の **ユニバーサルクリップボード** という機能です。
> 両方で同じ Apple ID にサインインし、Bluetooth と Wi-Fi をオンにし、**設定 > 一般 > AirPlay と連係** の「Handoff」をオンにしておきます。

時刻が書かれていない締め切りは 8:50(1 限の前)として登録します(設定で変更できます)。

---

## 7. Claude の中でシミュレーターを動かす(Mac)

iPhone を使わずに、Mac の中の仮想 iPhone(**iOS シミュレーター**)で動きを確かめられます。署名(Apple ID)も不要です。

1. Mac で Claude デスクトップアプリを開き、**Code** タブでこのフォルダ(`kadai-notify`)を選ぶ。
2. 「シミュレーターで起動して画面を見せて」と頼む。
   - Claude は `scripts/run-simulator.sh --sample` を実行します(手順は `CLAUDE.md` に書いてあります)。
   - ビルド → シミュレーター起動 → サンプルの提出物を入れてアプリを起動 → 画面を撮って `build/simulator.png` に保存、までを自動で行います。
   - ビルドエラーが出たら、Claude がログを読んでそのまま直せます。
3. Mac の画面に出たシミュレーターは、マウスで iPhone と同じように操作できます。

自分のターミナルで動かす場合:

```bash
scripts/run-simulator.sh --sample
```

> シミュレーターではアプリの署名期限(F-12)は表示されません。通知はシミュレーターでも鳴ります(設定タブの「テスト通知」で確認できます)。

### Mac がなくても触れる試作(ブラウザ)

`prototype/index.html` は、画面の流れと通知のタイミングをブラウザで試せる HTML 版の試作です(Swift のコードは動かず、同じ計算を JavaScript で再現したもの)。
右側の「時計」を進めると、予約された通知が iPhone の枠の中に届きます。ブラウザでファイルを開くだけで動きます。

---

## 8. テストを動かす(Mac のターミナル)

通知のタイミングの計算や、取り込みの読み取りなど、画面に関係ない部分は `Packages/KadaiCore` にまとめてあり、テストがあります。

```bash
cd Packages/KadaiCore && swift test
```

---

## 9. 仕組み(コードの読み方)

| フォルダ | 中身 |
|---|---|
| `Packages/KadaiCore/` | 画面に関係ない計算(通知の日時、まとめ通知の文面、取り込みの読み取り、繰り返し、残り時間の表示)。テスト付き |
| `Shared/` | 保存するデータの形(課題・科目・繰り返し)。アプリとウィジェットの両方で使う |
| `KadaiNotify/` | アプリ本体の画面(SwiftUI)と、通知の予約 |
| `KadaiNotifyWidget/` | ホーム画面ウィジェット |
| `Config/` | 署名や App Group の設定ファイル |
| `docs/` | 要件定義書 |

使っている Apple の技術(追加のライブラリは使っていません):

- **SwiftUI** … 画面を「こう見えてほしい」と書くと iOS が描いてくれる仕組み
- **SwiftData** … データを iPhone の中に保存する仕組み
- **UserNotifications(ローカル通知)** … サーバーなしで、iPhone の中で時刻を予約して通知を鳴らす仕組み。1 つのアプリが予約できるのは 64 件まで
- **WidgetKit** … ホーム画面ウィジェット

通知の流れ: アプリを開いたときや課題を変えたときに `Refresher.refresh` が呼ばれ、
`NotificationPlanner`(KadaiCore)が「これから鳴らす通知(最大 64 件)」を計算し、
`NotificationService` が iOS に全部予約し直します。
まとめ通知は 14 晩先まで予約するので、**2 週間アプリを開かないと止まります**(最後の通知でお知らせします)。

---

## 10. 困ったとき

| 症状 | 対処 |
|---|---|
| 「Failed to register bundle identifier」 | 3 章のとおりバンドル ID を変える |
| 「The maximum number of apps for free development profiles has been reached」 | 無料の Apple ID で入れられる自作アプリは 3 つまで。使っていない自作アプリを iPhone から消す |
| 「信頼されていないデベロッパ」 | 4 章の 5 |
| アプリが開かない(すぐ閉じる) | 署名の期限切れ。Mac から ▶ で入れ直す |
| 通知が来ない | iPhone の **設定 > 通知 > 課題通知** で許可されているか。集中モードになっていないか。アプリの設定タブの「予約中の通知」が 0 なら、課題が登録されていない |
| ウィジェットが空のまま | アプリを一度開く。App Group の名前がアプリとウィジェットで同じか確認 |
| `KadaiNotify.xcodeproj` が開けない | 予備として `project.yml` があります。`brew install xcodegen` のあと、このフォルダで `xcodegen generate` を実行すると作り直せます |

---

## 開発メモ

- Team を選ぶと `project.pbxproj` に `DEVELOPMENT_TEAM = ...`(自分のチーム ID)が書き込まれます。GitHub に公開するときは、この行の変更をコミットに含めないでください。
- ライセンス: MIT
