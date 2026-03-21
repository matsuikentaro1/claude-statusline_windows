# Claude Code statusline for Windows

Windows 環境で動作する Claude Code 用カスタム statusline です。
コンテキストウィンドウの使用率と API レート制限をリアルタイムで確認できます。

> **Note:** statusline は Claude Code CLI 専用の機能です。VSCode 拡張機能のチャットパネルには表示されません。VSCode 内で使う場合は統合ターミナル (`Ctrl+``) から `claude` コマンドで CLI を起動してください。

## 変更履歴

### v2 (2026-03-21)

Claude Code v2.1.80 で stdin の JSON に `rate_limits` フィールドが追加されました。
これに伴い、本スクリプトを大幅に簡素化しました:

- **Python に移行**: PowerShell ベースから Python ベースに変更。起動が高速に
- **OAuth API 廃止**: rate limit 情報を Claude Code 本体が提供する `rate_limits` フィールドから取得するように変更。資格情報の読み取り・キャッシュ機構が不要に (約200行削減)
- **bash ラッパー不要**: `statusline.sh` を介さず Python を直接呼び出す構成に

> 公式の `/statusline` コマンドは statusline スクリプトを自動生成するヘルパーです。本リポジトリは Windows 環境に特化したカスタム statusline を提供します。

## 表示内容

![sample](sample.png)

| 行 | 内容 |
|---|---|
| 1行目 | モデル名、リポジトリ名、ブランチ (未コミット変更は `*`) |
| context | コンテキストウィンドウ使用率 (`█░` ブロックメーター) |
| current | 5時間枠の API 使用率 (`●○` ドットメーター) + リセット時刻 |
| weekly | 7日枠の API 使用率 (`●○` ドットメーター) + リセット時刻 |

### context の色分け

コンテキスト使用率に応じてメーターとパーセント表示の色が変わります。
compact エラーを防ぐため、早めの `/compact` 実行や新規セッション開始の判断に使えます。

| 使用率 | 色 | 意味 |
|---|---|---|
| 0-59% | 緑 | 余裕あり |
| 60-79% | 黄色 | そろそろ `/compact` を検討 |
| 80-89% | オレンジ | `/compact` 推奨 |
| 90%+ | 赤 | 自動 compact が迫っている。すぐ対処 |

## 前提条件

- Windows 10/11
- Python 3.x
- Claude Code CLI v2.1.80 以降

## インストール

1. このリポジトリを任意の場所にクローンします。

   ```bash
   git clone https://github.com/matsuikentaro1/claude-statusline_windows.git
   ```

2. Claude Code に statusline を設定します。Claude Code のセッション内で以下のように依頼してください。

   ```
   claude-statusline_windows リポジトリの statusline.py を
   グローバル設定 (~/.claude/settings.json) の statusLine に登録してください。
   パスは私の環境に合わせて絶対パスで設定してください。
   ```

   手動で設定する場合は `~/.claude/settings.json` に以下を追加します。
   パスは自分の環境に合わせて書き換えてください。

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "python \"/path/to/claude-statusline_windows/statusline.py\""
     }
   }
   ```

3. Claude Code を再起動するか、新しいセッションを開始します。

## ファイル構成

| ファイル | 説明 |
|---|---|
| `statusline.py` | statusline 本体 (Python)。stdin JSON からコンテキスト・Git 情報・rate limit を取得して表示 |
| `statusline.ps1` | (レガシー) PowerShell 版 statusline。v1 互換用 |
| `statusline.sh` | (レガシー) Git Bash ラッパー。v1 で `statusline.ps1` を呼び出すために使用 |
| `settings.user.snippet.json` | settings.json に追加する設定のサンプル |

## 仕組み

1. Claude Code が `statusline.py` を実行
2. `statusline.py` が stdin から Claude Code の JSON データ (モデル情報・コンテキスト使用率・rate limit など) を受け取る
3. Git コマンドでリポジトリ情報を取得
4. 整形して stdout に出力 → Claude Code がターミナル下部に表示

## 環境変数

| 変数 | 説明 | 既定値 |
|---|---|---|
| `CC_STATUSLINE_NO_COLOR=1` | ANSI カラーを無効化 | off |
| `CC_STATUSLINE_ASCII=1` | メーターを `#` `.` の ASCII 文字に切り替え | off |
| `CC_STATUSLINE_SINGLE_LINE=1` | 全情報を 1 行にまとめて表示 | off |
| `CC_STATUSLINE_DEBUG=1` | エラー発生時にスタックトレースを表示 | off |

## 補足

- `rate_limits` は Claude.ai サブスクライバー (Pro/Max) のみで、最初の API レスポンス後に表示されます。起動直後は `--` と表示されます。
