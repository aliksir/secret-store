# secret-store

ローカル `.env` ファイルの機密値をGPG暗号化ボルトで管理するシェルスクリプトツール。`.env` に参照（`SECRET:project/KEY`）だけ残し、実際の値を暗号化保存する。

## 技術スタック
- bash（Git Bash on Windows / ネイティブ on macOS・Linux）
- gpg（GnuPG）— 暗号化
- jq — JSON処理

## セットアップ
```bash
# クローン後、ボルトを初期化（GPGパスフレーズを設定する）
./secret-manage.sh init
```

## ビルド
該当なし（シェルスクリプトのため）

## テスト
該当なし（自動テストなし）

## 開発規約
- `settings.json` やその他の設定ファイルは自動変更しない（`.env` のみ操作対象）
- `--fix` 相当の破壊操作を行う前は必ずバックアップを作成する
- GPGパスフレーズはいかなるファイルにも保存しない
- メインスクリプト: `secret-manage.sh`、解決ラッパー: `secret-resolve.sh`
