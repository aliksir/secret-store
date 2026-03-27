#!/bin/bash
# secret-resolve.sh — .envのSECRET:参照を展開してコマンドを実行
#
# 使い方:
#   secret-resolve.sh <.env> <command> [args...]
#
# 例:
#   secret-resolve.sh .env python app.py
#   secret-resolve.sh .env npm start
#
# .env内の SECRET:project/KEY を vault から解決し、
# 環境変数にセットした上で exec でコマンドを置き換える。
# 実値はファイルに一切書かない。
#
# 依存: bash, gpg (GnuPG), jq

set -euo pipefail

SECRETS_DIR="${SECRET_STORE_DIR:-${HOME}/.secrets}"
VAULT_ENC="${SECRETS_DIR}/vault.json.gpg"

# === 依存チェック ===

for cmd in gpg jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "エラー: ${cmd} がインストールされていません。"
    exit 1
  fi
done

# === 引数チェック ===

if [[ $# -lt 2 ]]; then
  echo "使い方: secret-resolve.sh <.env> <command> [args...]"
  echo "例:     secret-resolve.sh .env python app.py"
  exit 1
fi

ENVFILE="$1"
shift

if [[ ! -f "$ENVFILE" ]]; then
  echo "エラー: .env ファイルが見つかりません: ${ENVFILE}"
  exit 1
fi

# === vault 復号（SECRET:参照がある場合のみ） ===

has_secrets=false
if grep -q "^[A-Za-z_][A-Za-z0-9_]*=SECRET:" "$ENVFILE" 2>/dev/null; then
  has_secrets=true
fi

vault_json="{}"
if [[ "$has_secrets" == true ]]; then
  if [[ ! -f "$VAULT_ENC" ]]; then
    echo "エラー: vault が見つかりません: ${VAULT_ENC}"
    echo "secret-manage.sh init で初期化してください。"
    exit 1
  fi

  vault_json=$(gpg --quiet --batch --yes --decrypt "$VAULT_ENC" 2>/dev/null || \
               gpg --quiet --decrypt "$VAULT_ENC")
fi

# === .env を読んで環境変数をセット ===

missing_keys=()

while IFS= read -r line; do
  # CR除去（Windows CRLF対応）
  line="${line%$'\r'}"
  # コメント・空行をスキップ
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$line" ]] && continue

  # KEY=VALUE形式をパース
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"

    # 予約環境変数の上書き防止
    if [[ "$key" =~ ^(PATH|HOME|USER|SHELL|LANG|TERM|TMPDIR|LOGNAME|IFS|PS1|PS2|OLDPWD|PWD|SHLVL|_)$ ]]; then
      echo "警告: 予約環境変数 '${key}' への上書きをスキップしました" >&2
      continue
    fi

    # SECRET: 参照の解決
    if [[ "$val" == SECRET:* ]]; then
      secret_key="${val#SECRET:}"
      resolved=$(printf '%s' "$vault_json" | jq -r --arg k "$secret_key" '.[$k] // empty')

      if [[ -z "$resolved" ]]; then
        missing_keys+=("$secret_key")
        continue
      fi

      export "${key}=${resolved}"
    else
      export "${key}=${val}"
    fi
  fi
done < "$ENVFILE"

# === 未解決キーのエラー ===

if [[ ${#missing_keys[@]} -gt 0 ]]; then
  echo "エラー: vault に以下のキーが見つかりません:"
  for mk in "${missing_keys[@]}"; do
    echo "  - ${mk}"
  done
  echo ""
  echo "secret-manage.sh set <key> で登録してください。"
  exit 1
fi

# === コマンド実行（exec で置き換え） ===

exec "$@"
