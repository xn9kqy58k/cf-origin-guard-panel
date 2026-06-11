#!/usr/bin/env bash
# Uninstall cf-origin-guard. By default, this removes firewall rules and services but keeps config and Nginx real_ip file.

set -Eeuo pipefail

PURGE="0"
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE="1" ;;
    -h|--help)
      cat <<HELP
Usage:
  bash uninstall.sh          Remove firewall rules, service/timer, cron fallback, binary. Keep config and Nginx real_ip file.
  bash uninstall.sh --purge  Also remove /etc/cf-origin-guard and generated real_ip files.
HELP
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: ${arg}" >&2
      exit 2
      ;;
  esac
 done

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: must run as root" >&2
    exit 1
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

need_root

if have_cmd systemctl; then
  systemctl disable --now cf-origin-guard.timer >/dev/null 2>&1 || true
  systemctl disable --now cf-origin-guard.service >/dev/null 2>&1 || true
fi

if [[ -x /usr/local/sbin/cf-origin-guard ]]; then
  /usr/local/sbin/cf-origin-guard remove || true
  /usr/local/sbin/cf-origin-guard realip-off || true
fi

rm -f /etc/systemd/system/cf-origin-guard.service
rm -f /etc/systemd/system/cf-origin-guard.timer
rm -f /etc/cron.d/cf-origin-guard
rm -f /usr/local/sbin/cf-origin-guard
rm -f /usr/local/bin/cf

if have_cmd systemctl; then
  systemctl daemon-reload >/dev/null 2>&1 || true
fi

if [[ "$PURGE" == "1" ]]; then
  rm -rf /etc/cf-origin-guard
  rm -f /www/server/panel/vhost/nginx/cf-origin-guard-realip.conf
  rm -f /etc/nginx/conf.d/cf-origin-guard-realip.conf
fi

echo "Uninstall completed."
if [[ "$PURGE" != "1" ]]; then
  echo "Config was kept. Use --purge to remove /etc/cf-origin-guard."
fi
