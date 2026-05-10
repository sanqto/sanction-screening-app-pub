# Sanction Screening API

Self-hosted sanctions screening API for companies that need to screen orders
locally before fulfilment. The app exposes a REST API, stores local audit
evidence in SQLite, and can refresh sanctions lists on a schedule.

This public repository is the distribution repository. It contains the
installer, release artifacts, example configuration, and API contract. Source
code is built from the private development repository.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/sanqto/sanction-screening-app-pub/main/install.sh | sudo bash
```

The installer supports Linux and macOS.

On Linux it creates:

- `/etc/sanction-screening/config.toml`
- `/var/lib/sanction-screening/`
- `/usr/local/bin/sanction-screening`
- `/usr/local/bin/sanction_screen.sh`
- a `systemd` service

On macOS it creates:

- `/usr/local/etc/sanction-screening/config.toml`
- `/usr/local/var/lib/sanction-screening/`
- `/usr/local/bin/sanction-screening`
- `/usr/local/bin/sanction_screen.sh`
- a `launchd` service at `/Library/LaunchDaemons/com.sanqto.sanction-screening.plist`

Edit `/etc/sanction-screening/config.toml`, set secrets and list-source config,
then rerun the installer or start the service:

```bash
sudo systemctl start sanction-screening
```

On macOS, edit `/usr/local/etc/sanction-screening/config.toml` and start with:

```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/com.sanqto.sanction-screening.plist
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
