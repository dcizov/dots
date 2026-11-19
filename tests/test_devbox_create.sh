#!/usr/bin/env bash
# devbox-create.sh: a throwaway distrobox from a stock image — the image table,
# argument validation, and create-or-enter by container name.
. "$(dirname -- "${BASH_SOURCE[0]}")/harness.sh"

create() { ( source ../private_dot_local/share/ucli/scripts/devbox/executable_devbox-create.sh "$@" ); }

# distrobox list output: a header row, then "ID | NAME | STATUS | IMAGE".
boxes() {
  stub distrobox "if [[ \$1 == list ]]; then
    echo 'ID           | NAME   | STATUS | IMAGE'
    for n in $*; do echo \"abc123       | \$n | Up     | img\"; done
  fi"
}

test_list_shows_every_image() {
  t_run create --list
  assert_status 0
  assert_contains "$T_OUT" "ubuntu  docker.io/library/ubuntu:24.04"
  assert_contains "$T_OUT" "wolfi   cgr.dev/chainguard/wolfi-base:latest"
  assert_contains "$T_OUT" "alpine  docker.io/library/alpine:latest"
}

test_help_is_the_header_comment() {
  t_run create --help
  assert_status 0
  assert_contains "$T_OUT" "Usage: devbox-create.sh [ubuntu|fedora|wolfi|debian|arch|alpine] [NAME]"
}

test_an_unknown_distro_is_rejected_before_distrobox_runs() {
  boxes
  t_run create gentoo
  assert_status 2
  assert_contains "$T_OUT" "unsupported distro: gentoo (try --list)"
  assert_not_called "distrobox"
}

test_without_distrobox_it_says_how_to_get_it() {
  t_minimal_path
  t_run create fedora
  assert_status 1
  assert_contains "$T_OUT" "distrobox is not installed (run: ucli devmode)"
}

test_a_new_box_is_created_from_the_distro_image() {
  boxes dev
  t_run create fedora
  assert_status 0
  assert_called "distrobox create --name fedora --image docker.io/library/fedora:latest --yes"
  assert_contains "$T_OUT" "Enter it with:  distrobox enter fedora"
}

test_a_custom_name_is_used() {
  boxes
  t_run create arch scratch
  assert_called "distrobox create --name scratch --image docker.io/library/archlinux:latest --yes"
}

test_an_existing_box_is_entered_not_recreated() {
  boxes dev ubuntu
  t_run create ubuntu
  assert_status 0
  assert_contains "$T_OUT" "container 'ubuntu' already exists"
  assert_not_called "distrobox create"
}

test_a_name_that_only_contains_another_is_not_a_match() {
  boxes ubuntu-old
  t_run create ubuntu
  assert_called "distrobox create --name ubuntu"
}

t_main
