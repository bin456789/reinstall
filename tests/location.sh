#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154 # Variables shared with the extracted function.
set -e

cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LOCATION_TEST_CALLS="$tmp/calls"
export PATH="$tmp:$PATH"

# Load only the location check, never the installer entry point.
eval "$(sed -n '/^is_in_china() {$/,/^}$/p' reinstall.sh)"
is_have_cmd() { command -v "$1" >/dev/null; }
install_pkg() { return 99; }
warn() { echo "$*" >&2; }
curl() { return 99; } # The check must bypass the insecure wrapper.

cat >"$tmp/curl" <<'EOF'
#!/usr/bin/env bash
set -e
[[ "$*" == '-q -fsS --connect-timeout 10 --max-time 20 https://www.cloudflare-cn.com/cdn-cgi/trace' ]]
echo called >>"$LOCATION_TEST_CALLS"
printf '%s\n' "$LOCATION_TEST_TRACE"
exit "$LOCATION_TEST_STATUS"
EOF
chmod +x "$tmp/curl"
export LOCATION_TEST_TRACE LOCATION_TEST_STATUS

check() {
    local expected=$1 result=0
    LOCATION_TEST_TRACE=$2
    LOCATION_TEST_STATUS=${3:-0}
    unset _loc force_cn
    : >"$LOCATION_TEST_CALLS"
    is_in_china 2>"$tmp/log" || result=$?
    [ "$result" -eq "$expected" ] || { cat "$tmp/log" >&2; return 1; }
    [ "$(wc -l <"$LOCATION_TEST_CALLS")" -eq 1 ]
}

check 0 $'colo=XXX\nloc=CN'
check 1 $'colo=XXX\nloc=US'
for trace in '' 'loc=' 'loc=cn' 'loc=CHN' 'loc=CN=extra' 'prefixloc=CN' $'loc=CN\nloc=US'; do
    check 1 "$trace"
    [ "$_loc" = unknown ]
    grep -q -- '--force-cn' "$tmp/log"
done
# A partial response from a failed transfer must not select China mirrors.
for status in 22 28 60; do
    check 1 'loc=CN' "$status"
    [ "$_loc" = unknown ]
done

# Cache failures as well as successes so later callers do not retry the lookup.
is_in_china 2>/dev/null && exit 1
[ "$(wc -l <"$LOCATION_TEST_CALLS")" -eq 1 ]
check 0 'loc=CN'
is_in_china
[ "$(wc -l <"$LOCATION_TEST_CALLS")" -eq 1 ]

unset _loc
force_cn=1
: >"$LOCATION_TEST_CALLS"
is_in_china
[ ! -s "$LOCATION_TEST_CALLS" ]
echo 'Location checks passed.'
