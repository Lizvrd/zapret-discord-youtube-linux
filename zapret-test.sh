#!/usr/bin/env bash
#
# Тест стратегий zapret-discord-youtube для Linux.
# Аналог service.bat -> Run Tests -> Standard tests -> All configs.
#
# Скрипт по очереди запускает каждую стратегию через zapret.sh, проверяет
# доступность целей из utils/targets.txt (HTTP/1.1, TLS 1.2, TLS 1.3 + ping),
# останавливает стратегию и в конце выводит таблицу с результатами и
# лучшей стратегией.
#
# Требования:
#   * root (sudo), установленный nfqws (см. zapret.sh --install-nfqws)
#   * curl
#
# Использование:
#   sudo ./zapret-test.sh                  # проверить все стратегии
#   sudo ./zapret-test.sh general alt      # только выбранные
#   sudo ./zapret-test.sh 1 5-7            # по номерам из --list
#   ./zapret-test.sh --list                # список стратегий с номерами
#
# Переменные окружения:
#   TEST_CURL_TIMEOUT=4     таймаут одной проверки curl, сек
#   TEST_MAX_PARALLEL=8     сколько целей проверять одновременно
#   TEST_TARGETS=...        другой файл целей (формат utils/targets.txt)
#   NFQWS=/path/to/nfqws    если nfqws не в bin/nfqws
#
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)
SELF=$(readlink -f -- "$0")
ZAPRET="$SCRIPT_DIR/zapret.sh"
TARGETS_FILE="${TEST_TARGETS:-$SCRIPT_DIR/utils/targets.txt}"
RESULT_DIR="$SCRIPT_DIR/utils/test results"
UNIT_NAME="zapret-linux"

CURL_TIMEOUT="${TEST_CURL_TIMEOUT:-4}"
CONNECT_TIMEOUT="${TEST_CONNECT_TIMEOUT:-2}"
PARALLEL="${TEST_MAX_PARALLEL:-$(($(nproc 2>/dev/null || echo 2) * 2))}"
[[ "$PARALLEL" =~ ^[0-9]+$ ]] || PARALLEL=8
[ "$PARALLEL" -gt 16 ] && PARALLEL=16
[ "$PARALLEL" -lt 1 ] && PARALLEL=1
[[ "$CURL_TIMEOUT" =~ ^[0-9]+$ ]] || CURL_TIMEOUT=4
[[ "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] || CONNECT_TIMEOUT=2

PIDFILE="${ZAPRET_PIDFILE:-/run/zapret-linux.pid}"
STATEFILE="${ZAPRET_STATEFILE:-/run/zapret-linux.state}"

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Режим одного обработчика: печатает строку результата для одной цели.
# Вызывается самим скриптом в фоне, root не нужен.
# ---------------------------------------------------------------------------
curl_check() {
    local url="$1" timeout="$2" connect="$3"
    shift 3
    local err rc
    err=$(mktemp) || { printf 'ERROR'; return; }
    LC_ALL=C curl -I -sS -m "$timeout" --connect-timeout "$connect" \
        -o /dev/null -w '%{http_code}' "$@" "$url" 2>"$err" >/dev/null
    rc=$?

    if grep -qiE 'Could not resolve host|certificate|SSL|self[- ]?signed|unable to get local issuer' "$err"; then
        printf 'SSL'
    elif grep -qiE 'not supported|unsupported|unknown option|unrecognized option|is unknown' "$err"; then
        printf 'UNSUP'
    elif [ "$rc" -eq 0 ]; then
        printf 'OK'
    else
        printf 'ERROR'
    fi
    rm -f "$err"
}

ping_check() {
    local host="$1" out t
    command -v ping >/dev/null 2>&1 || { printf 'n/a'; return; }
    if out=$(LC_ALL=C ping -c 1 -W 1 -n "$host" 2>/dev/null); then
        t=$(printf '%s\n' "$out" | sed -n 's/.*time=\([0-9.]*\) *ms.*/\1/p' | head -n1)
        if [ -n "$t" ]; then
            printf '%.0f ms' "$t"
        else
            printf 'OK'
        fi
    else
        printf 'Timeout'
    fi
}

worker() {
    local name="$1" value="$2" timeout="$3" connect="$4"
    local url="" host="" http="n/a" tls12="n/a" tls13="n/a" ping="n/a"

    case "$value" in
        PING:*)
            host="${value#PING:}"
            host="${host//[[:space:]]/}"
            ;;
        *)
            url="$value"
            host=$(printf '%s' "$url" | sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://##; s#/.*$##; s#:[0-9]+$##')
            http=$(curl_check "$url" "$timeout" "$connect" --http1.1)
            case "$url" in
                https://*|HTTPS://*)
                    tls12=$(curl_check "$url" "$timeout" "$connect" --tlsv1.2 --tls-max 1.2)
                    tls13=$(curl_check "$url" "$timeout" "$connect" --tlsv1.3 --tls-max 1.3)
                    ;;
            esac
            ;;
    esac

    [ -n "$host" ] && ping=$(ping_check "$host")
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$http" "$tls12" "$tls13" "$ping"
}

if [ "${1:-}" = "--worker" ]; then
    worker "${2:-}" "${3:-}" "${4:-$CURL_TIMEOUT}" "${5:-$CONNECT_TIMEOUT}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Вспомогательные функции
# ---------------------------------------------------------------------------
all_strategies() {
    "$ZAPRET" --list | sed -n 's/^  \([a-z0-9-][a-z0-9-]*\)[[:space:]].*/\1/p'
}

show_list() {
    local i=0 s
    while IFS= read -r s; do
        i=$((i + 1))
        printf '  %2d  %s\n' "$i" "$s"
    done < <(all_strategies)
}

read_targets() {
    local line
    [ -f "$TARGETS_FILE" ] || die "нет файла целей $TARGETS_FILE"
    T_NAMES=()
    T_VALUES=()
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in ''|'#'*) continue ;; esac
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
            T_NAMES+=("${BASH_REMATCH[1]}")
            T_VALUES+=("${BASH_REMATCH[2]}")
        fi
    done <"$TARGETS_FILE"
    [ "${#T_NAMES[@]}" -gt 0 ] || die "в $TARGETS_FILE нет целей"
}

# ---------------------------------------------------------------------------
# Восстановление состояния до теста
# ---------------------------------------------------------------------------
SYSTEMD_PREV=0
PREV_STRATEGY=""
CLEANED=0
TMPDIR_TEST=""

cleanup() {
    local j
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    trap - EXIT INT TERM

    for j in $(jobs -p 2>/dev/null); do
        kill "$j" 2>/dev/null || true
    done
    wait 2>/dev/null || true

    "$ZAPRET" stop >/dev/null 2>&1 || true

    if [ "$SYSTEMD_PREV" -eq 1 ]; then
        systemctl start "$UNIT_NAME.service" 2>/dev/null &&
            say "Предыдущий запуск восстановлен (systemd $UNIT_NAME.service)"
    elif [ -n "$PREV_STRATEGY" ]; then
        if "$ZAPRET" start "$PREV_STRATEGY" >/dev/null 2>&1; then
            say "Предыдущая стратегия восстановлена: $PREV_STRATEGY"
        else
            warn "не удалось восстановить стратегию $PREV_STRATEGY"
        fi
    fi

    [ -n "$TMPDIR_TEST" ] && rm -rf "$TMPDIR_TEST"
}

remember_previous() {
    local pid=""
    if command -v systemctl >/dev/null 2>&1 &&
       systemctl is-active --quiet "$UNIT_NAME.service" 2>/dev/null; then
        SYSTEMD_PREV=1
        say "Останавливаю systemd-службу $UNIT_NAME.service на время тестов..."
        systemctl stop "$UNIT_NAME.service" 2>/dev/null || true
        return
    fi

    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE" 2>/dev/null || true)
        case "$pid" in ''|*[!0-9]*) pid="" ;; esac
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            PREV_STRATEGY=$(cat "$STATEFILE" 2>/dev/null || echo "general")
            say "Останавливаю запущенную стратегию $PREV_STRATEGY на время тестов..."
        fi
    fi
    "$ZAPRET" stop >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Основной сценарий
# ---------------------------------------------------------------------------
main() {
    [ "$(id -u)" -eq 0 ] || die "нужны права root: sudo $0 $*"
    command -v curl >/dev/null 2>&1 || die "нужен curl"
    [ -x "$ZAPRET" ] || die "не найден $ZAPRET"

    read_targets

    local all=() selected=() arg n i s
    mapfile -t all < <(all_strategies)
    [ "${#all[@]}" -gt 0 ] || die "zapret.sh --list не вернул стратегии"

    if [ "$#" -eq 0 ] || [ "${1:-}" = "all" ]; then
        selected=("${all[@]}")
    else
        for arg in "$@"; do
            case "$arg" in
                all) selected+=("${all[@]}") ;;
                [0-9]*-[0-9]*)
                    local lo="${arg%-*}" hi="${arg#*-}" k
                    if [ "$lo" -ge 1 ] && [ "$hi" -le "${#all[@]}" ] && [ "$lo" -le "$hi" ]; then
                        for ((k = lo; k <= hi; k++)); do
                            selected+=("${all[$((k - 1))]}")
                        done
                    else
                        warn "диапазон $arg вне 1-${#all[@]}"
                    fi
                    ;;
                *[!0-9]*)
                    local found=0
                    for s in "${all[@]}"; do
                        [ "$s" = "$arg" ] && { selected+=("$s"); found=1; break; }
                    done
                    [ "$found" -eq 1 ] || warn "неизвестная стратегия '$arg'"
                    ;;
                *)
                    n=$arg
                    if [ "$n" -ge 1 ] && [ "$n" -le "${#all[@]}" ]; then
                        selected+=("${all[$((n - 1))]}")
                    else
                        warn "номер $n вне диапазона 1-${#all[@]}"
                    fi
                    ;;
            esac
        done
        # убрать неизвестные/дубликаты с сохранением порядка
        local dedup=()
        for arg in "${selected[@]}"; do
            [ -n "$arg" ] || continue
            case " ${dedup[*]-} " in *" $arg "*) continue ;; esac
            dedup+=("$arg")
        done
        selected=("${dedup[@]}")
        [ "${#selected[@]}" -gt 0 ] || die "не выбрано ни одной стратегии. Список: $0 --list"
    fi

    mkdir -p "$RESULT_DIR"
    RESULT_FILE="$RESULT_DIR/test_results_$(date +%Y-%m-%d_%H-%M-%S).txt"
    : >"$RESULT_FILE"

    remember_previous
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    log ""
    log "============================================================"
    log "                 ZAPRET CONFIG TESTS"
    log "                 Mode: STANDARD"
    log "                 Total configs: ${#selected[@]}"
    log "                 Targets: ${#T_NAMES[@]}"
    log "============================================================"
    log "Тесты могут занять несколько минут..."
    log ""

    declare -A A_OK=() A_ERR=() A_UNSUP=() A_PINGOK=() A_PINGFAIL=()
    local order=()
    local idx=0 strat failed=0
    local tmp
    tmp=$(mktemp -d)
    TMPDIR_TEST="$tmp"

    for strat in "${selected[@]}"; do
        idx=$((idx + 1))
        say ""
        say "------------------------------------------------------------"
        say "  [$idx/${#selected[@]}] $strat"
        say "------------------------------------------------------------"
        log "Config: $strat"

        say "  > запуск..."
        if ! "$ZAPRET" start "$strat" >"$tmp/start.log" 2>&1; then
            warn "стратегия $strat не запустилась, пропуск"
            log "  > strategy failed to start, skipped"
            if [ -s "$tmp/start.log" ]; then
                local msg
                msg=$(tail -n 12 "$tmp/start.log" | sed 's/^/    /')
                printf '%s\n' "$msg"
                log "$msg"
            fi
            failed=$((failed + 1))
            continue
        fi
        sleep 0.5

        say "  > проверка ${#T_NAMES[@]} целей..."
        local j=0
        rm -f "$tmp"/target.*
        for j in "${!T_NAMES[@]}"; do
            "$SELF" --worker "${T_NAMES[$j]}" "${T_VALUES[$j]}" \
                "$CURL_TIMEOUT" "$CONNECT_TIMEOUT" >"$tmp/target.$j" 2>/dev/null &
            while [ "$(jobs -pr | wc -l)" -ge "$PARALLEL" ]; do
                sleep 0.1
            done
        done
        wait

        local ok=0 err=0 unsup=0 pingok=0 pingfail=0
        local name http tls12 tls13 ping tok
        for j in "${!T_NAMES[@]}"; do
            if [ -s "$tmp/target.$j" ]; then
                IFS=$'\t' read -r name http tls12 tls13 ping <"$tmp/target.$j"
            else
                name="${T_NAMES[$j]}"; http="ERROR"; tls12="ERROR"; tls13="ERROR"; ping="Timeout"
            fi
            for tok in "$http" "$tls12" "$tls13"; do
                case "$tok" in
                    OK) ok=$((ok + 1)) ;;
                    SSL|ERROR) err=$((err + 1)) ;;
                    UNSUP) unsup=$((unsup + 1)) ;;
                esac
            done
            case "$ping" in
                Timeout|n/a|'') pingfail=$((pingfail + 1)) ;;
                *) pingok=$((pingok + 1)) ;;
            esac

            log "$(printf '  %-20s HTTP:%-5s TLS1.2:%-5s TLS1.3:%-5s | Ping: %s' \
                "$name" "$http" "$tls12" "$tls13" "$ping")"
        done

        A_OK[$strat]=$ok
        A_ERR[$strat]=$err
        A_UNSUP[$strat]=$unsup
        A_PINGOK[$strat]=$pingok
        A_PINGFAIL[$strat]=$pingfail
        order+=("$strat")

        "$ZAPRET" stop >/dev/null 2>&1 || true
    done

    # ------------------------------------------------------------------
    # Аналитика
    # ------------------------------------------------------------------
    local best="" maxscore=-1 maxping=-1 key score pscore
    log ""
    log "=== ANALYTICS ==="

    for key in "${order[@]}"; do
        log "$(printf '%-18s : HTTP OK: %3d, ERR: %3d, UNSUP: %3d, Ping OK: %3d, Fail: %3d' \
            "$key" "${A_OK[$key]}" "${A_ERR[$key]}" "${A_UNSUP[$key]}" \
            "${A_PINGOK[$key]}" "${A_PINGFAIL[$key]}")"

        score=${A_OK[$key]}
        pscore=${A_PINGOK[$key]}
        if [ "$score" -gt "$maxscore" ] ||
           { [ "$score" -eq "$maxscore" ] && [ "$pscore" -gt "$maxping" ]; }; then
            maxscore=$score
            maxping=$pscore
            best=$key
        fi
    done

    log ""
    if [ -n "$best" ]; then
        log "Лучшая стратегия: $best"
    else
        log "Ни одна стратегия не запустилась"
    fi
    [ "$failed" -gt 0 ] && warn "не запустилось стратегий: $failed"
    if [ -z "$best" ]; then
        log ""
        log "Подсказка: проверьте окружение командой:"
        log "  sudo $ZAPRET check general"
        log "и посмотрите лог nfqws: /var/log/zapret-linux.log"
    fi
    log ""
    log "Результаты сохранены: $RESULT_FILE"

    [ -n "$best" ] || exit 1
}

# log() используется после инициализации RESULT_FILE
log() {
    [ -n "${RESULT_FILE:-}" ] || { printf '%s\n' "$*"; return; }
    printf '%s\n' "$*" | tee -a "$RESULT_FILE"
}

usage() {
    awk 'NR > 1 { if ($0 == "set -u") exit; sub(/^# ?/, ""); print }' "$0"
}

case "${1:-}" in
    --list|-l)
        say "Стратегии (номер для zapret-test.sh):"
        show_list
        exit 0
        ;;
    --help|-h|help)
        usage
        exit 0
        ;;
esac

main "$@"
