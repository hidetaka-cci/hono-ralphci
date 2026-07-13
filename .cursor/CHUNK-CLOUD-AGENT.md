# Cursor Cloud Agent × Chunk Sidecar セットアップ

Claude Code 向けに `chunk init` 済みのリポジトリを、Cursor Cloud Agent でも同様に sidecar 検証できるようにする手順です。

## 背景（なぜそのままでは動かないか）

| Claude Code | Cursor Cloud Agent |
|-------------|-------------------|
| `.claude/settings.json` の hooks | **`.cursor/hooks.json` のみ**が読まれる |
| `Stop` → `chunk validate` | 素の `chunk validate` は **stdin JSON 待ちでハング**しうる |
| ローカルに CLI / SSH 鍵がある想定 | VM には **CLI も `~/.ssh/chunk_ai` も無い** |

プロダクトバグというより、**hook の前提と Cloud Agent VM の前提のずれ**です。

## 前提

- CircleCI の Chunk / sidecar が使える org
- Cloud Agent の Secret に `CIRCLECI_TOKEN`（または `CIRCLE_TOKEN`）が入っている
- リポジトリに `.chunk/config.json`（`orgID` と `validation.sidecarImage`）がある

このリポジトリでは上記は揃っています。

## リポジトリに入れるもの（この PR の内容）

```text
.cursor/
  environment.json              # install で setup を実行
  setup-chunk.sh                # Chunk CLI + SSH 鍵
  hooks.json                    # Cursor hooks
  hooks/
    chunk-validate-stop.sh      # stop ラッパー（stdin drain + validate --remote）
```

### hooks の役割

1. **`beforeShellExecution`（`git commit`）**  
   Cloud Agent VM 上で `npm ci && npm test`（速いローカルゲート）
2. **`stop`（ラッパー）**  
   sidecar 上で `chunk validate --remote`（本番 CI に近い検証）

## 新規 Cloud Agent セッションでの流れ

### 1. ブランチを取り込む

`main` にマージ済みならそのままで OK。未マージなら当該 PR ブランチを使う。

### 2. Cloud Agent 環境

`.cursor/environment.json` がある場合、install で次が走ります。

```bash
npm ci && .cursor/setup-chunk.sh
```

`environment.json` が効いていない（ダッシュボード側の環境だけ使う等）場合は、セッション冒頭で手動実行:

```bash
bash .cursor/setup-chunk.sh
```

確認:

```bash
chunk --version
test -f ~/.ssh/chunk_ai && echo "ssh key ok"
chunk config show   # circleCIToken / orgID が解決されること
```

### 3. Secret

Cloud Agents ダッシュボードの Secrets に:

- `CIRCLECI_TOKEN` … CircleCI Personal API Token

`chunk config show` で `Environment variable (CIRCLECI_TOKEN)` と出れば OK。

### 4. 動作確認（推奨・1回）

Cursor stop hook を模してラッパーを実行:

```bash
echo '{"hook_event_name":"stop"}' | .cursor/hooks/chunk-validate-stop.sh
```

成功時の目安:

- active sidecar が無ければ snapshot から作成
- `add-ssh-key` → sync → remote `npm ci` / `npm test`
- exit code `0`

失敗時は exit `2`（エージェントに修正を続けさせる想定）。

## エージェント作業中の推奨フロー

stop hook に任せてもよいが、明示実行するなら:

```bash
chunk sidecar sync
chunk validate --remote
# または
chunk sidecar ssh -- npm test
```

**使わない方がよいもの**

| 避け方 | 理由 |
|--------|------|
| 素の `chunk validate`（stdin 未処理） | Cursor hook / TTY でハングしうる |
| `chunk sidecar exec --command "..."`（長時間） | 同期 HTTP で短いタイムアウトになりやすい |
| `.claude/settings.json` だけに依存 | Cloud Agent は読まない |

## トラブルシュート

| 症状 | 確認 |
|------|------|
| `chunk: command not found` | `.cursor/setup-chunk.sh` を実行。`environment.json` の install が走っているか |
| `SSH key not found: ~/.ssh/chunk_ai` | setup 再実行、またはラッパー実行（鍵を自動生成する） |
| `circleCIToken: (not set)` | Secret `CIRCLECI_TOKEN` を追加してセッション再起動 |
| `chunk validate` が無出力で止まる | stdin を渡せているか。必ずラッパーか `cat >/dev/null` 経由で `--remote` |
| sync / validate が path で落ちる | active sidecar を `chunk sidecar current` で確認。必要なら snapshot から作り直す |
| `sidecar exec` が timeout | `chunk sidecar ssh -- <cmd>` を使う |

## ファイル対応表（Claude → Cursor）

| Claude Code | Cursor Cloud Agent |
|-------------|-------------------|
| `.claude/settings.json` → `Stop` → `chunk validate` | `.cursor/hooks/chunk-validate-stop.sh` → `chunk validate --remote` |
| `.claude/settings.json` → `PreToolUse` / git commit | `.cursor/hooks.json` → `beforeShellExecution` / `git commit` |
| ローカル Homebrew 等の CLI | `.cursor/setup-chunk.sh`（Releases から Linux binary） |

## 参考

- [Cursor Hooks](https://cursor.com/docs/hooks.md)（Cloud agent support）
- [Cursor Cloud Environment Setup](https://cursor.com/docs/cloud-agent/setup)
- [Chunk CLI](https://circleci.com/docs/guides/toolkit/install-and-configure-the-chunk-cli/)
- CircleCI: [Wire Chunk sidecars into agent hooks](https://circleci.com/blog/chunk-sidecar-agent-hooks/)
