# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2026-03-22

### Added
- `verify` command — check vault integrity and detect orphaned/missing entries
- `rotate` command — re-encrypt vault with a new passphrase
- Automated tests with bats-core and GPG wrapper for non-interactive testing
- GitHub Actions CI (shellcheck + bats tests)

### Fixed
- Replaced `ls` parsing with `find -print0` for safe filename handling
- Fixed all shellcheck warnings across both scripts
- CI: skip shellcheck within bats tests (delegated to dedicated shellcheck job)

## [1.0.0] - 2026-03-18

### Added
- `secret-manage.sh` — encrypt/decrypt/list/add/remove secrets in GPG vault
- `secret-resolve.sh` — resolve `SECRET_REF:` references in `.env` files at runtime
- GPG symmetric encryption (AES256) — no key pair management needed
- Reference-based `.env` + encrypted vault + exec wrapper architecture
- Japanese README (`README.ja.md`)
