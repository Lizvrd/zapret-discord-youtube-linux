#!/usr/bin/env bash
#
# service.sh - установка zapret в автозапуск через systemd.
#
#   sudo ./service.sh install [стратегия]   установить (по умолчанию general)
#   sudo ./service.sh uninstall             удалить службу
#   sudo ./service.sh restart               перезапустить службу
#   ./service.sh status                     состояние службы
#
# Служба называется zapret-linux.service.
#
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
. "$SCRIPT_DIR/lib/zapret-lib.sh"

UNIT_PATH="${ZAPRET_UNIT_PATH:-/etc/systemd/system/$UNIT_NAME.service}"

usage() {
    cat <<EOF
Управление службой zapret-linux.

  sudo ./service.sh install [стратегия]   установить автозапуск (general по умолчанию)
  sudo ./service.sh uninstall             удалить службу
  sudo ./service.sh restart               перезапустить
  ./service.sh status                     состояние
EOF
}

install_service() {
    local strategy="${1:-general}"

    need_root "$@"
    command -v systemctl >/dev/null 2>&1 || die "systemd не найден"
    strategy_exists "$strategy" || die "неизвестная стратегия '$strategy'. Список: ./zapret.sh list"

    cat >"$UNIT_PATH" <<EOF
[Unit]
Description=zapret-discord-youtube (strategy: $strategy)
Documentation=https://github.com/Flowseal/zapret-discord-youtube
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=$PIDFILE
ExecStart="$ZAPRET_DIR/zapret.sh" start $strategy
ExecStop="$ZAPRET_DIR/zapret.sh" stop

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$UNIT_NAME.service"
    say "Служба установлена: $UNIT_PATH (стратегия $strategy)"
    say "Проверить: systemctl status $UNIT_NAME.service"
}

uninstall_service() {
    need_root "$@"
    command -v systemctl >/dev/null 2>&1 || die "systemd не найден"

    systemctl disable --now "$UNIT_NAME.service" 2>/dev/null || true
    rm -f "$UNIT_PATH"
    systemctl daemon-reload
    say "Служба удалена: $UNIT_NAME.service"
}

status_service() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status "$UNIT_NAME.service" --no-pager -l 2>/dev/null || true
    else
        say "systemd не найден"
    fi
}

case "${1:-help}" in
    install)   shift; install_service "$@" ;;
    uninstall) uninstall_service "$@" ;;
    restart)   need_root "$@"; systemctl restart "$UNIT_NAME.service" ;;
    status)    status_service ;;
    help|--help|-h|*) usage ;;
esac
