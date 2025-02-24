#!/usr/bin/env bash

# This file needs to exist otherwise running this in a RUN label makes it so bash strict mode doesnt work.
# Thus leading to silent failures

set -euo pipefail

# Do not rely on any of these scripts existing in a specific path
# Make the names as descriptive as possible and everything that uses dnf for package installation/removal should have `packages-` as a prefix.

run_buildscripts_for() {
	WHAT=$1
	shift
	# Complex "find" expression here since there might not be any overrides
	find "/var/tmp/build_scripts/overrides/$WHAT" -iname "*-*.sh" -type f -maxdepth 1 -print0 | while IFS= read -r -d $'\0' script; do
		printf "::group:: ===$WHAT-%s===\n" "$(basename "$script")"
		$script
		printf "::endgroup::\n"
	done
}

copy_systemfiles_for() {
	WHAT=$1
	shift
	printf "::group:: ===%s-file-copying===\n" "$WHAT"
	cp -avf "/var/tmp/system_files_overrides/$WHAT/." /
	printf "::endgroup::\n"
}

MAJOR_VERSION_NUMBER="$(sh -c '. /usr/lib/os-release ; echo $VERSION_ID')"
SCRIPTS_PATH="$(realpath "$(dirname "$0")/scripts")"
export SCRIPTS_PATH
export MAJOR_VERSION_NUMBER

for script in /var/tmp/build_scripts/*-*.sh; do
	printf "::group:: ===%s===\n" "$(basename "$script")"
	$script
	printf "::endgroup::\n"
done

copy_systemfiles_for "$(arch)"
run_buildscripts_for "$(arch)"

if [ "$ENABLE_DX" == "1" ]; then
	copy_systemfiles_for dx
	run_buildscripts_for dx
	copy_systemfiles_for "$(arch)-dx"
	run_buildscripts_for "$(arch)/dx"
fi

if [ "$ENABLE_GDX" == "1" ]; then
	copy_systemfiles_for gdx
	run_buildscripts_for gdx
	copy_systemfiles_for "$(arch)-gdx"
	run_buildscripts_for "$(arch)/gdx"
fi

if [ "$ENABLE_HWE" == "1" ]; then
	copy_systemfiles_for hwe
	run_buildscripts_for hwe
	copy_systemfiles_for "$(arch)-hwe"
	run_buildscripts_for "$(arch)/hwe"
fi

printf "::group:: ===Image Cleanup===\n"
# Ensure these get run at the _end_ of the build no matter what
/var/tmp/build_scripts/cleanup.sh
printf "::endgroup::\n"
