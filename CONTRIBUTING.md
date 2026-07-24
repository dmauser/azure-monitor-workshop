# Contributing

Thanks for your interest in improving the **Azure Monitor Observability Workshop**! This lab is
meant to be a clean, reusable teaching asset, so contributions that make it easier to run,
clearer to follow, or more accurate are very welcome.

## Ways to contribute

- 🐛 **Report a bug** — open an issue describing what you ran, what you expected, and what happened.
- 📖 **Improve the docs** — fix typos, clarify steps, or add screenshots under `docs/images/`.
- ✨ **Add or refine a scenario** — new Data Collection Rules, telemetry generators, or demos.
- 🧹 **Housekeeping** — dependency bumps, script hardening, cross-platform fixes.

## Before you start

This repository ships **no customer data**. Please keep it that way:

- **Never commit** real subscription IDs, tenant IDs, object/principal IDs, resource names,
  email addresses, or machine paths. Use placeholders (e.g. `<SUBSCRIPTION_ID>`) or resolve
  values at runtime from `az account` / environment variables.
- Real values belong only in **gitignored** `config/*.env` files, which are never published.
- If you spot leaked identifiers anywhere in a tracked file, please open an issue.

## Development setup

```bash
git clone https://github.com/dmauser/azure-monitor-workshop.git
cd azure-monitor-workshop
pip install -r requirements.txt
az login
```

See the [Quickstart](README.md#-quickstart) and [Hands-On Lab](docs/hands-on-lab.md) for the
full deployment walkthrough.

## Coding conventions

- **Shell scripts** (`*.sh`) use **LF** line endings (enforced via `.gitattributes`). On Windows,
  run `git add --renormalize .` if you see line-ending noise in a diff.
- **PowerShell scripts** (`*.ps1`) use **CRLF** and should pass
  `[System.Management.Automation.Language.Parser]::ParseFile(...)` with no errors.
- Keep changes **surgical** — match the existing style and avoid unrelated reformatting.
- Prefer parameterized, idempotent scripts that read config from `config/*.env` or the `az` context.

## Submitting changes

1. Fork the repo and create a feature branch: `git checkout -b my-improvement`.
2. Make your change and verify scripts still parse / run.
3. Confirm no secrets or customer identifiers were added.
4. Open a pull request with a clear description of the *what* and *why*.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE) that covers this project.
