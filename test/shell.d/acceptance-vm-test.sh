#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

iso_repo="$test_tmp/omarchy-iso"
stub_bin="$test_tmp/bin"
log="$test_tmp/harness.log"
mkdir -p "$iso_repo/bin" "$iso_repo/release" "$iso_repo/test-runs/existing" "$stub_bin" "$test_tmp/firmware" "$test_tmp/tessdata"
printf 'do not touch\n' >"$iso_repo/test-runs/existing/base.qcow2"
printf 'test iso input\n' >"$iso_repo/release/omarchy-test.iso"
touch "$test_tmp/firmware/code.fd" "$test_tmp/firmware/vars.fd" "$test_tmp/tessdata/eng.traineddata" "$test_tmp/kvm"

cat >"$iso_repo/bin/omarchy-iso-test" <<'SH'
#!/bin/bash
printf 'arg=%s\n' "$@" >"$OMARCHY_VM_TEST_LOG"
SH
chmod +x "$iso_repo/bin/omarchy-iso-test"

cat >"$iso_repo/bin/omarchy-iso-make" <<'SH'
#!/bin/bash
printf 'arg=%s\n' "$@" >"$OMARCHY_VM_MAKE_LOG"
printf 'locally built iso\n' >"$(cd -- "$(dirname -- "$0")/.." && pwd)/release/omarchy-local.iso"
SH
chmod +x "$iso_repo/bin/omarchy-iso-make"

for command in qemu-system-x86_64 qemu-img socat magick tesseract ssh docker; do
  cat >"$stub_bin/$command" <<'SH'
#!/bin/bash
exit 0
SH
  chmod +x "$stub_bin/$command"
done
cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
[[ $1 == "-Q" ]]
SH
chmod +x "$stub_bin/pacman"

run_vm() {
  local harness_log="$1"
  shift

  PATH="$stub_bin:$PATH" \
    OMARCHY_VM_OVMF_CODE="$test_tmp/firmware/code.fd" \
    OMARCHY_VM_OVMF_VARS_TEMPLATE="$test_tmp/firmware/vars.fd" \
    OMARCHY_VM_TESSDATA_ENG="$test_tmp/tessdata/eng.traineddata" \
    OMARCHY_VM_KVM_PATH="$test_tmp/kvm" \
    OMARCHY_VM_TEST_LOG="$harness_log" \
    OMARCHY_VM_MAKE_LOG="${OMARCHY_VM_MAKE_LOG:-}" \
    "$ROOT/test/acceptance-vm" "$@"
}

run_vm "$log" \
  --iso-repo "$iso_repo" \
  --iso "$iso_repo/release/omarchy-test.iso" \
  --port 2299 >/dev/null

[[ -f $log ]] || fail "VM validation accepts an isolated KVM preflight path"
iso_sha256=$(sha256sum "$iso_repo/release/omarchy-test.iso" | awk '{print $1}')
base_name="vm-validation-${iso_sha256:0:16}"
managed_iso="$iso_repo/test-runs/vm-validation-inputs/$base_name.iso"
[[ -f $managed_iso ]] || fail "VM validation keeps a content-addressed ISO input"
grep -Fxq 'do not touch' "$iso_repo/test-runs/existing/base.qcow2" ||
  fail "VM validation leaves unrelated VM state untouched"
grep -Fxq "arg=$managed_iso" "$log" || fail "VM validation delegates its managed ISO"
grep -Fxq 'arg=--reuse-base' "$log" || fail "VM validation reuses only its validation base"
grep -Fxq 'arg=--sync-omarchy' "$log" || fail "VM validation uses the harness acceptance sync"
grep -Fxq "arg=$ROOT" "$log" || fail "VM validation syncs the current acceptance suite"
grep -Fxq 'arg=2299' "$log" || fail "VM validation delegates the selected SSH port"
grep -Fxq 'arg=--no-preview' "$log" || fail "VM validation stays noninteractive"
pass "VM validation safely delegates to the ISO harness"

mkdir -p "$iso_repo/test-runs/$base_name/runs/interrupted"
printf '%s\n' "$$" >"$iso_repo/test-runs/$base_name/runs/interrupted/qemu.pid"
if run_vm "$test_tmp/should-not-run.log" \
  --iso-repo "$iso_repo" \
  --iso "$iso_repo/release/omarchy-test.iso" >"$test_tmp/already-running.out" 2>&1; then
  fail "VM validation refuses a live VM in its namespace"
fi
[[ ! -e $test_tmp/should-not-run.log ]] || fail "VM validation leaves the live VM harness alone"
grep -Fq 'it was not stopped or reused' "$test_tmp/already-running.out" ||
  fail "VM validation explains that the live VM was left alone"
pass "VM validation refuses to target a live VM"

mkdir -p "$test_tmp/omarchy-pkgs"
OMARCHY_VM_MAKE_LOG="$test_tmp/make.log" \
  run_vm "$test_tmp/build-harness.log" \
    --iso-repo "$iso_repo" \
    --build "$test_tmp/omarchy-pkgs" >/dev/null

grep -Fxq 'arg=--keep-pkg-cache' "$test_tmp/make.log" || fail "VM build preserves the host package cache"
grep -Fxq 'arg=--local-source' "$test_tmp/make.log" || fail "VM build uses local source"
grep -Fxq "arg=$ROOT" "$test_tmp/make.log" || fail "VM build installs the current checkout"
grep -Fxq "arg=$test_tmp/omarchy-pkgs" "$test_tmp/make.log" || fail "VM build uses the package checkout"
[[ -f $test_tmp/build-harness.log ]] || fail "VM build delegates its ISO to the harness"
pass "VM validation delegates local-source ISO builds"
