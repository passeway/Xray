#!/usr/bin/env bash
# Compatibility entry point: share the manager's installation logic.
main() (
    [ "$(id -u)" = 0 ] || { echo '请使用 root 运行' >&2; return 1; }
    local directory temporary
    directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || return 1
    if [ -f "$directory/Xray.sh" ]; then
        bash "$directory/Xray.sh" --install
        return $?
    fi
    temporary=$(mktemp -d) || return 1
    trap 'rm -rf -- "$temporary"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    curl -fLsS --retry 2 --connect-timeout 8 --max-time 60 \
        https://raw.githubusercontent.com/passeway/Xray/main/Xray.sh \
        -o "$temporary/Xray.sh" || return 1
    bash -n "$temporary/Xray.sh" && bash "$temporary/Xray.sh" --install
)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
