# secret-store

> **[日本語版 README はこちら](README.ja.md)**

Local secret management for `.env` files. Replaces actual secret values with references (`SECRET:project/KEY`), stores real values in a GPG-encrypted vault.

If your `.env` leaks, only references are exposed — not the actual secrets.

## How it works

```
.env (references only)         ~/.secrets/vault.json.gpg (encrypted)
┌──────────────────────┐       ┌─────────────────────────────┐
│ API_KEY=SECRET:myapp/ │──────▶│ {"myapp/API_KEY": "sk-xxx"} │
│ API_KEY              │       └─────────────────────────────┘
│ PORT=3000            │                    │
└──────────────────────┘           secret-resolve.sh
                                           │
                                    env vars (memory only)
                                           │
                                      exec your-app
```

## Requirements

- **bash** (Git Bash on Windows, or native on macOS/Linux)
- **gpg** (GnuPG) — encryption
- **jq** — JSON processing

## Quick Start

```bash
# 1. Clone
git clone https://github.com/aliksir/secret-store.git
cd secret-store

# 2. Initialize vault (sets GPG passphrase)
./secret-manage.sh init

# 3. Migrate your .env (one command does everything)
./secret-manage.sh migrate /path/to/your/app/.env

# 4. Start your app
cd /path/to/your/app
./start-with-secrets.sh python app.py
```

That's it. Your `.env` now contains only references. Real values are in the encrypted vault.

## Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize vault and create pattern config |
| `migrate <.env>` | **One-command migration**: backup → detect secrets → store in vault → rewrite .env → generate launch wrapper |
| `set <project/KEY>` | Manually register a secret |
| `get <project/KEY>` | Retrieve a secret value |
| `list` | List all keys (values hidden) |
| `delete <project/KEY>` | Remove a secret |
| `export-template <.env>` | Preview what migration would change |
| `backup <.env>` | Create encrypted backup of .env |
| `restore <project>` | Restore .env from backup |

## What `migrate` does

```
secret-manage.sh migrate .env
  ├─ ⚠️  Warns about running services
  ├─ Step 1: Encrypted backup of current .env
  ├─ Step 2: Auto-detect secret keys → store in vault
  ├─ Step 3: Rewrite .env with SECRET: references
  └─ Step 4: Generate start-with-secrets.sh/.ps1 wrappers
```

**Zero code changes required** in your application. The wrapper resolves references before launching your app.

## Secret Detection

Keys matching these patterns are treated as secrets:

```
KEY, SECRET, TOKEN, PASSWORD, CREDENTIAL, API_KEY, BEARER
```

Customize by editing `~/.secrets/.secretsrc`:

```
# One pattern per line
KEY
SECRET
TOKEN
MY_CUSTOM_PATTERN
```

## Windows (PowerShell)

On Windows, use the generated `.ps1` wrapper:

```powershell
cd C:\path\to\your\app
.\start-with-secrets.ps1 python app.py
```

The wrapper auto-detects Git Bash location. No manual path configuration needed.

## Rollback

```bash
# Restore original .env from encrypted backup
./secret-manage.sh restore myapp
```

Backups are stored encrypted at `~/.secrets/backups/`.

## Important Notes

- **Stop running services before migrating.** If your app runs as a service (systemd, nssm, etc.), stop it first. After migration, update the service to launch via `start-with-secrets.sh`.
- GPG passphrase exists only in your memory — not stored in any file.
- Vault location can be customized via `SECRET_STORE_DIR` environment variable.
- This tool **does not** auto-modify `settings.json` or any config — it only manages `.env` files.

## Disclaimer

**Use at your own risk.**

- This is not an official tool from any cloud provider or security company.
- GPG encryption strength depends on your passphrase quality.
- Always verify backups work before migrating production secrets.
- The author assumes no liability for any damages arising from use of this tool.

## License

MIT
