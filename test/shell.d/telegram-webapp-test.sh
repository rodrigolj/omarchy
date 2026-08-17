#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1786881090.sh"

require_command desktop-file-validate
require_command python3

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/home"
cat >"$test_tmp/bin/omarchy-mise-install" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$test_tmp/bin/update-desktop-database" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >>"$OMARCHY_TEST_LOG"
SH
chmod +x "$test_tmp/bin/omarchy-mise-install" "$test_tmp/bin/update-desktop-database"

export PATH="$test_tmp/bin:$ROOT/bin:$PATH"
export HOME="$test_tmp/home"
export OMARCHY_TEST_LOG="$test_tmp/refresh.log"
export OMARCHY_PATH="$ROOT"

bash -euo pipefail "$migration" >/dev/null
installed_desktop="$HOME/.local/share/applications/Telegram.desktop"
desktop-file-validate "$installed_desktop"
python3 - "$installed_desktop" <<'PY'
import configparser
import sys

desktop = configparser.ConfigParser(interpolation=None, strict=True)
desktop.optionxform = str
with open(sys.argv[1], encoding="utf-8") as launcher:
    desktop.read_file(launcher)

entry = desktop["Desktop Entry"]
expected = {
    "Name": "Telegram",
    "Exec": "omarchy-launch-webapp https://web.telegram.org/",
    "Icon": "telegram",
}
for field, value in expected.items():
    if entry.get(field) != value:
        raise SystemExit(f"{field}: expected {value!r}, got {entry.get(field)!r}")
PY
[[ $(<"$OMARCHY_TEST_LOG") == "$HOME/.local/share/applications" ]] ||
  fail "Telegram migration refreshes the desktop application cache"
pass "Telegram migration installs a valid frameless launcher for existing users"

export HOME="$test_tmp/opt-out-home"
mkdir -p "$HOME/.local/state/omarchy"
touch "$HOME/.local/state/omarchy/preinstalls-removed"
bash -euo pipefail "$migration" >/dev/null
[[ ! -e $HOME/.local/share/applications/Telegram.desktop ]] ||
  fail "Telegram migration preserves the preinstall opt-out"
pass "Telegram migration preserves the preinstall opt-out"
