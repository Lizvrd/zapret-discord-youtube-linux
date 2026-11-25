#!/usr/bin/env bash
#
# zapret-discord-youtube для Linux - небольшая CLI поверх lib/zapret-lib.sh.
#
# Сами стратегии лежат отдельными файлами в корне (general.sh, alt.sh, ...)
# и запускаются напрямую:
#   sudo ./general.sh
#
# Через этот файл:
#   ./zapret.sh                    запустить general
#   ./zapret.sh alt                запустить стратегию alt
#   sudo ./zapret.sh start alt
#   sudo ./zapret.sh run alt       передний план, лог в консоль
#   sudo ./zapret.sh stop
#   sudo ./zapret.sh restart alt
#   ./zapret.sh status
#   sudo ./zapret.sh check alt     диагностика: root, firewall, nfqws
#   ./zapret.sh list
#   ./zapret.sh --dry-run alt      проверить параметры без запуска
#   ./zapret.sh --install-nfqws    скачать nfqws из последнего релиза zapret
#   sudo ./service.sh install alt  автозапуск через systemd
#
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
. "$SCRIPT_DIR/lib/zapret-lib.sh"

usage() {
    cat <<EOF
zapret-discord-youtube (Linux)

Использование:
  ./zapret.sh                  запустить general (нужен root)
  ./zapret.sh <стратегия>      запустить стратегию (см. list)
  sudo ./zapret.sh start <с>   запустить стратегию
  sudo ./zapret.sh run <с>     запуск в переднем плане
  sudo ./zapret.sh stop        остановить
  sudo ./zapret.sh restart <с> перезапустить
  ./zapret.sh status           состояние
  sudo ./zapret.sh check <с>   диагностика
  ./zapret.sh list             список стратегий
  ./zapret.sh --dry-run <с>    проверка параметров
  ./zapret.sh --install-nfqws  скачать nfqws

Стратегии также запускаются напрямую: sudo ./general.sh
Автозапуск: sudo ./service.sh install <стратегия>
EOF
}

run_strategy() {
    local cmd="$1" name="$2"
    strategy_exists "$name" || die "неизвестная стратегия '$name'. Список: $0 list"
    exec "$(strategy_file "$name")" "$cmd"
}

main() {
    local cmd="${1:-start}" name="${2:-general}"

    case "$cmd" in
        start|run|check)
            run_strategy "$cmd" "$name"
            ;;
        dry-run|--dry-run)
            run_strategy "dry-run" "$name"
            ;;
        restart)
            name="${2:-$(cat "$STATEFILE" 2>/dev/null || echo general)}"
            strategy_exists "$name" || die "неизвестная стратегия '$name'"
            need_root "$@"
            stop_zapret
            exec "$(strategy_file "$name")" start
            ;;
        stop)
            need_root "$@"
            stop_zapret
            ;;
        status)
            show_status
            ;;
        list|--list|-l)
            list_strategies
            ;;
        install-service)
            exec "$ZAPRET_DIR/service.sh" install "$name"
            ;;
        uninstall-service)
            exec "$ZAPRET_DIR/service.sh" uninstall
            ;;
        --install-nfqws)
            install_nfqws
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            # ./zapret.sh <стратегия> -> start <стратегия>
            if strategy_exists "$cmd"; then
                exec "$(strategy_file "$cmd")" start
            fi
            die "неизвестная команда '$cmd'. Справка: $0 --help"
            ;;
    esac
}

main "$@"
