#!/usr/bin/env bash
# Install cf-origin-guard visual panel on aaPanel / generic Nginx servers.

set -Eeuo pipefail

PROGRAM="cf-origin-guard"
INSTALL_BIN="/usr/local/sbin/cf-origin-guard"
INSTALL_CF="/usr/local/bin/cf"
CONFIG_DIR="/etc/cf-origin-guard"
CONFIG_FILE="${CONFIG_DIR}/cf-origin-guard.conf"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_dependencies() {
  local missing=0
  for cmd in curl ipset iptables; do
    if ! have_cmd "$cmd"; then
      missing=1
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    return 0
  fi

  echo "Installing dependencies: curl ca-certificates ipset iptables"

  if have_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl ca-certificates ipset iptables
    return 0
  fi

  if have_cmd dnf; then
    dnf install -y curl ca-certificates ipset iptables iptables-services || dnf install -y curl ca-certificates ipset iptables
    return 0
  fi

  if have_cmd yum; then
    yum install -y curl ca-certificates ipset iptables iptables-services || yum install -y curl ca-certificates ipset iptables
    return 0
  fi

  if have_cmd apk; then
    apk add --no-cache curl ca-certificates ipset iptables ip6tables
    return 0
  fi

  echo "ERROR: unsupported package manager. Install curl, ca-certificates, ipset, iptables manually, then rerun install.sh" >&2
  exit 1
}

install_binaries() {
  install -D -m 0755 "${REPO_DIR}/bin/cf-origin-guard" "${INSTALL_BIN}"
  install -D -m 0755 "${REPO_DIR}/bin/cf" "${INSTALL_CF}"
}

write_default_config() {
  mkdir -p "$CONFIG_DIR"

  if [[ -f "$CONFIG_FILE" ]]; then
    echo "Config exists, keep unchanged: ${CONFIG_FILE}"
    return 0
  fi

  local web_ports enable_ipv6 manage_realip nginx_realip_conf drop_action enable_guard enable_auto_sync
  enable_guard="${ENABLE_GUARD:-0}"
  enable_auto_sync="${ENABLE_AUTO_SYNC:-1}"
  web_ports="${WEB_PORTS:-80,443}"
  enable_ipv6="${ENABLE_IPV6:-auto}"
  manage_realip="${MANAGE_NGINX_REALIP:-0}"
  nginx_realip_conf="${NGINX_REALIP_CONF:-auto}"
  drop_action="${DROP_ACTION:-DROP}"

  cat > "$CONFIG_FILE" <<EOF_CONF
# cf-origin-guard configuration
# This file is shell syntax. Keep values quoted.

# Master switch. 1 = restrict protected web ports to Cloudflare IP ranges; 0 = disabled.
# Default is disabled: install does not immediately block existing traffic.
ENABLE_GUARD="${enable_guard}"

# Daily automatic Cloudflare IP synchronization through systemd timer or cron.
ENABLE_AUTO_SYNC="${enable_auto_sync}"

# Only these TCP ports will be restricted to Cloudflare source IP ranges.
# Do not put SSH or aaPanel management ports here unless they are also behind Cloudflare.
WEB_PORTS="${web_ports}"

# auto: manage IPv6 when ip6tables is available; 1: require IPv6; 0: disable IPv6 firewall rules.
ENABLE_IPV6="${enable_ipv6}"

# DROP is quieter and recommended for hiding direct-origin access.
# REJECT is easier to test but reveals that the origin is reachable.
DROP_ACTION="${drop_action}"

# Allow local health checks such as curl http://127.0.0.1/.
ALLOW_LOOPBACK="1"

# Generate Nginx real_ip config so xiaov2board / Nginx logs see real visitor IPs.
# Default is off to avoid changing existing Nginx behavior without confirmation.
# For aaPanel, auto writes: /www/server/panel/vhost/nginx/cf-origin-guard-realip.conf
# For generic Nginx, auto writes: /etc/nginx/conf.d/cf-origin-guard-realip.conf
MANAGE_NGINX_REALIP="${manage_realip}"
NGINX_REALIP_CONF="${nginx_realip_conf}"
NGINX_REALIP_STRICT="0"

# Official Cloudflare text lists.
CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

# Download behavior.
CURL_CONNECT_TIMEOUT="10"
CURL_MAX_TIME="45"
CURL_RETRIES="3"

# Optional direct-origin allowlist. Use only when a trusted system must bypass Cloudflare.
# Examples:
# EXTRA_ALLOWLIST_IPV4="203.0.113.10/32 198.51.100.0/24"
# EXTRA_ALLOWLIST_IPV6="2001:db8::10/128"
EXTRA_ALLOWLIST_IPV4=""
EXTRA_ALLOWLIST_IPV6=""

# Optional defaults used by the visual panel verification screen.
MENU_DEFAULT_DOMAIN=""
MENU_DEFAULT_ORIGIN_IP=""

LOG_FILE="/var/log/cf-origin-guard.log"
EOF_CONF

  chmod 0644 "$CONFIG_FILE"
  echo "Wrote default config: ${CONFIG_FILE}"
}

install_systemd_or_cron() {
  if have_cmd systemctl && [[ -d /run/systemd/system || "$(ps -p 1 -o comm= 2>/dev/null || true)" == "systemd" ]]; then
    install -D -m 0644 "${REPO_DIR}/systemd/cf-origin-guard.service" "/etc/systemd/system/cf-origin-guard.service"
    install -D -m 0644 "${REPO_DIR}/systemd/cf-origin-guard.timer" "/etc/systemd/system/cf-origin-guard.timer"
    systemctl daemon-reload
    systemctl enable cf-origin-guard.service >/dev/null || true
    if grep -q '^ENABLE_AUTO_SYNC="1"' "$CONFIG_FILE"; then
      systemctl enable --now cf-origin-guard.timer >/dev/null || true
      echo "Installed systemd service/timer: cf-origin-guard.service / cf-origin-guard.timer"
    else
      systemctl disable --now cf-origin-guard.timer >/dev/null 2>&1 || true
      echo "Installed systemd service. Timer is disabled by config."
    fi
    return 0
  fi

  if grep -q '^ENABLE_AUTO_SYNC="1"' "$CONFIG_FILE"; then
    cat > /etc/cron.d/cf-origin-guard <<'EOF_CRON'
# Update Cloudflare IP ranges and refresh origin firewall daily.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
17 4 * * * root /usr/local/sbin/cf-origin-guard apply >/dev/null 2>&1
EOF_CRON
    chmod 0644 /etc/cron.d/cf-origin-guard
    echo "Installed cron fallback: /etc/cron.d/cf-origin-guard"
  else
    rm -f /etc/cron.d/cf-origin-guard
    echo "Cron fallback is disabled by config."
  fi
}

main() {
  need_root

  if [[ ! -f "${REPO_DIR}/bin/cf-origin-guard" ]]; then
    echo "ERROR: ${REPO_DIR}/bin/cf-origin-guard not found" >&2
    exit 1
  fi
  if [[ ! -f "${REPO_DIR}/bin/cf" ]]; then
    echo "ERROR: ${REPO_DIR}/bin/cf not found" >&2
    exit 1
  fi
  chmod +x "${REPO_DIR}/bin/cf-origin-guard" "${REPO_DIR}/bin/cf" 2>/dev/null || true

  install_dependencies
  install_binaries
  write_default_config
  install_systemd_or_cron

  echo ""
  echo "Installation completed."
  echo "Visual panel: cf"
  echo "Status:       cf status"
  echo "Config:       ${CONFIG_FILE}"
  echo "Log:          /var/log/cf-origin-guard.log"
  echo ""
  echo "Default safety behavior: source protection is NOT enabled automatically."
  echo "Run 'cf', then choose option 1 to enable Cloudflare-only origin protection."
}

main "$@"
