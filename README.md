# Loom

A tmux plugin of agent dashboard.

tmux 上の AI コーディングエージェント(Claude Code など)の pane を検知し、状態(working / idle / blocked)付きの一覧 popup を提供する。設計資料は [docs/](docs/) を参照。

## インストール(TPM)

```tmux
set -g @plugin '<you>/Loom'
```

または手動で:

```sh
git clone https://github.com/<you>/Loom ~/.tmux/plugins/Loom
# .tmux.conf に追記:
run-shell ~/.tmux/plugins/Loom/loom.tmux
```

要件: tmux 3.2+(`display-popup`)。

## 使い方

- `prefix + a` で popup ダッシュボードを開く(キーは `@loom_key` で変更可)
- popup 内キー: `j`/`k`/`C-n`/`C-p`/`↑`/`↓` 移動、`Enter` で対象 pane へジャンプ、`r` 再スキャン、`q`/`Esc`/`C-c` 閉じる
- 検知は二段構え:
  - 主経路: Claude Code Hooks によるイベント駆動報告(下記 integration、正確・負荷ゼロ)
  - 従経路: 画面検知(`manifests/*.toml` のルールで判定)。popup を開いた瞬間と、エージェント pane が `@loom_silence_timeout` 秒無出力になったタイミング(`monitor-silence`)に走る
- `blocked` / `idle` への遷移は通知される(`@loom_notify_on` で変更可)

## Claude Code 連携(推奨)

```sh
bin/loom integration install claude    # ~/.claude/settings.json へフックをマージ
bin/loom integration uninstall claude  # 除去(loom 由来のエントリのみ)
```

既存フックは保持され、再実行しても重複しない。変更前に `settings.json.loom-bak` へバックアップされる。反映には Claude Code の再起動が必要。

## CLI

`bin/loom` でエージェント pane を外から操作できる。`<target>` は pane ID(`%3`)・tmux ターゲット(`sess:1.2`)・エージェント名(`claude`)のいずれか。

```sh
bin/loom list --json                          # 全エージェントと状態(スクリプト連携用)
bin/loom send %3 "テストを直して"               # 入力を送る(既定で末尾に Enter)
bin/loom wait %3 --status idle --timeout 600  # 指定状態になるまで待つ
bin/loom read %3 --lines 50                   # 出力を読む(scrollback 含む末尾 N 行)
bin/loom start claude --cwd ~/dev/api         # 新 window でエージェント起動
bin/loom worktree feat/x                      # git worktree + 新 window
```

`send` → `wait` → `read` を組み合わせると、複数エージェントへの指示出し・完了待ち・結果回収をスクリプト化できる。

## 設定

```tmux
set -g @loom_key "a"              # popup 起動キー(prefix + <key>)
set -g @loom_popup_width "80%"
set -g @loom_popup_height "70%"
set -g @loom_screen_detection "on"
set -g @loom_silence_timeout "4"  # monitor-silence の秒数(0 で無効)
set -g @loom_notify "on"          # 状態遷移通知
set -g @loom_notify_on "blocked,idle"
set -g @loom_notify_backend "auto"  # display-message | osc9 | terminal-notifier | auto
set -g @loom_manifest_dir ""      # 追加/上書きマニフェストのディレクトリ
```

## 実装状況

- [x] M1: 画面検知(claude マニフェスト)+ popup 一覧 + Enter ジャンプ
- [x] M2: Claude Code Hooks 連携・遷移通知・`monitor-silence` フォールバック
- [x] M3: CLI(`send`/`read`/`wait`/`worktree`/`start`、`list --json`)
- [ ] M4: codex/copilot マニフェスト・TPM 登録
