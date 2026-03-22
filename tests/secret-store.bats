#!/usr/bin/env bats
# secret-store E2E テスト
# 依存: bats-core, gpg, jq

setup() {
  export TEST_DIR="$(mktemp -d)"
  export SECRET_STORE_DIR="${TEST_DIR}/.secrets"
  export MANAGE="$BATS_TEST_DIRNAME/../secret-manage.sh"
  export RESOLVE="$BATS_TEST_DIRNAME/../secret-resolve.sh"
  export TEST_PASSPHRASE="testpass123"
  mkdir -p "$SECRET_STORE_DIR"

  # テスト用gpgラッパー: パスフレーズを自動入力
  export REAL_GPG="$(command -v gpg)"
  local wrapper_dir="${TEST_DIR}/bin"
  mkdir -p "$wrapper_dir"
  cat > "${wrapper_dir}/gpg" << 'WRAPPER'
#!/bin/bash
# テスト用GPGラッパー: --passphrase と --pinentry-mode loopback を自動付与
REAL_GPG_PATH="@@REAL_GPG@@"
PASS="@@PASSPHRASE@@"
exec "$REAL_GPG_PATH" --batch --yes --passphrase "$PASS" --pinentry-mode loopback "$@"
WRAPPER
  sed -i "s|@@REAL_GPG@@|${REAL_GPG}|g" "${wrapper_dir}/gpg"
  sed -i "s|@@PASSPHRASE@@|${TEST_PASSPHRASE}|g" "${wrapper_dir}/gpg"
  chmod +x "${wrapper_dir}/gpg"
  export PATH="${wrapper_dir}:${PATH}"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# === init ===

@test "init: vault を初期化できる" {
  run bash "$MANAGE" init
  [ "$status" -eq 0 ]
  [ -f "${SECRET_STORE_DIR}/vault.json.gpg" ]
  [[ "$output" == *"初期化しました"* ]]
}

@test "init: 既存vault があるとエラー" {
  bash "$MANAGE" init
  run bash "$MANAGE" init
  [ "$status" -eq 1 ]
  [[ "$output" == *"既に存在します"* ]]
}

# === set / get ===

@test "set/get: 値を登録して取得できる" {
  bash "$MANAGE" init
  echo "my-secret-value" | bash "$MANAGE" set "testproj/API_KEY"
  run bash "$MANAGE" get "testproj/API_KEY"
  [ "$status" -eq 0 ]
  [ "$output" = "my-secret-value" ]
}

@test "get: 存在しないキーはエラー" {
  bash "$MANAGE" init
  run bash "$MANAGE" get "nonexistent/KEY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"見つかりません"* ]]
}

# === list ===

@test "list: 空のvault" {
  bash "$MANAGE" init
  run bash "$MANAGE" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"空です"* ]]
}

@test "list: キー名が表示される" {
  bash "$MANAGE" init
  echo "val1" | bash "$MANAGE" set "proj/KEY1"
  echo "val2" | bash "$MANAGE" set "proj/KEY2"
  run bash "$MANAGE" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"proj/KEY1"* ]]
  [[ "$output" == *"proj/KEY2"* ]]
}

# === delete ===

@test "delete: キーを削除できる" {
  bash "$MANAGE" init
  echo "val" | bash "$MANAGE" set "proj/KEY"
  run bash "$MANAGE" delete "proj/KEY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"削除完了"* ]]
  # 削除後のget はエラー
  run bash "$MANAGE" get "proj/KEY"
  [ "$status" -eq 1 ]
}

@test "delete: 存在しないキーはエラー" {
  bash "$MANAGE" init
  run bash "$MANAGE" delete "nonexistent/KEY"
  [ "$status" -eq 1 ]
  [[ "$output" == *"見つかりません"* ]]
}

# === verify ===

@test "verify: 正常なvault" {
  bash "$MANAGE" init
  echo "val" | bash "$MANAGE" set "proj/KEY"
  run bash "$MANAGE" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"整合性OK"* ]]
}

@test "verify: vault がない場合エラー" {
  run bash "$MANAGE" verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"見つかりません"* ]]
}

# === export-template ===

@test "export-template: SECRET:参照に変換される" {
  local projdir="${TEST_DIR}/testproj"
  mkdir -p "$projdir"
  cat > "${projdir}/.env" << 'EOF'
PORT=3000
API_KEY=sk-12345
DB_PASSWORD=secret123
NORMAL_VAR=hello
EOF
  run bash "$MANAGE" export-template "${projdir}/.env"
  [ "$status" -eq 0 ]
  [[ "$output" == *"API_KEY=SECRET:testproj/API_KEY"* ]]
  [[ "$output" == *"DB_PASSWORD=SECRET:testproj/DB_PASSWORD"* ]]
  [[ "$output" == *"PORT=3000"* ]]
  [[ "$output" == *"NORMAL_VAR=hello"* ]]
}

# === resolve ===

@test "resolve: SECRET:参照を解決してコマンド実行" {
  bash "$MANAGE" init
  echo "resolved-secret" | bash "$MANAGE" set "testproj/API_KEY"

  local envfile="${TEST_DIR}/.env"
  cat > "$envfile" << 'EOF'
API_KEY=SECRET:testproj/API_KEY
PORT=3000
EOF
  run bash "$RESOLVE" "$envfile" env
  [ "$status" -eq 0 ]
  [[ "$output" == *"API_KEY=resolved-secret"* ]]
  [[ "$output" == *"PORT=3000"* ]]
}

# === help ===

@test "help: ヘルプが表示される" {
  run bash "$MANAGE" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret-store"* ]]
  [[ "$output" == *"verify"* ]]
  [[ "$output" == *"rotate"* ]]
}

# === ShellCheck ===

@test "shellcheck: secret-manage.sh に警告なし" {
  # CIでは専用のshellcheckジョブが実行するためスキップ
  [[ -n "${CI:-}" ]] && skip "CI has dedicated shellcheck job"
  command -v shellcheck &>/dev/null || skip "shellcheck not available"
  run shellcheck "$BATS_TEST_DIRNAME/../secret-manage.sh"
  [ "$status" -eq 0 ]
}

@test "shellcheck: secret-resolve.sh に警告なし" {
  [[ -n "${CI:-}" ]] && skip "CI has dedicated shellcheck job"
  command -v shellcheck &>/dev/null || skip "shellcheck not available"
  run shellcheck "$BATS_TEST_DIRNAME/../secret-resolve.sh"
  [ "$status" -eq 0 ]
}
