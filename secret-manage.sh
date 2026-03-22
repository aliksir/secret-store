#!/bin/bash
# secret-manage.sh — ローカルシークレットvault管理ツール
#
# .envファイルのシークレット（APIキー等）を暗号化vaultに移行し、
# .envには参照（SECRET:project/KEY）だけを残す。
# .envが流出しても実値が漏れない構造を実現する。
#
# 使い方:
#   secret-manage.sh init                        vault初期化
#   secret-manage.sh migrate <.env>              .envのシークレットをvaultに移行（一発）
#   secret-manage.sh set <project/KEY_NAME>      値を対話入力で登録
#   secret-manage.sh get <project/KEY_NAME>      値を取得
#   secret-manage.sh list                        キー名一覧（値は非表示）
#   secret-manage.sh delete <project/KEY_NAME>   キーを削除
#   secret-manage.sh export-template <.env>      .envのシークレットをSECRET:参照に変換（プレビュー）
#   secret-manage.sh backup <.env>               .envを暗号化バックアップ
#   secret-manage.sh restore <project>           バックアップから.envを復元
#   secret-manage.sh verify                      vault整合性チェック
#   secret-manage.sh rotate                      GPGパスフレーズ変更
#
# 依存: bash, gpg (GnuPG), jq

set -euo pipefail

SECRETS_DIR="${SECRET_STORE_DIR:-${HOME}/.secrets}"
VAULT_ENC="${SECRETS_DIR}/vault.json.gpg"

# シークレット検出パターン（カスタマイズ可）
DEFAULT_SECRET_PATTERNS="KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL|API_KEY|BEARER"
SECRETSRC="${SECRETS_DIR}/.secretsrc"

# === 依存チェック ===

check_deps() {
  if ! command -v gpg &>/dev/null; then
    echo "エラー: gpg (GnuPG) がインストールされていません。"
    echo ""
    echo "インストール方法:"
    echo "  Windows (Git Bash): Git for Windows に同梱されています"
    echo "  Windows (Scoop):    scoop install gnupg"
    echo "  macOS:              brew install gnupg"
    echo "  Ubuntu/Debian:      sudo apt install gnupg"
    echo "  Fedora/RHEL:        sudo dnf install gnupg2"
    exit 1
  fi

  if ! command -v jq &>/dev/null; then
    echo "エラー: jq がインストールされていません。"
    echo ""
    echo "インストール方法:"
    echo "  Windows (Scoop):    scoop install jq"
    echo "  macOS:              brew install jq"
    echo "  Ubuntu/Debian:      sudo apt install jq"
    exit 1
  fi
}

# === ヘルパー ===

get_secret_patterns() {
  if [[ -f "$SECRETSRC" ]]; then
    # .secretsrc から読み込み（1行1パターン、| で結合）
    grep -v '^#' "$SECRETSRC" | grep -v '^$' | tr '\n' '|' | sed 's/|$//'
  else
    echo "$DEFAULT_SECRET_PATTERNS"
  fi
}

ensure_dir() {
  if [[ ! -d "$SECRETS_DIR" ]]; then
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
    echo "作成: ${SECRETS_DIR}/"
  fi
}

decrypt_vault() {
  if [[ ! -f "$VAULT_ENC" ]]; then
    echo "{}"
    return
  fi
  gpg --quiet --batch --yes --decrypt "$VAULT_ENC" 2>/dev/null || {
    gpg --quiet --decrypt "$VAULT_ENC"
  }
}

encrypt_vault() {
  local json
  json=$(cat)
  echo "$json" | gpg --quiet --batch --yes --symmetric --cipher-algo AES256 --output "$VAULT_ENC" 2>/dev/null || {
    echo "$json" | gpg --quiet --symmetric --cipher-algo AES256 --output "$VAULT_ENC"
  }
}

cleanup() {
  # tmpファイルと平文変数のクリーンアップ
  if [[ -f "${SECRETS_DIR}/.vault.tmp.json" ]]; then
    rm -f "${SECRETS_DIR}/.vault.tmp.json"
  fi
  # migrate中断時の残存ファイル除去
  for f in "${SECRETS_DIR}"/.migrating.*; do
    [[ -e "$f" ]] && rm -f "$f" || true
  done
}
trap cleanup EXIT

# === コマンド ===

cmd_init() {
  check_deps
  ensure_dir
  if [[ -f "$VAULT_ENC" ]]; then
    echo "vault は既に存在します: ${VAULT_ENC}"
    echo "リセットする場合は手動で削除してください。"
    exit 1
  fi
  echo "{}" | encrypt_vault
  echo "vault を初期化しました: ${VAULT_ENC}"

  # .secretsrc のサンプル作成
  if [[ ! -f "$SECRETSRC" ]]; then
    cat > "$SECRETSRC" << 'RCEOF'
# シークレット検出パターン（1行1パターン、正規表現）
# .envのキー名がこれらにマッチすると SECRET: 参照に変換されます
KEY
SECRET
TOKEN
PASSWORD
CREDENTIAL
API_KEY
BEARER
RCEOF
    echo "パターン設定を作成しました: ${SECRETSRC}"
    echo "必要に応じて編集してください。"
  fi
}

cmd_set() {
  local key="${1:?使い方: secret-manage.sh set <project/KEY_NAME>}"
  check_deps
  ensure_dir

  echo -n "値を入力 (${key}): "
  read -rs value
  echo ""

  if [[ -z "$value" ]]; then
    echo "エラー: 空の値は登録できません"
    exit 1
  fi

  local vault
  vault=$(decrypt_vault)
  echo "$vault" | jq --arg k "$key" --arg v "$value" '.[$k] = $v' | encrypt_vault
  echo "登録完了: ${key}"
}

cmd_get() {
  local key="${1:?使い方: secret-manage.sh get <project/KEY_NAME>}"
  check_deps

  local vault
  vault=$(decrypt_vault)
  local value
  value=$(echo "$vault" | jq -r --arg k "$key" '.[$k] // empty')

  if [[ -z "$value" ]]; then
    echo "エラー: キー '${key}' が見つかりません" >&2
    exit 1
  fi
  echo "$value"
}

cmd_list() {
  check_deps
  local vault
  vault=$(decrypt_vault)
  local count
  count=$(echo "$vault" | jq 'length')

  if [[ "$count" == "0" ]]; then
    echo "vault は空です。secret-manage.sh set <key> で登録してください。"
    return
  fi

  echo "=== Secret Vault (${count} keys) ==="
  echo "$vault" | jq -r 'keys[]' | while read -r key; do
    echo "  ${key}"
  done
}

cmd_delete() {
  local key="${1:?使い方: secret-manage.sh delete <project/KEY_NAME>}"
  check_deps

  local vault
  vault=$(decrypt_vault)
  local exists
  exists=$(echo "$vault" | jq --arg k "$key" 'has($k)')
  if [[ "$exists" != "true" ]]; then
    echo "エラー: キー '${key}' が見つかりません"
    exit 1
  fi

  echo "$vault" | jq --arg k "$key" 'del(.[$k])' | encrypt_vault
  echo "削除完了: ${key}"
}

cmd_export_template() {
  local envfile="${1:?使い方: secret-manage.sh export-template <.env>}"

  if [[ ! -f "$envfile" ]]; then
    echo "エラー: ファイルが見つかりません: ${envfile}"
    exit 1
  fi

  local dir
  dir=$(cd "$(dirname "$envfile")" && basename "$(pwd)")
  local secret_patterns
  secret_patterns=$(get_secret_patterns)

  echo "# プロジェクト: ${dir}"
  echo "# SECRET: 参照に変換されるキー（プレビュー）"
  echo ""

  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
      echo "$line"
      continue
    fi
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      if [[ "$key" =~ ($secret_patterns) ]] && [[ -n "$val" ]] && [[ "$val" != SECRET:* ]]; then
        echo "${key}=SECRET:${dir}/${key}"
      else
        echo "$line"
      fi
    else
      echo "$line"
    fi
  done < "$envfile"
}

cmd_backup() {
  local envfile="${1:?使い方: secret-manage.sh backup <.env>}"
  check_deps
  ensure_dir

  if [[ ! -f "$envfile" ]]; then
    echo "エラー: ファイルが見つかりません: ${envfile}"
    exit 1
  fi

  local dir
  dir=$(cd "$(dirname "$envfile")" && basename "$(pwd)")
  local backup_dir="${SECRETS_DIR}/backups"
  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="${backup_dir}/${dir}_${timestamp}.env.gpg"

  mkdir -p "$backup_dir"
  gpg --quiet --batch --yes --symmetric --cipher-algo AES256 --output "$backup_file" "$envfile" 2>/dev/null || {
    gpg --quiet --symmetric --cipher-algo AES256 --output "$backup_file" "$envfile"
  }

  echo "バックアップ完了: ${backup_file}"
  echo "復元: secret-manage.sh restore ${dir}"
  echo ""
  echo "=== ${dir} のバックアップ一覧 ==="
  find "$backup_dir" -maxdepth 1 -name "${dir}_*.env.gpg" -print0 2>/dev/null \
    | sort -rz | while IFS= read -r -d '' f; do
    echo "  $(basename "$f")"
  done
}

cmd_restore() {
  local project="${1:?使い方: secret-manage.sh restore <project>}"
  check_deps
  local backup_dir="${SECRETS_DIR}/backups"

  local latest
  latest=$(find "$backup_dir" -maxdepth 1 -name "${project}_*.env.gpg" -print0 2>/dev/null \
    | sort -rz | head -z -n1 | tr -d '\0')

  if [[ -z "$latest" ]]; then
    echo "エラー: ${project} のバックアップが見つかりません"
    exit 1
  fi

  echo "=== ${project} のバックアップ一覧 ==="
  local i=1
  local files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
    echo "  [${i}] $(basename "$f")"
    i=$((i + 1))
  done < <(find "$backup_dir" -maxdepth 1 -name "${project}_*.env.gpg" -print0 2>/dev/null | sort -rz)

  echo ""
  echo -n "復元するバックアップ番号（最新=1）: "
  read -r choice
  [[ -z "$choice" ]] && choice=1

  local idx=$((choice - 1))
  if [[ $idx -lt 0 ]] || [[ $idx -ge ${#files[@]} ]]; then
    echo "エラー: 無効な番号です"
    exit 1
  fi

  local selected="${files[$idx]}"
  echo ""
  echo "復元元: $(basename "$selected")"
  echo -n "復元先の.envパスを入力: "
  read -r dest

  if [[ -z "$dest" ]]; then
    echo "エラー: 復元先が指定されていません"
    exit 1
  fi

  if [[ -f "$dest" ]]; then
    cp "$dest" "${dest}.before-restore"
    echo "既存.envを退避: ${dest}.before-restore"
  fi

  gpg --quiet --batch --yes --decrypt "$selected" > "$dest" 2>/dev/null || {
    gpg --quiet --decrypt "$selected" > "$dest"
  }
  echo "復元完了: ${dest}"
}

cmd_migrate() {
  local envfile="${1:?使い方: secret-manage.sh migrate <.env>}"
  check_deps
  ensure_dir

  if [[ ! -f "$envfile" ]]; then
    echo "エラー: ファイルが見つかりません: ${envfile}"
    exit 1
  fi

  local dir
  dir=$(cd "$(dirname "$envfile")" && basename "$(pwd)")

  local secret_patterns
  secret_patterns=$(get_secret_patterns)

  echo "⚠️  注意: この.envを使用しているサービスやプロセスが起動中の場合、"
  echo "   先に停止してください。移行後は start-with-secrets.sh 経由で起動する必要があります。"
  echo ""
  echo -n "続行しますか？ (y/N): "
  read -r confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "中止しました。"
    exit 0
  fi
  echo ""

  # Step 1: バックアップ
  echo "=== Step 1: バックアップ ==="
  cmd_backup "$envfile"
  echo ""

  # Step 2: シークレット検出 → vault登録
  echo "=== Step 2: シークレットをvaultに登録 ==="
  local vault
  vault=$(decrypt_vault)
  local count=0

  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      val="${val%$'\r'}"

      [[ "$val" == SECRET:* ]] && continue

      if [[ "$key" =~ ($secret_patterns) ]] && [[ -n "$val" ]]; then
        local vault_key="${dir}/${key}"
        vault=$(echo "$vault" | jq --arg k "$vault_key" --arg v "$val" '.[$k] = $v')
        echo "  登録: ${vault_key}"
        count=$((count + 1))
      fi
    fi
  done < "$envfile"

  if [[ "$count" -eq 0 ]]; then
    echo "  新規シークレットなし（既にSECRET:参照済み or シークレットキーなし）"
    echo ""
  fi

  if [[ "$count" -gt 0 ]]; then
    echo "$vault" | encrypt_vault
    echo ""
    echo "${count} 個のシークレットをvaultに登録しました。"
    echo ""
  fi

  # Step 3: .envを書き換え
  if [[ "$count" -gt 0 ]]; then
  echo "=== Step 3: .envをSECRET:参照に書き換え ==="
  local tmpfile="${envfile}.migrating"
  # 前回中断時の残存ファイルを除去してから書き込み
  rm -f "$tmpfile"

  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      val="${val%$'\r'}"

      [[ "$val" == SECRET:* ]] && { echo "$line" >> "$tmpfile"; continue; }

      if [[ "$key" =~ ($secret_patterns) ]] && [[ -n "$val" ]]; then
        echo "${key}=SECRET:${dir}/${key}" >> "$tmpfile"
      else
        echo "$line" >> "$tmpfile"
      fi
    else
      echo "$line" >> "$tmpfile"
    fi
  done < "$envfile"

  mv "$tmpfile" "$envfile"
  echo "  書き換え完了: ${envfile}"
  echo ""
  fi

  # Step 4: 起動ラッパー生成
  echo "=== Step 4: 起動ラッパー生成 ==="
  local envdir
  envdir=$(cd "$(dirname "$envfile")" && pwd)

  # secret-resolve.sh のパスを解決
  local resolve_path
  resolve_path="$(cd "$(dirname "$0")" && pwd)/secret-resolve.sh"
  if [[ ! -f "$resolve_path" ]]; then
    echo "  警告: secret-resolve.sh が見つかりません: ${resolve_path}"
    echo "  起動ラッパーを手動で編集してください。"
    resolve_path="secret-resolve.sh"
  fi

  local wrapper_sh="${envdir}/start-with-secrets.sh"
  cat > "$wrapper_sh" << WRAPPER_EOF
#!/bin/bash
# 起動ラッパー（secret-store自動生成）
# 使い方: ./start-with-secrets.sh <command> [args...]
# 例:     ./start-with-secrets.sh python app.py

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
RESOLVE="${resolve_path}"

if [[ ! -f "\$RESOLVE" ]]; then
  echo "エラー: secret-resolve.sh が見つかりません: \$RESOLVE"
  echo "secret-store のインストール先を確認してください。"
  exit 1
fi

if [[ \$# -eq 0 ]]; then
  echo "使い方: ./start-with-secrets.sh <command> [args...]"
  exit 1
fi

exec "\$RESOLVE" "\${SCRIPT_DIR}/.env" "\$@"
WRAPPER_EOF
  chmod +x "$wrapper_sh"
  echo "  生成: ${wrapper_sh}"

  # Windows PowerShell版
  local wrapper_ps1="${envdir}/start-with-secrets.ps1"
  # Git Bash のパスを自動検出
  cat > "$wrapper_ps1" << 'WRAPPER_PS1_HEAD'
# 起動ラッパー（secret-store自動生成）
# 使い方: .\start-with-secrets.ps1 <command> [args...]

# Git Bash を自動検出
$GitBashPaths = @(
    'C:\Program Files\Git\bin\bash.exe',
    'C:\Program Files (x86)\Git\bin\bash.exe',
    "${env:LOCALAPPDATA}\Programs\Git\bin\bash.exe",
    "${env:ProgramFiles}\Git\bin\bash.exe"
)
$GitBash = $null
foreach ($p in $GitBashPaths) {
    if (Test-Path $p) { $GitBash = $p; break }
}
if (-not $GitBash) {
    Write-Error 'Git Bash が見つかりません。Git for Windows をインストールしてください。'
    exit 1
}

WRAPPER_PS1_HEAD

  # 動的部分を追記
  cat >> "$wrapper_ps1" << WRAPPER_PS1_TAIL
\$ResolveSh = '${resolve_path}'
\$ScriptDir = Split-Path -Parent \$MyInvocation.MyCommand.Path
\$EnvFile = Join-Path \$ScriptDir '.env'

# パスをGit Bash形式に変換
\$BashResolve = \$ResolveSh -replace '\\\\','/' -replace '^C:','/c'
\$BashEnvFile = \$EnvFile -replace '\\\\','/' -replace '^C:','/c'

\$ConvertedArgs = @()
foreach (\$a in \$args) {
    \$ConvertedArgs += (\$a -replace '\\\\','/' -replace '^C:','/c')
}

\$FullCmd = "\$BashResolve \$BashEnvFile \$(\$ConvertedArgs -join ' ')"
& \$GitBash --login -c \$FullCmd
WRAPPER_PS1_TAIL
  echo "  生成: ${wrapper_ps1}"
  echo ""

  # Step 5: 結果表示
  echo "=== 完了 ==="
  echo "  バックアップ: ~/.secrets/backups/${dir}_*.env.gpg"
  [[ "$count" -gt 0 ]] && echo "  vault登録数: ${count} 個"
  echo "  .env: SECRET:参照に書き換え済み"
  echo "  起動ラッパー: start-with-secrets.sh / .ps1"
  echo ""
  echo "アプリ起動:"
  echo "  Bash:       cd ${envdir} && ./start-with-secrets.sh <command>"
  echo "  PowerShell: cd ${envdir} && .\\start-with-secrets.ps1 <command>"
  echo ""
  echo "元に戻す場合:"
  echo "  secret-manage.sh restore ${dir}"
}

cmd_verify() {
  check_deps

  if [[ ! -f "$VAULT_ENC" ]]; then
    echo "エラー: vault が見つかりません: ${VAULT_ENC}"
    echo "secret-manage.sh init で初期化してください。"
    exit 1
  fi

  local vault
  vault=$(decrypt_vault)
  local count
  count=$(echo "$vault" | jq 'length')
  local valid
  valid=$(echo "$vault" | jq 'type == "object"')

  if [[ "$valid" != "true" ]]; then
    echo "❌ vault が壊れています（JSONオブジェクトではありません）"
    exit 1
  fi

  echo "✅ vault 整合性OK"
  echo "  ファイル: ${VAULT_ENC}"
  echo "  キー数: ${count}"
  echo "  形式: JSON object"
}

cmd_rotate() {
  check_deps

  if [[ ! -f "$VAULT_ENC" ]]; then
    echo "エラー: vault が見つかりません: ${VAULT_ENC}"
    echo "secret-manage.sh init で初期化してください。"
    exit 1
  fi

  echo "GPGパスフレーズを変更します。"
  echo "1. 現在のパスフレーズで復号します"
  echo ""

  local vault
  vault=$(decrypt_vault)
  local count
  count=$(echo "$vault" | jq 'length')

  echo "  復号成功（${count} キー）"
  echo ""
  echo "2. 新しいパスフレーズで再暗号化します"
  echo ""

  # 一時的にvault.json.gpgを退避
  local backup="${VAULT_ENC}.before-rotate"
  cp "$VAULT_ENC" "$backup"

  if echo "$vault" | encrypt_vault; then
    echo ""
    echo "✅ パスフレーズを変更しました"
    echo "  退避ファイル: ${backup}"
    echo "  問題があれば退避ファイルから復元できます。"
    echo ""

    # バックアップも再暗号化が必要な旨を通知
    local backup_dir="${SECRETS_DIR}/backups"
    if [[ -d "$backup_dir" ]] && find "$backup_dir" -maxdepth 1 -name "*.env.gpg" -print -quit 2>/dev/null | grep -q .; then
      echo "⚠️  注意: backups/ 内のファイルは旧パスフレーズで暗号化されています。"
      echo "  必要に応じて restore → 再 backup してください。"
    fi
  else
    echo "❌ 再暗号化に失敗しました。退避ファイルから復元します。"
    mv "$backup" "$VAULT_ENC"
    exit 1
  fi
}

# === メイン ===

case "${1:-help}" in
  init)    cmd_init ;;
  set)     cmd_set "${2:-}" ;;
  get)     cmd_get "${2:-}" ;;
  list)    cmd_list ;;
  delete)  cmd_delete "${2:-}" ;;
  export-template) cmd_export_template "${2:-}" ;;
  backup)  cmd_backup "${2:-}" ;;
  restore) cmd_restore "${2:-}" ;;
  migrate) cmd_migrate "${2:-}" ;;
  verify)  cmd_verify ;;
  rotate)  cmd_rotate ;;
  help|--help|-h)
    echo "secret-store — .envシークレット管理ツール"
    echo ""
    echo "使い方:"
    echo "  secret-manage.sh init                       vault初期化"
    echo "  secret-manage.sh migrate <.env>             .envのシークレットをvaultに移行"
    echo "  secret-manage.sh set <project/KEY_NAME>     値を登録"
    echo "  secret-manage.sh get <project/KEY_NAME>     値を取得"
    echo "  secret-manage.sh list                       キー名一覧"
    echo "  secret-manage.sh delete <project/KEY_NAME>  キーを削除"
    echo "  secret-manage.sh export-template <.env>     SECRET:参照プレビュー"
    echo "  secret-manage.sh backup <.env>              .envを暗号化バックアップ"
    echo "  secret-manage.sh restore <project>          バックアップから復元"
    echo "  secret-manage.sh verify                     vault整合性チェック"
    echo "  secret-manage.sh rotate                     GPGパスフレーズ変更"
    ;;
  *)
    echo "エラー: 不明なコマンド '${1}'"
    echo "secret-manage.sh help でヘルプを表示"
    exit 1
    ;;
esac
