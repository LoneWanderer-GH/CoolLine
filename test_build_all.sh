#!/usr/bin/env bash
set -euo pipefail

addon_dir_path="Interface/AddOns/"
# ./packager/release.sh -r ${WOW_ROOT}/__classic_era__/Interface\AddOns/CoolLine -e -g classic -d -l -z
# ./packager/release.sh -r ${WOW_ROOT}/__classic__/Interface/AddOns/CoolLine     -e -g bcc     -d -l -z
# ./packager/release.sh -r ${WOW_ROOT}/__retail__/Interface/AddOns/CoolLine      -e -g retail  -d -l -z

if [[ -z "${WOW_ROOT_LINUX:-}" ]]; then
	printf 'Set WOW_ROOT_LINUX to the directory containing _classic_era_, _classic_, and _retail_.\n' >&2
	exit 2
fi

if [[ ! -x ./packager/release.sh ]]; then
	printf 'Missing packager/release.sh. Initialize the packager submodule first.\n' >&2
	exit 2
fi

if ! command -v svn >/dev/null 2>&1; then
	printf 'Subversion is required to fetch the libraries in .pkgmeta (install it with: sudo apt install subversion).\n' >&2
	exit 2
fi

installed_clients=0

build_if_installed() {
	local game_dir="$1"
	local flavor="$2"
	local addon_path="${WOW_ROOT_LINUX}/${game_dir}/${addon_dir_path}"

	if [[ ! -d "$addon_path" ]]; then
		printf 'Skipping %s; no AddOns directory at %s\n' "$flavor" "$addon_path"
		return
	fi

	./packager/release.sh -r "$addon_path" -g "$flavor" -d -l -z
	installed_clients=$((installed_clients + 1))
}

build_if_installed _classic_era_ classic
build_if_installed _classic_ bcc
build_if_installed _retail_ retail

if [[ "$installed_clients" -eq 0 ]]; then
	printf 'No supported WoW client was found under %s.\n' "$WOW_ROOT_LINUX" >&2
	exit 2
fi
