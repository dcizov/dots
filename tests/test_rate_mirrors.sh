#!/usr/bin/env bash
# rate-mirrors.sh (`ucli mirrors`): rank each mirrorlist found (Arch, CachyOS)
# with rate-mirrors or reflector, show the result, and install it with a .bak
# — never pointing CachyOS at Arch mirrors, and writing nothing on a dry run.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

mirrors() { ( source ../private_dot_local/share/ucli/scripts/system/executable_rate-mirrors.sh "$@" ); }

# lists <repo…> — mirrorlist files in a fake /etc/pacman.d; engines write a
# ranked file naming the repo they were asked for.
lists() {
  t_minimal_path   # only the engines a test stubs: never the host's rate-mirrors
  export UCLI_MIRRORLIST_DIR="$T_ROOT/pacman.d"
  mkdir -p "$UCLI_MIRRORLIST_DIR"
  local r
  for r in "$@"; do
    case $r in
      arch) echo 'Server = https://old.example/$repo/os/$arch' >"$UCLI_MIRRORLIST_DIR/mirrorlist" ;;
      cachyos) echo 'Server = https://old.cachy/$arch/$repo' >"$UCLI_MIRRORLIST_DIR/cachyos-mirrorlist" ;;
    esac
  done
  stub sudo '"$@"'
  stub curl 'exit 1'
}
rate_mirrors_tool() {
  stub rate-mirrors 'for a; do [[ $prev == --save ]] && out=$a; prev=$a; done
    printf "Server = https://fast.%s/x\nServer = https://second.%s/x\n" "${@: -1}" "${@: -1}" >"$out"'
}
reflector_tool() {
  stub reflector 'for a; do [[ $prev == --save ]] && out=$a; prev=$a; done
    printf "Server = https://fast.arch/\$repo/os/\$arch\n" >"$out"'
}

test_each_list_is_ranked_and_installed_with_a_backup() {
  lists arch cachyos; rate_mirrors_tool
  t_run mirrors --yes --no-snapshot --country DE
  assert_status 0
  assert_contains "$(cat "$UCLI_MIRRORLIST_DIR/mirrorlist")" "https://fast.arch/x"
  assert_contains "$(cat "$UCLI_MIRRORLIST_DIR/cachyos-mirrorlist")" "https://fast.cachyos/x"
  assert_contains "$(cat "$UCLI_MIRRORLIST_DIR/mirrorlist.bak")" "old.example"
  assert_called "--entry-country=DE"
}

test_reflector_never_writes_arch_mirrors_into_the_cachyos_list() {
  lists arch cachyos; reflector_tool
  t_run mirrors --yes --no-snapshot --no-geo --tool reflector
  assert_status 1
  assert_contains "$(cat "$UCLI_MIRRORLIST_DIR/mirrorlist")" "fast.arch"
  assert_eq 'Server = https://old.cachy/$arch/$repo' "$(cat "$UCLI_MIRRORLIST_DIR/cachyos-mirrorlist")"
  assert_contains "$T_OUT" "reflector cannot rank cachyos mirrors"
  assert_contains "$T_PLAIN" "Failed: cachyos"
}

test_a_dry_run_ranks_but_writes_and_snapshots_nothing() {
  lists arch; rate_mirrors_tool
  S="$(t_deployed system/rate-mirrors)"
  t_fake_script "${S%/*}/snapshot-fresh-install.sh"
  t_run bash "$S" --dry-run --no-geo
  assert_status 0
  assert_contains "$T_PLAIN" "Dry run: 1 mirrorlist(s) ranked, nothing written."
  assert_not_called "snapshot-fresh-install.sh"
  assert_contains "$(cat "$UCLI_MIRRORLIST_DIR/mirrorlist")" "old.example"
}

test_a_failed_ranking_leaves_the_files_alone() {
  lists arch; stub rate-mirrors 'exit 1'
  t_run mirrors --yes --no-snapshot --no-geo
  assert_status 1
  assert_contains "$T_PLAIN" "no mirrorlist was produced; the existing files are untouched"
  assert_contains "$(cat "$UCLI_MIRRORLIST_DIR/mirrorlist")" "old.example"
}

test_validation() {
  lists arch; rate_mirrors_tool
  t_run mirrors --protocol ftp
  assert_status 2
  t_run mirrors --max-mirrors many
  assert_status 2
  t_run mirrors --repos arch,debian
  assert_status 2
  assert_contains "$T_OUT" "unknown repo: debian"
  t_run mirrors --country
  assert_status 2
  assert_contains "$T_OUT" "--country needs a value"
  t_run mirrors --tool
  assert_contains "$T_OUT" "--tool needs a value"
  export UCLI_MIRRORLIST_DIR="$T_ROOT/empty"
  t_run mirrors
  assert_status 1
  assert_contains "$T_OUT" "no mirrorlist found"
}

t_main
