#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-0.1.0}"
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
  BASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}"
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
  install -m 0600 "$tmp/config.example.toml" "$CONFIG_DIR/config.toml"
  echo "created $CONFIG_DIR/config.toml; edit API_KEY, AUDIT_HMAC_KEY and EU_FSF_TOKEN before starting" >&2
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
