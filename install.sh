#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-latest}"
GITHUB_REPO="${GITHUB_REPO:-sanqto/sanction-screening-app-pub}"
BASE_URL="${SANCTION_RELEASE_URL:-}"
SERVICE_USER="${SERVICE_USER:-sanction-screening}"
SERVICE_NAME="sanction-screening"

if [[ "${EUID}" -ne 0 ]]; then
  echo "install.sh must run as root" >&2
  exit 1
fi

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }
}
need curl
if command -v sha256sum >/dev/null 2>&1; then
  SHA256_CMD="sha256sum -c"
elif command -v shasum >/dev/null 2>&1; then
  SHA256_CMD="shasum -a 256 -c"
else
  echo "missing required command: sha256sum or shasum" >&2
  exit 1
fi

random_hex_32() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  elif [[ -r /dev/urandom ]]; then
    LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 64
    echo
  else
    echo "cannot generate random key; install openssl" >&2
    exit 1
  fi
}

prompt_value() {
  local label="$1"
  local default_value="$2"
  local value=""
  if [[ -t 0 ]]; then
    read -r -p "$label [$default_value]: " value
  elif [[ -r /dev/tty ]]; then
    read -r -p "$label [$default_value]: " value </dev/tty
  fi
  if [[ -z "$value" ]]; then
    value="$default_value"
  fi
  printf '%s' "$value"
}

toml_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_initial_config() {
  local config_path="$1"
  local api_default audit_default token_default api_key audit_key eu_token data_dir_toml
  api_default="$(random_hex_32)"
  audit_default="$(random_hex_32)"
  token_default="dG9rZW4tMjAxNw"

  api_key="$(prompt_value "API key" "$api_default")"
  audit_key="$(prompt_value "Audit HMAC key" "$audit_default")"
  eu_token="$(prompt_value "EU FSF token" "$token_default")"
  data_dir_toml="$(toml_escape "$DATA_DIR")"

  cat >"$config_path" <<CONFIG
http_addr = "127.0.0.1:8080"
data_dir = "$data_dir_toml"
api_key = "$(toml_escape "$api_key")"
audit_hmac_key = "$(toml_escape "$audit_key")"
compliance_webhook_url = ""
refresh_interval_seconds = 3600
stale_list_max_hours = 24

eu_fsf_fetch_enabled = true
eu_fsf_rss_url = "https://webgate.ec.europa.eu/fsd/fsf/public/rss"
eu_fsf_url = "https://webgate.ec.europa.eu/fsd/fsf/public/files/xmlFullSanctionsList_1_1/content"
eu_fsf_token = "$(toml_escape "$eu_token")"

# Temporary fallback while EUROPA is unavailable. UN SC is not a replacement
# for the EU FSF compliance source, but it lets the appliance run and test.
un_sc_fetch_enabled = false
un_sc_url = "https://scsanctions.un.org/resources/xml/en/name/consolidated.xml"
CONFIG

  chmod 0600 "$config_path"
}

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS:$ARCH" in
  Linux:x86_64) TARGET="${TARGET:-x86_64-unknown-linux-gnu}" ;;
  Linux:aarch64|Linux:arm64) TARGET="${TARGET:-aarch64-unknown-linux-gnu}" ;;
  Darwin:x86_64)
    echo "macOS Intel is not published yet; set TARGET=x86_64-apple-darwin only if you uploaded that artifact manually" >&2
    exit 1
    ;;
  Darwin:arm64|Darwin:aarch64) TARGET="${TARGET:-aarch64-apple-darwin}" ;;
  *) echo "unsupported platform: $OS $ARCH" >&2; exit 1 ;;
esac

case "$OS" in
  Linux)
    INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
    CONFIG_DIR="${CONFIG_DIR:-/etc/sanction-screening}"
    DATA_DIR="${DATA_DIR:-/var/lib/sanction-screening}"
    ;;
  Darwin)
    INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
    CONFIG_DIR="${CONFIG_DIR:-/usr/local/etc/sanction-screening}"
    DATA_DIR="${DATA_DIR:-/usr/local/var/lib/sanction-screening}"
    ;;
esac

if [[ -z "$BASE_URL" ]]; then
  if [[ -z "$GITHUB_REPO" ]]; then
    echo "set GITHUB_REPO=owner/repo or SANCTION_RELEASE_URL=https://..." >&2
    exit 2
  fi
  if [[ "$VERSION" == "latest" ]]; then
    latest_url="$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/${GITHUB_REPO}/releases/latest")"
    tag="${latest_url##*/}"
    if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "could not resolve latest release tag from $latest_url" >&2
      exit 2
    fi
    VERSION="${tag#v}"
  else
    tag="v${VERSION}"
  fi
  BASE_URL="https://github.com/${GITHUB_REPO}/releases/download/${tag}"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

artifact="sanction-screening-${VERSION}-${TARGET}.tar.gz"
echo "downloading $artifact from $BASE_URL" >&2
curl -fsSLo "$tmp/$artifact" "$BASE_URL/$artifact"
curl -fsSLo "$tmp/$artifact.sha256" "$BASE_URL/$artifact.sha256"
(cd "$tmp" && $SHA256_CMD "$artifact.sha256")
tar -xzf "$tmp/$artifact" -C "$tmp"

if [[ "$OS" == "Linux" ]]; then
  id "$SERVICE_USER" >/dev/null 2>&1 || useradd --system --home "$DATA_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
  install -d -m 0755 "$CONFIG_DIR"
  install -d -m 0750 -o "$SERVICE_USER" -g "$SERVICE_USER" "$DATA_DIR"
else
  install -d -m 0755 "$CONFIG_DIR"
  install -d -m 0755 "$DATA_DIR"
fi
install -m 0755 "$tmp/sanction-screening" "$INSTALL_DIR/sanction-screening"
install -m 0755 "$tmp/sanction_screen.sh" "$INSTALL_DIR/sanction_screen.sh"

if [[ ! -f "$CONFIG_DIR/config.toml" ]]; then
  write_initial_config "$CONFIG_DIR/config.toml"
  echo "created $CONFIG_DIR/config.toml" >&2
  echo "review compliance_webhook_url and list-source settings before production use" >&2
  exit 0
fi

"$INSTALL_DIR/sanction-screening" refresh --config "$CONFIG_DIR/config.toml"

if [[ "$OS" == "Linux" ]]; then
  cat >/etc/systemd/system/${SERVICE_NAME}.service <<UNIT
[Unit]
Description=Sanction Screening API
After=network-online.target
Wants=network-online.target

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
ExecStart=$INSTALL_DIR/sanction-screening serve --config $CONFIG_DIR/config.toml
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=$DATA_DIR

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable --now ${SERVICE_NAME}.service
  echo "sanction-screening installed and started via systemd"
else
  plist="/Library/LaunchDaemons/com.sanqto.sanction-screening.plist"
  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.sanqto.sanction-screening</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_DIR/sanction-screening</string>
    <string>serve</string>
    <string>--config</string>
    <string>$CONFIG_DIR/config.toml</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/sanction-screening.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/sanction-screening.err</string>
</dict>
</plist>
PLIST
  chown root:wheel "$plist"
  chmod 0644 "$plist"
  launchctl bootout system "$plist" >/dev/null 2>&1 || true
  launchctl bootstrap system "$plist"
  launchctl enable system/com.sanqto.sanction-screening
  echo "sanction-screening installed and started via launchd"
fi
