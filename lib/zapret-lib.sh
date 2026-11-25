#!/usr/bin/env bash
#
# lib/zapret-lib.sh - общий движок zapret-discord-youtube для Linux.
#
# Не запускается сам по себе: его подключают
#   * zapret.sh            - CLI (start/stop/status/list/...)
#   * service.sh           - установка в systemd
#   * <стратегия>.sh       - файлы стратегий в корне репозитория
#
# Вместо winws.exe/WinDivert используется nfqws (Linux/NFQUEUE).
# Параметры стратегий (--dpi-desync, hostlist, ipset, фейки) перенесены
# из general*.bat; --wf-tcp/--wf-udp заменены правилами iptables/nftables.
#
# Переменные окружения:
#   NFQWS=/путь/к/nfqws  QNUM=200  ZAPRET_LOG=/var/log/zapret-linux.log
#   NFQWS_UID=uid[:gid]   под каким пользователем работает nfqws
#                         (по умолчанию - владелец каталога lists/)
#

ZAPRET_DIR=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
SCRIPT_DIR="$ZAPRET_DIR"
BIN="$ZAPRET_DIR/bin/"
LISTS="$ZAPRET_DIR/lists/"
UTILS="$ZAPRET_DIR/utils/"

QNUM="${QNUM:-200}"
PIDFILE="${ZAPRET_PIDFILE:-/run/zapret-linux.pid}"
STATEFILE="${ZAPRET_STATEFILE:-/run/zapret-linux.state}"
LOGFILE="${ZAPRET_LOG:-/var/log/zapret-linux.log}"
UNIT_NAME="zapret-linux"
TABLE_NAME="zapret_dy"
DESYNC_MARK="0x40000000"

BASE_TCP_PORTS="80,443,2053,2083,2087,2096,8443"
BASE_UDP_PORTS="443,19294-19344,50000-50100"

# как --wf-filter-lan=1 в winws: не трогаем локальные сети
# (iptables не разрешает несколько -d, поэтому используем iprange)
LAN_MATCH4=(-m iprange '!' --dst-range 10.0.0.0-10.255.255.255
            -m iprange '!' --dst-range 172.16.0.0-172.31.255.255
            -m iprange '!' --dst-range 192.168.0.0-192.168.255.255
            -m iprange '!' --dst-range 127.0.0.0-127.255.255.255
            -m iprange '!' --dst-range 169.254.0.0-169.254.255.255)
LAN_MATCH6=(-m iprange '!' --dst-range fc00::-fc00:ffff:ffff:ffff:ffff:ffff:ffff:ffff
            -m iprange '!' --dst-range fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
            -m iprange '!' --dst-range ::1-::1)
NFT_LAN4='{ 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8, 169.254.0.0/16 }'
NFT_LAN6='{ fc00::/7, fe80::/10, ::1/128 }'

# значения по умолчанию; файл стратегии переопределяет их после подключения lib
GAME_FILTER_TCP="12"
GAME_FILTER_UDP="12"
STRATEGY_NAME=""
NFQWS_ARGS=()
NFQWS_BIN=""
TCP_PORTS=""
UDP_PORTS=""
TCP_PORTS_IPT=""
UDP_PORTS_IPT=""
IPTABLES_AVAILABLE=""
NFT_AVAILABLE=""

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_root() {
    [ "$(id -u)" -eq 0 ] || die "нужны права root: sudo $0 $*"
}

find_nfqws() {
    local c
    if [ -n "${NFQWS:-}" ]; then
        [ -x "$NFQWS" ] || die "NFQWS=$NFQWS не найден или не исполняемый"
        NFQWS_BIN="$NFQWS"
        return
    fi
    for c in "${BIN}nfqws" /opt/zapret/nfqws /usr/local/bin/nfqws /usr/bin/nfqws; do
        if [ -x "$c" ]; then
            NFQWS_BIN="$c"
            return
        fi
    done
    c=$(command -v nfqws 2>/dev/null || true)
    [ -n "$c" ] && { NFQWS_BIN="$c"; return; }
    die "nfqws не найден. Установите zapret для Linux (https://github.com/bol-van/zapret/releases),
возьмите binaries/linux-x86_64/nfqws, положите в $BIN
или запустите: $ZAPRET_DIR/zapret.sh --install-nfqws"
}

download_file() {
    # $1 - url, $2 - destination
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        die "нужен curl или wget"
    fi
}

fetch_text() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$1"
    else
        die "нужен curl или wget"
    fi
}

install_nfqws() {
    local arch tag tmp tarball url

    case "$(uname -m)" in
        x86_64|amd64)        arch="linux-x86_64" ;;
        i386|i486|i586|i686) arch="linux-x86" ;;
        aarch64|arm64)       arch="linux-arm64" ;;
        armv6l|armv7l|arm)   arch="linux-arm" ;;
        mips64|mips)         arch="linux-mips" ;;
        mipsel)              arch="linux-mipsel" ;;
        ppc|ppc64)           arch="linux-ppc" ;;
        *) die "неизвестная архитектура $(uname -m). Скачайте nfqws вручную" ;;
    esac

    command -v tar >/dev/null 2>&1 || die "нужен tar"
    command -v sha256sum >/dev/null 2>&1 || die "нужен sha256sum (coreutils)"

    say "Определение последней версии zapret..."
    tag=$(fetch_text "https://api.github.com/repos/bol-van/zapret/releases/latest" |
          sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
    [ -n "$tag" ] || die "не удалось определить последнюю версию zapret (GitHub API)"

    tmp=$(mktemp -d)
    tarball="$tmp/zapret.tar.gz"
    url="https://github.com/bol-van/zapret/releases/download/$tag/zapret-$tag.tar.gz"
    say "Скачивание $url"
    download_file "$url" "$tarball" || { rm -rf "$tmp"; die "не удалось скачать $url"; }
    download_file "https://github.com/bol-van/zapret/releases/download/$tag/sha256sum.txt" \
        "$tmp/sha256sum.txt" 2>/dev/null || true

    tar -xzf "$tarball" -C "$tmp" || { rm -rf "$tmp"; die "не удалось распаковать архив"; }
    local src expected actual
    src=$(find "$tmp" -path "*/binaries/$arch/nfqws" -type f | head -n1)
    [ -n "$src" ] || { rm -rf "$tmp"; die "в архиве нет binaries/$arch/nfqws"; }

    if [ -s "$tmp/sha256sum.txt" ]; then
        expected=$(grep "binaries/$arch/nfqws\$" "$tmp/sha256sum.txt" | awk '{print $1}' | head -n1)
        actual=$(sha256sum "$src" | awk '{print $1}')
        if [ -n "$expected" ] && [ "$expected" != "$actual" ]; then
            rm -rf "$tmp"
            die "контрольная сумма nfqws не совпала"
        fi
    else
        warn "sha256sum.txt недоступен, проверка контрольной суммы пропущена"
    fi

    mkdir -p "$BIN"
    install -m 0755 "$src" "${BIN}nfqws"
    rm -rf "$tmp"

    "${BIN}nfqws" --version || die "установленный nfqws не запускается"
    say "Установлено: ${BIN}nfqws"
}

load_user_lists() {
    [ -d "$LISTS" ] || die "нет каталога $LISTS"
    [ -f "$LISTS/ipset-exclude-user.txt" ] ||
        printf '203.0.113.113/32\n' >"$LISTS/ipset-exclude-user.txt"
    [ -f "$LISTS/list-general-user.txt" ] ||
        printf '# Never leave this file empty\ndomain.example.abc\n' >"$LISTS/list-general-user.txt"
    [ -f "$LISTS/list-exclude-user.txt" ] ||
        printf 'domain.example.abc\n' >"$LISTS/list-exclude-user.txt"
    for f in ipset-all.txt ipset-exclude.txt list-general.txt list-exclude.txt list-google.txt; do
        [ -f "$LISTS/$f" ] || die "нет файла $LISTS/$f — проверьте целостность репозитория"
    done
}

valid_port_list() {
    [[ "$1" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]]
}

load_game_filter() {
    local file="$UTILS/game_filter.enabled"
    local mode="" key val all="" tcp="" udp="" line

    if [ -f "$file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            case "$line" in ''|'#'*) continue ;; esac
            key="${line%%=*}"
            val=""
            [ "$key" != "$line" ] && val="${line#*=}"
            key="${key//[[:space:]]/}"
            val="${val//[[:space:]]/}"
            case "${key,,}" in
                mode) mode="${val,,}" ;;
                all)  mode="all"; all="$val" ;;
                tcp)  tcp="$val" ;;
                udp)  udp="$val" ;;
            esac
        done <"$file"
    fi

    case "$mode" in
        all)
            GAME_FILTER_TCP="${all:-${tcp:-1024-65535}}"
            GAME_FILTER_UDP="${all:-${udp:-1024-65535}}"
            ;;
        tcp) GAME_FILTER_TCP="${tcp:-1024-65535}" ;;
        udp) GAME_FILTER_UDP="${udp:-1024-65535}" ;;
    esac

    valid_port_list "$GAME_FILTER_TCP" || GAME_FILTER_TCP="1024-65535"
    valid_port_list "$GAME_FILTER_UDP" || GAME_FILTER_UDP="1024-65535"
}

build_ports() {
    TCP_PORTS="$BASE_TCP_PORTS"
    UDP_PORTS="$BASE_UDP_PORTS"
    [ "$GAME_FILTER_TCP" != "12" ] && TCP_PORTS="$TCP_PORTS,$GAME_FILTER_TCP"
    [ "$GAME_FILTER_UDP" != "12" ] && UDP_PORTS="$UDP_PORTS,$GAME_FILTER_UDP"
    # iptables multiport: port1-port2 -> port1:port2
    TCP_PORTS_IPT=$(printf '%s' "$TCP_PORTS" | tr '-' ':')
    UDP_PORTS_IPT=$(printf '%s' "$UDP_PORTS" | tr '-' ':')
}

choose_firewall_tool() {
    IPTABLES_AVAILABLE=""
    NFT_AVAILABLE=""
    command -v iptables >/dev/null 2>&1 && IPTABLES_AVAILABLE=1
    command -v nft >/dev/null 2>&1 && NFT_AVAILABLE=1
    [ -n "$IPTABLES_AVAILABLE" ] || [ -n "$NFT_AVAILABLE" ] ||
        die "не найден ни iptables, ни nft. Установите iptables или nftables"
}

apply_firewall() {
    local tool lan added=0

    if [ -z "$IPTABLES_AVAILABLE" ]; then
        remove_firewall
        nft add table inet "$TABLE_NAME" || die "nft: не удалось создать таблицу"
        nft "add chain inet $TABLE_NAME post { type filter hook postrouting priority mangle; policy accept; }" ||
            die "nft: не удалось создать цепочку"
        nft add rule inet "$TABLE_NAME" post mark "&" "$DESYNC_MARK" "!=" "$DESYNC_MARK" \
            meta nfproto ipv4 ip daddr "!=" "$NFT_LAN4" \
            tcp dport "{ $TCP_PORTS }" queue num "$QNUM" bypass ||
            die "nft: не удалось добавить правило TCP/IPv4"
        nft add rule inet "$TABLE_NAME" post mark "&" "$DESYNC_MARK" "!=" "$DESYNC_MARK" \
            meta nfproto ipv6 ip6 daddr "!=" "$NFT_LAN6" \
            tcp dport "{ $TCP_PORTS }" queue num "$QNUM" bypass ||
            die "nft: не удалось добавить правило TCP/IPv6"
        nft add rule inet "$TABLE_NAME" post mark "&" "$DESYNC_MARK" "!=" "$DESYNC_MARK" \
            meta nfproto ipv4 ip daddr "!=" "$NFT_LAN4" \
            udp dport "{ $UDP_PORTS }" queue num "$QNUM" bypass ||
            die "nft: не удалось добавить правило UDP/IPv4"
        nft add rule inet "$TABLE_NAME" post mark "&" "$DESYNC_MARK" "!=" "$DESYNC_MARK" \
            meta nfproto ipv6 ip6 daddr "!=" "$NFT_LAN6" \
            udp dport "{ $UDP_PORTS }" queue num "$QNUM" bypass ||
            die "nft: не удалось добавить правило UDP/IPv6"
        say "Firewall: nftables (inet $TABLE_NAME, NFQUEUE $QNUM)"
        return
    fi

    for tool in iptables ip6tables; do
        command -v "$tool" >/dev/null 2>&1 || continue
        if [ "$tool" = "ip6tables" ]; then
            lan=("${LAN_MATCH6[@]}")
        else
            lan=("${LAN_MATCH4[@]}")
        fi
        if "$tool" -w 5 -t mangle -I POSTROUTING "${lan[@]}" -p tcp \
                -m mark ! --mark "$DESYNC_MARK/$DESYNC_MARK" \
                -m multiport --dports "$TCP_PORTS_IPT" \
                -j NFQUEUE --queue-num "$QNUM" --queue-bypass; then
            say "Firewall: $tool (TCP $TCP_PORTS -> NFQUEUE $QNUM)"
            added=$((added + 1))
        else
            warn "$tool: не удалось добавить правило TCP (модули NFQUEUE/multiport/mark?)"
        fi
        if "$tool" -w 5 -t mangle -I POSTROUTING "${lan[@]}" -p udp \
                -m mark ! --mark "$DESYNC_MARK/$DESYNC_MARK" \
                -m multiport --dports "$UDP_PORTS_IPT" \
                -j NFQUEUE --queue-num "$QNUM" --queue-bypass; then
            say "Firewall: $tool (UDP $UDP_PORTS -> NFQUEUE $QNUM)"
            added=$((added + 1))
        else
            warn "$tool: не удалось добавить правило UDP (модули NFQUEUE/multiport/mark?)"
        fi
    done

    [ "$added" -gt 0 ] || die "не удалось добавить ни одного правила firewall"
}

remove_firewall() {
    local tool lan n

    if command -v nft >/dev/null 2>&1; then
        nft delete table inet "$TABLE_NAME" 2>/dev/null || true
    fi
    for tool in iptables ip6tables; do
        command -v "$tool" >/dev/null 2>&1 || continue
        if [ "$tool" = "ip6tables" ]; then
            lan=("${LAN_MATCH6[@]}")
        else
            lan=("${LAN_MATCH4[@]}")
        fi
        n=0
        while [ "$n" -lt 20 ] && "$tool" -w 5 -t mangle -D POSTROUTING "${lan[@]}" -p tcp \
                -m mark ! --mark "$DESYNC_MARK/$DESYNC_MARK" \
                -m multiport --dports "$TCP_PORTS_IPT" \
                -j NFQUEUE --queue-num "$QNUM" --queue-bypass 2>/dev/null; do
            n=$((n + 1))
        done
        n=0
        while [ "$n" -lt 20 ] && "$tool" -w 5 -t mangle -D POSTROUTING "${lan[@]}" -p udp \
                -m mark ! --mark "$DESYNC_MARK/$DESYNC_MARK" \
                -m multiport --dports "$UDP_PORTS_IPT" \
                -j NFQUEUE --queue-num "$QNUM" --queue-bypass 2>/dev/null; do
            n=$((n + 1))
        done
    done
}

running_pid() {
    local pid
    [ -f "$PIDFILE" ] || return 1
    pid=$(cat "$PIDFILE" 2>/dev/null || true)
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    # не убиваем чужой процесс, если pid переиспользован
    if [ -r "/proc/$pid/cmdline" ]; then
        tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q 'nfqws' || return 1
    fi
    printf '%s' "$pid"
}

prepare() {
    find_nfqws
    load_user_lists
    load_game_filter
    build_ports
    choose_firewall_tool
}

nfqws_args() {
    local uid gid
    uid=$(stat -c %u "$LISTS" 2>/dev/null || true)
    gid=$(stat -c %g "$LISTS" 2>/dev/null || true)
    case "$uid" in ''|*[!0-9]*) uid=0 ;; esac
    case "$gid" in ''|*[!0-9]*) gid=0 ;; esac

    NFQWS_CMD=("$NFQWS_BIN" "--qnum=$QNUM" "--dpi-desync-fwmark=$DESYNC_MARK")

    # nfqws по умолчанию сбрасывает root до uid 0x7FFFFFFF и затем проверяет,
    # что сможет перечитать файлы списков. Если репозиторий лежит в домашнем
    # каталоге (например 750), эта проверка падает с "file_open_test: Permission
    # denied". Работаем под владельцем каталога lists/ — он точно может читать
    # свои файлы. Переопределить: NFQWS_UID=uid[:gid].
    # Флаг добавляем только от root: без root nfqws всё равно не сбросит права,
    # а --uid заставил бы его пытаться это сделать (setgroups: EPERM).
    if [ "$(id -u)" -eq 0 ]; then
        NFQWS_CMD+=("--uid=${NFQWS_UID:-$uid:$gid}")
    fi
    NFQWS_CMD+=("${NFQWS_ARGS[@]}")
}

stop_zapret() {
    local pid
    [ -n "$TCP_PORTS_IPT" ] || { load_game_filter; build_ports; }

    if pid=$(running_pid); then
        kill "$pid" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        kill -9 "$pid" 2>/dev/null || true
        say "Остановлено (pid $pid)"
    else
        say "zapret не запущен"
    fi
    rm -f "$PIDFILE" "$STATEFILE"
    remove_firewall
}

start_zapret() {
    local pid i

    prepare

    if pid=$(running_pid); then
        say "zapret уже запущен (pid $pid). Перезапуск..."
        stop_zapret
    else
        remove_firewall
    fi

    apply_firewall
    mkdir -p "$(dirname "$LOGFILE")"
    nfqws_args

    say "Стратегия: $STRATEGY_NAME"
    say "nfqws: $NFQWS_BIN"
    say "Запуск..."

    nohup "${NFQWS_CMD[@]}" >>"$LOGFILE" 2>&1 &
    pid=$!
    echo "$pid" >"$PIDFILE"
    echo "$STRATEGY_NAME" >"$STATEFILE"

    for i in 1 2 3 4 5; do
        sleep 0.2
        kill -0 "$pid" 2>/dev/null || break
    done

    if kill -0 "$pid" 2>/dev/null; then
        say "Готово. PID $pid, лог: $LOGFILE"
    else
        rm -f "$PIDFILE" "$STATEFILE"
        remove_firewall
        warn "nfqws завершился с ошибкой. Последние строки лога:"
        if [ -f "$LOGFILE" ]; then
            tail -n 20 "$LOGFILE" >&2
            if tail -n 20 "$LOGFILE" | grep -qE 'file_open_test|cannot access (hostlist|ipset)'; then
                warn ""
                warn "nfqws не смог прочитать файлы списков после сброса прав."
                warn "Попробуйте: sudo NFQWS_UID=0:0 $0"
            fi
        fi
        exit 1
    fi
}

run_zapret() {
    local pid
    if pid=$(running_pid); then
        die "zapret уже запущен (pid $pid). Сначала: $0 stop"
    fi

    prepare
    apply_firewall
    nfqws_args

    trap 'remove_firewall' EXIT INT TERM
    say "Стратегия: $STRATEGY_NAME (передний план, Ctrl+C для выхода)"
    "${NFQWS_CMD[@]}"
}

dry_run() {
    prepare
    nfqws_args
    say "Стратегия: $STRATEGY_NAME"
    say "Порты TCP: $TCP_PORTS; UDP: $UDP_PORTS; game TCP=$GAME_FILTER_TCP UDP=$GAME_FILTER_UDP"
    say "fwmark: $DESYNC_MARK"
    "${NFQWS_CMD[@]}" --dry-run
}

check_env() {
    prepare
    nfqws_args

    say "root: OK"
    say "nfqws: $NFQWS_BIN"
    "$NFQWS_BIN" --version 2>/dev/null | head -n1 || true
    say "Порты TCP: $TCP_PORTS; UDP: $UDP_PORTS; game TCP=$GAME_FILTER_TCP UDP=$GAME_FILTER_UDP"
    say "fwmark: $DESYNC_MARK"

    say ""
    say "1) firewall: добавляю и сразу удаляю правила..."
    trap 'remove_firewall' EXIT
    apply_firewall
    remove_firewall
    trap - EXIT
    say "   OK: правила добавляются и удаляются"

    say ""
    say "2) nfqws: проверка параметров..."
    if "${NFQWS_CMD[@]}" --dry-run; then
        say "   OK: nfqws принимает параметры"
    else
        die "nfqws не принял параметры (см. сообщения выше)"
    fi

    say ""
    if strategy_exists "$STRATEGY_NAME"; then
        say "Диагностика пройдена. Можно запускать: sudo $(strategy_file "$STRATEGY_NAME")"
    else
        say "Диагностика пройдена. Можно запускать: sudo $ZAPRET_DIR/zapret.sh start $STRATEGY_NAME"
    fi
}

show_status() {
    local pid strategy
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$UNIT_NAME.service"; then
        say "systemd: $UNIT_NAME.service активен"
    fi
    if pid=$(running_pid); then
        strategy=$(cat "$STATEFILE" 2>/dev/null || echo "?")
        say "zapret запущен: pid $pid, стратегия: $strategy"
        if command -v nft >/dev/null 2>&1 && nft list table inet "$TABLE_NAME" >/dev/null 2>&1; then
            say "Firewall: nftables inet $TABLE_NAME"
        elif [ "$(id -u)" -ne 0 ]; then
            say "Firewall: для проверки правил запустите: sudo $0 status"
        elif command -v iptables >/dev/null 2>&1; then
            if iptables -t mangle -S POSTROUTING 2>/dev/null | grep -q "NFQUEUE.*$QNUM"; then
                say "Firewall: iptables POSTROUTING -> NFQUEUE $QNUM"
            else
                say "ВНИМАНИЕ: правила iptables не найдены"
            fi
        fi
    else
        say "zapret не запущен"
        if [ -f "$PIDFILE" ]; then
            warn "остался устаревший pid-файл $PIDFILE"
        fi
    fi
}


strategy_file() {
    printf '%s/%s.sh' "$ZAPRET_DIR" "$1"
}

# файл стратегии содержит маркер "# zapret-strategy: <имя>"
strategy_exists() {
    local f
    f=$(strategy_file "$1")
    [ -f "$f" ] && sed -n '1,3p' "$f" | grep -q '^# zapret-strategy: '
}

list_strategies() {
    local f name src
    say "Доступные стратегии:"
    say ""
    while IFS= read -r f; do
        name=$(sed -n 's/^# zapret-strategy: //p' "$f" | head -n1)
        [ -n "$name" ] || continue
        src=$(sed -n 's/^# source: //p' "$f" | head -n1)
        printf '  %-24s из %s\n' "$name" "${src:-<неизвестно>}"
    done < <(LC_ALL=C ls -1 "$ZAPRET_DIR"/*.sh 2>/dev/null)
    say ""
    say "Запуск: sudo $ZAPRET_DIR/<стратегия>.sh  (например, sudo $ZAPRET_DIR/general.sh)"
}

strategy_usage() {
    say "Стратегия: $STRATEGY_NAME"
    say ""
    say "  sudo $0              запустить в фоне"
    say "  sudo $0 run          запустить в переднем плане (Ctrl+C - выход)"
    say "  $0 --dry-run         проверить параметры без запуска"
    say "  sudo $0 check        диагностика: root, firewall, nfqws"
    say "  sudo $0 stop         остановить"
    say "  $0 status            показать состояние"
}

# точка входа для файлов стратегий
strategy_cli() {
    local cmd="${1:-start}"
    case "$cmd" in
        start)
            need_root "$@"
            start_zapret
            ;;
        run)
            need_root "$@"
            run_zapret
            ;;
        restart)
            need_root "$@"
            stop_zapret
            start_zapret
            ;;
        check)
            need_root "$@"
            check_env
            ;;
        dry-run|--dry-run)
            dry_run
            ;;
        stop)
            need_root "$@"
            stop_zapret
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            strategy_usage
            ;;
        *)
            die "неизвестная команда '$cmd'. Справка: $0 --help"
            ;;
    esac
}
