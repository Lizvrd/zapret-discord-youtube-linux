#!/usr/bin/env bash
# zapret-strategy: alt5
# source: general (ALT5).bat
#
# Стратегия "alt5" (Linux-порт general (ALT5).bat).
#
#   sudo ./alt5.sh            запустить в фоне
#   ./alt5.sh --dry-run       проверить параметры без запуска
#   sudo ./alt5.sh run        в переднем плане, Ctrl+C для остановки
#
set -u

. "$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)/lib/zapret-lib.sh"

STRATEGY_NAME="alt5"
NFQWS_ARGS=(
    "--filter-udp=443"
    "--hostlist=${LISTS}list-general.txt"
    "--hostlist=${LISTS}list-general-user.txt"
    "--hostlist-exclude=${LISTS}list-exclude.txt"
    "--hostlist-exclude=${LISTS}list-exclude-user.txt"
    "--ipset-exclude=${LISTS}ipset-exclude.txt"
    "--ipset-exclude=${LISTS}ipset-exclude-user.txt"
    "--dpi-desync=fake"
    "--dpi-desync-repeats=6"
    "--dpi-desync-fake-quic=${BIN}quic_initial_www_google_com.bin"
    "--new"
    "--filter-udp=19294-19344,50000-50100"
    "--filter-l7=discord,stun"
    "--dpi-desync=fake"
    "--dpi-desync-fake-discord=${BIN}ACTIVE_DISCORD_UDP.bin"
    "--dpi-desync-fake-stun=${BIN}ACTIVE_DISCORD_UDP.bin"
    "--dpi-desync-repeats=6"
    "--new"
    "--filter-l3=ipv4"
    "--filter-tcp=80,443,2053,2083,2087,2096,8443"
    "--ipset-exclude=${LISTS}ipset-exclude.txt"
    "--ipset-exclude=${LISTS}ipset-exclude-user.txt"
    "--dpi-desync=syndata,multidisorder"
    "--new"
    "--filter-tcp=${GAME_FILTER_TCP}"
    "--ipset=${LISTS}ipset-all.txt"
    "--ipset-exclude=${LISTS}ipset-exclude.txt"
    "--ipset-exclude=${LISTS}ipset-exclude-user.txt"
    "--dpi-desync=syndata,multidisorder"
    "--dpi-desync-any-protocol=1"
    "--dpi-desync-cutoff=n4"
    "--new"
    "--filter-udp=443"
    "--ipset=${LISTS}ipset-all.txt"
    "--hostlist-exclude=${LISTS}list-exclude.txt"
    "--hostlist-exclude=${LISTS}list-exclude-user.txt"
    "--ipset-exclude=${LISTS}ipset-exclude.txt"
    "--ipset-exclude=${LISTS}ipset-exclude-user.txt"
    "--dpi-desync=fake"
    "--dpi-desync-repeats=6"
    "--dpi-desync-fake-quic=${BIN}quic_initial_www_google_com.bin"
    "--new"
    "--filter-udp=${GAME_FILTER_UDP}"
    "--ipset=${LISTS}ipset-all.txt"
    "--ipset-exclude=${LISTS}ipset-exclude.txt"
    "--ipset-exclude=${LISTS}ipset-exclude-user.txt"
    "--dpi-desync=fake"
    "--dpi-desync-repeats=14"
    "--dpi-desync-any-protocol=1"
    "--dpi-desync-fake-unknown-udp=${BIN}ACTIVE_GAME_UDP.bin"
    "--dpi-desync-cutoff=n3"
)

strategy_cli "$@"
