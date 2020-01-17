#!/usr/bin/env bash
set -e

# shellcheck disable=SC1090
if ! source "${GITHUB_ACTION_LIB:-/usr/lib/github-action-lib.sh}"; then
	echo "::error::Unable to locate github-action-lib.sh"
	exit 1
fi

[[ ${GITHUB_REF} = refs/heads/* ]] && git_branch="${GITHUB_REF##*/}"
[[ ${GITHUB_REF} = refs/tags/* ]] && git_tag="${GITHUB_REF##*/}"

cat << END
------------------------------------------------------------------------------------------------------------------------
                            _   _                       _           _ _     _        _            _   
                           | | (_)                     | |         (_) |   | |      | |          | |  
                  __ _  ___| |_ _  ___  _ __ ______ ___| |__  _   _ _| | __| |______| |_ ___  ___| |_ 
                 / _\` |/ __| __| |/ _ \| '_ \______/ _ \ '_ \| | | | | |/ _\` |______| __/ _ \/ __| __|
                | (_| | (__| |_| | (_) | | | |    |  __/ |_) | |_| | | | (_| |      | ||  __/\__ \ |_ 
                 \__,_|\___|\__|_|\___/|_| |_|     \___|_.__/ \__,_|_|_|\__,_|       \__\___||___/\__|

                https://github.com/hacking-gentoo/action-ebuild-test         (c) 2019-2020 Max Hacking 
------------------------------------------------------------------------------------------------------------------------
INPUT_PACKAGE_ONLY="${INPUT_PACKAGE_ONLY}"
GITHUB_ACTOR="${GITHUB_ACTOR}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY}"
GITHUB_REF="${GITHUB_REF}"
git_branch="${git_branch}"
git_tag="${git_tag}"
------------------------------------------------------------------------------------------------------------------------
END

# If we are being run because of a tag (or release) then we're done.
if [[ -n "${git_tag}" ]]; then
	finish "Nothing to do for a tag action!"
fi

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

# Find the ebuild template and get its category, package and name
ebuild_path=$(find_ebuild_template)
ebuild_cat=$(get_ebuild_cat "${ebuild_path}")
ebuild_pkg=$(get_ebuild_pkg "${ebuild_path}")
ebuild_name=$(get_ebuild_name "${ebuild_path}")

# Display our findings thus far
echo "Located ebuild at ${ebuild_path}"
echo "  in category ${ebuild_cat}"
echo "    for ${ebuild_pkg}"
echo "      with name ${ebuild_name}"

# Create this package in the overlay
create_test_ebuild "${repo_path}" "${repo_id}" "${ebuild_cat}" "${ebuild_pkg}" "${ebuild_name}" "${ebuild_path}"

# Enable test use-flag for package
update_use "${ebuild_cat}/${ebuild_pkg}" "test"

# Install dependencies of test ebuild
install_ebuild_deps "${ebuild_cat}" "${ebuild_pkg}" "${repo_id}"

# Test the ebuild
run_ebuild_tests "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}"

# Try to find the coverage script, if it exists and we have a CODECOV_TOKEN execute it and try to upload
# the coverage report
if [[ -x .gentoo/coverage.sh ]] && [[ -n "${CODECOV_TOKEN}" ]]; then
	run_coverage_tests "${ebuild_cat}" "${ebuild_pkg}"
fi

# Merge the ebuild
merge_ebuild "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}"

# If we don't have an overlay_repo input defined then we're done
if [[ -z "${INPUT_OVERLAY_REPO}" ]]; then
	# Clean any distfiles or binary packages
	clean_binary_packages
	clean_distfiles
	
	# We're done!
	finish "Done!"
fi

# There is an overlay_repo input defined so we need to (maybe) update the
# live ebuild or metadata.xml.

# Check for repository deploy key.
[[ -z "${INPUT_DEPLOY_KEY}" ]] && die "Must set INPUT_DEPLOY_KEY"

# Calculate overlay branch name
overlay_branch="${INPUT_OVERLAY_BRANCH:-${ebuild_cat}/${ebuild_pkg}}"

# Configure ssh
configure_ssh "${INPUT_DEPLOY_KEY}"

# Configure git
configure_git "${GITHUB_ACTOR}"

# Checkout the overlay (master).
checkout_overlay_master "${INPUT_OVERLAY_REPO}"

# Check out the branch or create a new one
checkout_or_create_overlay_branch "${overlay_branch}"

# Try to rebase.
rebase_overlay_branch

# Add the overlay to repos.conf
repo_name="$(configure_overlay)"

# Ensure that this ebuild's category is present in categories file.
check_ebuild_category "${ebuild_cat}"

# Copy everything from the template to the new ebuild directory.
copy_ebuild_directory "${ebuild_cat}" "${ebuild_pkg}"

# Create the new ebuild - 9999 live version.
create_live_ebuild "${ebuild_cat}" "${ebuild_pkg}" "${ebuild_name}"

# Add it to git
git_add_files

# Check it with repoman
repoman_check

# Commit the new ebuild.
if git_commit "Automated update of ${ebuild_cat}/${ebuild_pkg} live ebuild / metadata"; then
	# Push git repo branch
	git_push "${overlay_branch}"
	
	# Create a pull request
	if [[ -n "${INPUT_AUTH_TOKEN}" ]]; then
		title="Automated release of ${ebuild_cat}/${ebuild_pkg}"
		msg="Automatically generated pull request to update overlay for release of ${ebuild_cat}/${ebuild_pkg}"
		create_pull_request "${overlay_branch}" "master" "${title}" "${msg}" "false" 
	fi
fi

# We're done!
finish "Done!"
