# secret-store

> **[English README](README.md)**

`.env` ファイルのシークレットをローカルで安全に管理するツール。実際の値を参照（`SECRET:project/KEY`）に置き換え、本物の値はGPG暗号化vaultに保存します。

`.env` が流出しても、参照文字列しか漏れません。

## 仕組み

```
.env（参照のみ）               ~/.secrets/vault.json.gpg（暗号化）
┌──────────────────────┐       ┌─────────────────────────────┐
│ API_KEY=SECRET:myapp/ │──────▶│ {"myapp/API_KEY": "sk-xxx"} │
│ API_KEY              │       └─────────────────────────────┘
│ PORT=3000            │                    │
└──────────────────────┘           secret-resolve.sh
                                           │
                                    環境変数（メモリのみ）
                                           │
                                      exec アプリ起動
```

## 必要なもの

- **bash**（WindowsではGit Bash、macOS/Linuxはそのまま）
- **gpg**（GnuPG）— 暗号化
- **jq** — JSON処理

## クイックスタート

```bash
# 1. クローン
git clone https://github.com/aliksir/secret-store.git
cd secret-store

# 2. vault初期化（GPGパスフレーズを設定）
./secret-manage.sh init

# 3. .envを移行（1コマンドで全部やる）
./secret-manage.sh migrate /path/to/your/app/.env

# 4. アプリ起動
cd /path/to/your/app
./start-with-secrets.sh python app.py
```

これだけです。`.env` には参照だけが残り、実値は暗号化vaultに入ります。

## コマンド一覧

| コマンド | 説明 |
|---------|------|
| `init` | vault初期化 + パターン設定ファイル作成 |
| `migrate <.env>` | **ワンコマンド移行**: バックアップ → シークレット検出 → vault登録 → .env書き換え → 起動ラッパー生成 |
| `set <project/KEY>` | シークレットを手動登録 |
| `get <project/KEY>` | シークレットの値を取得 |
| `list` | キー名一覧（値は非表示） |
| `delete <project/KEY>` | シークレットを削除 |
| `export-template <.env>` | 移行プレビュー（実際には書き換えない） |
| `backup <.env>` | .envを暗号化バックアップ |
| `restore <project>` | バックアップから.envを復元 |

## `migrate` が行うこと

```
secret-manage.sh migrate .env
  ├─ ⚠️  起動中サービスの停止を確認
  ├─ Step 1: 現在の.envを暗号化バックアップ
  ├─ Step 2: シークレットキーを自動検出 → vaultに登録
  ├─ Step 3: .envをSECRET:参照に書き換え
  └─ Step 4: start-with-secrets.sh/.ps1 起動ラッパーを生成
```

**アプリのコード変更は不要です。** ラッパーが参照を解決してからアプリを起動します。

## シークレットの検出パターン

以下のパターンにマッチするキーがシークレットとして扱われます:

```
KEY, SECRET, TOKEN, PASSWORD, CREDENTIAL, API_KEY, BEARER
```

`~/.secrets/.secretsrc` を編集してカスタマイズできます:

```
# 1行1パターン
KEY
SECRET
TOKEN
MY_CUSTOM_PATTERN
```

## Windows（PowerShell）での使用

migrateで生成される `.ps1` ラッパーを使います:

```powershell
cd C:\path\to\your\app
.\start-with-secrets.ps1 python app.py
```

Git Bashの場所は自動検出されます。手動設定は不要です。

## ロールバック（元に戻す）

```bash
# 暗号化バックアップから.envを復元
./secret-manage.sh restore myapp
```

バックアップは `~/.secrets/backups/` に暗号化保存されています。

## 注意事項

- **移行前に起動中のサービスを停止してください。** アプリがサービス（systemd, nssm等）として動いている場合、先に停止が必要です。移行後は `start-with-secrets.sh` 経由で起動するようサービス設定を変更してください。
- GPGパスフレーズはあなたの記憶の中だけに存在します。ファイルには保存されません。
- vault の場所は `SECRET_STORE_DIR` 環境変数で変更できます。
- このツールは `.env` ファイルのみを管理します。`settings.json` 等の他の設定ファイルは対象外です。

## 免責事項

**本ツールは自己責任でご利用ください。**

- クラウドプロバイダーやセキュリティ企業の公式ツールではありません
- GPG暗号化の強度はパスフレーズの品質に依存します
- 本番環境のシークレットを移行する前に、バックアップからの復元が正しく動作することを必ず確認してください
- 本ツールの使用によるいかなる損害についても、作者は責任を負いません

## 着想

[1Password CLI](https://developer.1password.com/docs/cli/) — シークレットの実値を参照（`op://vault/item/field`）に置き換えるコンセプト

## ライセンス

MIT
