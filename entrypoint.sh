#!/usr/bin/env bash
set -e

function die()
{
    echo "::error::$1"
	echo "------------------------------------------------------------------------------------------------------------------------"
    exit 1
}

[[ ${GITHUB_REF} = refs/heads/* ]] && git_branch="${GITHUB_REF##*/}"
[[ ${GITHUB_REF} = refs/tags/* ]] &&git_tag="${GITHUB_REF##*/}"

cat << END
------------------------------------------------------------------------------------------------------------------------
                            _   _                       _           _ _     _        _            _   
                           | | (_)                     | |         (_) |   | |      | |          | |  
                  __ _  ___| |_ _  ___  _ __ ______ ___| |__  _   _ _| | __| |______| |_ ___  ___| |_ 
                 / _\` |/ __| __| |/ _ \| '_ \______/ _ \ '_ \| | | | | |/ _\` |______| __/ _ \/ __| __|
                | (_| | (__| |_| | (_) | | | |    |  __/ |_) | |_| | | | (_| |      | ||  __/\__ \ |_ 
                 \__,_|\___|\__|_|\___/|_| |_|     \___|_.__/ \__,_|_|_|\__,_|       \__\___||___/\__|

                https://github.com/hacking-gentoo/action-ebuild-test              (c) 2019 Max Hacking 
------------------------------------------------------------------------------------------------------------------------
GITHUB_REPOSITORY=${GITHUB_REPOSITORY}
GITHUB_REF=${GITHUB_REF}
git_branch=${git_branch}
git_tag=${git_tag}
------------------------------------------------------------------------------------------------------------------------
END

# Check for a GITHUB_WORKSPACE env variable
[[ -z "${GITHUB_WORKSPACE}" ]] && die "Must set GITHUB_WORKSPACE in env"
cd "${GITHUB_WORKSPACE}" || exit 2

# If there isn't a .gentoo directory in the base of the workspace then bail
[[ -d .gentoo ]] || die "No .gentoo directory in workspace root"

# Try to find the overlays file and add any overlays it contains
if [[ -f .gentoo/overlays ]]; then
    while IFS= read -r overlay
    do
    	# shellcheck disable=SC2086
        [[ -n "${overlay}" ]] && add_overlay ${overlay}
	done < .gentoo/overlays
fi

# We will use the test-repo for the ebuild under test
repo_id="test-repo"
repo_path="/var/db/repos"

# Find the ebuild to test and strip the .gentoo/ prefix 
# e.g. dev-libs/hacking-bash-lib/hacking-bash-lib-9999.ebuild
ebuild_path=$(find .gentoo -iname '*-9999.ebuild' | head -1)
ebuild_path="${ebuild_path#*/}"
[[ -z "${ebuild_path}" ]] && die "Unable to find an ebuild to test"

# Calculate the ebuild name e.g. hacking-bash-lib-9999.ebuild
ebuild_name="${ebuild_path##*/}"
[[ -z "${ebuild_name}" ]] && die "Unable to calculate ebuild name"

# Calculate the ebuild package name e.g. hacking-bash-lib
ebuild_pkg="${ebuild_path%-*}"
ebuild_pkg="${ebuild_pkg##*/}"
[[ -z "${ebuild_pkg}" ]] && die "Unable to calculate ebuild package"

# Calculate the ebuild package category
ebuild_cat="${ebuild_path%%/*}"
[[ -z "${ebuild_cat}" ]] && die "Unable to calculate ebuild category"

# Display our findings thus far
echo "Located ebuild at ${ebuild_path}"
echo "  in category ${ebuild_cat}"
echo "    for ${ebuild_pkg}"
echo "      with name ${ebuild_name}"

# Create this package in the overlay
mkdir -p "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}" "${repo_path}/${repo_id}/metadata" "${repo_path}/${repo_id}/profiles"
echo "masters = gentoo" >> "${repo_path}/${repo_id}/metadata/layout.conf"
echo "${ebuild_cat}" >> "${repo_path}/${repo_id}/profiles/categories"
echo "${repo_id}" >> "${repo_path}/${repo_id}/profiles/repo_name"
unexpand --first-only -t 4 ".gentoo/${ebuild_path}" > "${repo_path}/${repo_id}/${ebuild_path}"
cp ".gentoo/${ebuild_cat}/${ebuild_pkg}/metadata.xml" "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/"
sed-or-die "GITHUB_REPOSITORY" "${GITHUB_REPOSITORY}" "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}"
sed-or-die "GITHUB_REF" "${git_branch:-master}" "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}"
ebuild "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}" manifest

# Enable test use-flag for package
update_use "${ebuild_cat}/${ebuild_pkg}" "test"

# Install dependencies of test ebuild
emerge --autounmask y --autounmask-write y --autounmask-only y "${ebuild_cat}/${ebuild_pkg}::${repo_id}" || \
    die "Unable to un-mask dependencies"
etc-update --automode -5
emerge --onlydeps "${ebuild_cat}/${ebuild_pkg}::${repo_id}" || die "Unable to merge dependencies"

# Test the ebuild
ebuild "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}" test || die "Package failed tests"

# Try to find the coverage script, if it exists and we have a CODECOV_TOKEN execute it and try to upload
# the coverage report
if [[ -x .gentoo/coverage.sh ]] && [[ -n "${CODECOV_TOKEN}" ]]; then
    chmod g+rX -R /var/tmp/portage
    pushd "/var/tmp/portage/${ebuild_cat}/${ebuild_pkg}-9999/work/${ebuild_pkg}-9999/" >/dev/null
    su --preserve-environment testrunner -c "${GITHUB_WORKSPACE}/.gentoo/coverage.sh" || die "Test coverage report generation failed"
    popd
    codecov -s /var/tmp/coverage -B "${GITHUB_REF##*/}" || die "Unable to upload coverage report"
fi

# Clean any distfiles or binary packages
eclean-pkg --deep
eclean-dist --deep

# Merge the ebuild
ebuild "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}" merge || die "Package failed merge"

echo "------------------------------------------------------------------------------------------------------------------------"
