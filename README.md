# Sanction Screening Server

Self-hosted sanctions screening server for companies that need to screen orders
locally before fulfilment. The app exposes a REST API, stores local audit
evidence in SQLite, and can refresh sanctions lists on a schedule.

This public repository is the distribution repository. It contains the
installer, release artifacts, example configuration, and API contract. Source
code is built from the private development repository.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/sanqto/sanction-screening-app-pub/main/install.sh | bash
```

The installer supports Linux and macOS. By default it installs in user mode and
does not create a daemon.

User mode creates:

- `$HOME/.config/sanction-screening/config.toml`
- `$HOME/.local/share/sanction-screening/`
- `$HOME/.local/bin/sanction-screening`
- `$HOME/.local/bin/sanction_screen.sh`

Run the server manually:

```bash
$HOME/.local/bin/sanction-screening refresh --config $HOME/.config/sanction-screening/config.toml
$HOME/.local/bin/sanction-screening serve --config $HOME/.config/sanction-screening/config.toml
```

System service install is optional:

```bash
curl -fsSL https://raw.githubusercontent.com/sanqto/sanction-screening-app-pub/main/install.sh | sudo INSTALL_MODE=system bash
```

## Configure

Generate secrets:

```bash
openssl rand -hex 32
openssl rand -hex 32
```

Set `api_key` if you want the API to require `X-API-Key`. Leave it empty for
local deployments without API-key auth. Set the generated second value as
`audit_hmac_key`.

For EU FSF production use, configure a real EU FSF token:

```toml
eu_fsf_fetch_enabled = true
eu_fsf_token = "..."
un_sc_fetch_enabled = false
```

When EUROPA is unavailable, use the UN SC fallback:

```toml
eu_fsf_fetch_enabled = false
eu_fsf_token = ""
un_sc_fetch_enabled = true
un_sc_url = "https://scsanctions.un.org/resources/xml/en/name/consolidated.xml"
```

## Test API

```bash
sanction_screen.sh --name "Ali Darassa" --dob 1978-09-22 | jq
sanction_screen.sh --name "Ali Darassa" | jq
```

The API returns `MATCH`, `POSSIBLE`, or `CLEAR` and pins `list_versions` in every
response and audit row.

## Endpoints

- `POST /v1/screen/person`
- `GET /healthz`
- `GET /readyz`
- `GET /v1/lists/status`
- `GET /v1/audit`
- `POST /v1/admin/refresh`

See [docs/openapi.json](docs/openapi.json).

## Release Artifacts

GitHub Releases should contain:

- `sanction-screening-<version>-x86_64-unknown-linux-gnu.tar.gz`
- `sanction-screening-<version>-x86_64-unknown-linux-gnu.tar.gz.sha256`
- `sanction-screening-<version>-aarch64-unknown-linux-gnu.tar.gz`
- `sanction-screening-<version>-aarch64-unknown-linux-gnu.tar.gz.sha256`
- `sanction-screening-<version>-aarch64-apple-darwin.tar.gz`
- `sanction-screening-<version>-aarch64-apple-darwin.tar.gz.sha256`

The installer downloads the matching artifact for the host architecture.
