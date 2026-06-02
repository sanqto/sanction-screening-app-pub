# Sanction Screening Server

Self-hosted sanctions screening server for companies that need to screen orders
locally before fulfilment. The app exposes a REST API, stores local audit
evidence in SQLite, and can refresh sanctions lists on a schedule.

This public repository is the distribution repository. It contains the
installer, release artifacts, example configuration, and API contract. Source
code is built from the private development repository.

## Install

```bash
curl -fsSL https://sanqto.com/install.sh | bash
```

The installer supports Linux and macOS. By default it installs in user mode and
does not create a daemon.

User mode creates:

- `$HOME/.config/sanction-screening/config.toml`
- `$HOME/.local/share/sanction-screening/`
- `$HOME/.local/bin/sanction-screening`
- `$HOME/.local/bin/sanction_screen.sh`
- `$HOME/.local/bin/sanction_screen_organization.sh`

Run the server manually:

```bash
$HOME/.local/bin/sanction-screening refresh --config $HOME/.config/sanction-screening/config.toml
$HOME/.local/bin/sanction-screening serve --config $HOME/.config/sanction-screening/config.toml
```

Run a one-shot screen without starting the REST API:

```bash
$HOME/.local/bin/sanction-screening check \
  --config $HOME/.config/sanction-screening/config.toml \
  --name "Ali Darassa" \
  --dob 1978-09-22 | jq
```

System service install is optional:

```bash
curl -fsSL https://sanqto.com/install.sh | sudo INSTALL_MODE=system bash
```

## Configure

Generate secrets:

```bash
openssl rand -hex 32
openssl rand -hex 32
```

The installer generates `api_key` and `audit_hmac_key` by default. Use
`X-API-Key` for REST calls, or `SANCTION_API_KEY` with `sanction_screen.sh`.
Leave `api_key` empty only if you intentionally want to disable API-key auth.

Fresh installs are non-interactive. To provide your own values, set
`SANCTION_INSTALL_API_KEY`, `SANCTION_INSTALL_AUDIT_HMAC_KEY`, or
`EU_FSF_TOKEN` before running `install.sh`.

EU FSF is enabled by default. For production use, configure a real EU FSF
token. Natural persons and organizations are loaded from this source:

```toml
eu_fsf_fetch_enabled = true
eu_fsf_token = "..."
un_sc_fetch_enabled = true
```

If EUROPA is unavailable and you need the appliance to keep running from other
sources, temporarily disable EU FSF:

```toml
eu_fsf_fetch_enabled = false
eu_fsf_token = ""
un_sc_fetch_enabled = true
un_sc_url = "https://scsanctions.un.org/resources/xml/en/name/consolidated.xml"
```

For Polish companies, keep the Polish MSWiA source enabled:

```toml
pl_mswia_fetch_enabled = true
pl_mswia_url = "https://sanqto.com/download/lista-sankcyjna-MSWiA.xml"
```

Organization screening currently loads companies from EU FSF, UN SC, UK
FCDO, and PL MSWiA. Additional organization sources are planned.

For UK screening, keep the UK FCDO source enabled:

```toml
uk_fcdo_fetch_enabled = true
uk_fcdo_url = "https://sanctionslist.fcdo.gov.uk/docs/UK-Sanctions-List.xml"
```

## Test API

```bash
sanction_screen.sh --name "Ali Darassa" --dob 1978-09-22 | jq
sanction_screen.sh --name "Ali Darassa" | jq
sanction-screening check-organization --config "$HOME/.config/sanction-screening/config.toml" --name "GO SPORT POLSKA" --identifier NIP:9511861015 | jq
sanction_screen_organization.sh --name "GO SPORT POLSKA" --identifier NIP:9511861015 --country PL | jq
```

The API returns `MATCH`, `POSSIBLE`, or `CLEAR` and pins `list_versions` in every
response and audit row.

## Endpoints

- `POST /v1/screen/person`
- `POST /v1/screen/organization`
- `GET /healthz`
- `GET /readyz`
- `GET /v1/lists/status`
- `GET /v1/audit`
- `GET /v1/audit/organizations`
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
