#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

desktop="$ROOT/applications/Telegram.desktop"
migration="$ROOT/migrations/1786881090.sh"

[[ -f $desktop ]] || fail "Telegram ships a desktop launcher"
grep -Fx 'Name=Telegram' "$desktop" >/dev/null || fail "Telegram launcher uses the product name"
grep -Fx 'Exec=omarchy-launch-webapp https://web.telegram.org/' "$desktop" >/dev/null ||
  fail "Telegram launcher uses the canonical web app entry point"
grep -Fx 'Icon=telegram' "$desktop" >/dev/null || fail "Telegram launcher uses its packaged icon"
[[ -s $ROOT/applications/icons/Telegram.png ]] || fail "Telegram ships its launcher icon"
pass "Telegram ships as a frameless default web app"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/home"
cat >"$test_tmp/bin/omarchy-refresh-applications" <<'SH'
#!/bin/bash
printf 'refresh\n' >>"$OMARCHY_TEST_LOG"
SH
chmod +x "$test_tmp/bin/omarchy-refresh-applications"

export PATH="$test_tmp/bin:$PATH"
export HOME="$test_tmp/home"
export OMARCHY_TEST_LOG="$test_tmp/refresh.log"

bash -euo pipefail "$migration" >/dev/null
[[ $(<"$OMARCHY_TEST_LOG") == "refresh" ]] || fail "Telegram migration installs default launchers"
pass "Telegram migration installs the launcher for existing users"

mkdir -p "$HOME/.local/state/omarchy"
touch "$HOME/.local/state/omarchy/preinstalls-removed"
: >"$OMARCHY_TEST_LOG"
bash -euo pipefail "$migration" >/dev/null
[[ ! -s $OMARCHY_TEST_LOG ]] || fail "Telegram migration preserves the preinstall opt-out"
pass "Telegram migration preserves the preinstall opt-out"
