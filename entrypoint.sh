#!/usr/bin/env bash
set -e

function die()
{
    echo "::error::$1"
	echo "------------------------------------------------------------------------------------------------------------------------"
    exit 1
}

function infomsg()
{
	echo -e "\n${1}\n"
}


function create_pull_request() 
{
	local src tgt title body draft api_ver base_url auth_hdr header pulls_url repo_base query_url resp pr data
	
    src="${1}"		# from this branch
    tgt="${2}"		# pull request TO this target
    title="${3}"	# pull request title
    body="${4}"		# this is the content of the message

	[[ -z "${src}" ]] && die "create_pull_request() requires a source branch as parameter 1"
	[[ -z "${tgt}" ]] && die "create_pull_request() requires a target branch as parameter 2"
	[[ -z "${title}" ]] && die "create_pull_request() requires a title as parameter 3"
	[[ -z "${body}" ]] && die "create_pull_request() requires a body as parameter 4"

    if [[ "${5}" ==  "true" ]]; then
      draft="true";
    else
      draft="false";
    fi

	api_ver="v3"
	base_url="https://api.github.com"
	auth_hdr="Authorization: token ${INPUT_AUTH_TOKEN}"
	header="Accept: application/vnd.github.${api_ver}+json; application/vnd.github.antiope-preview+json; application/vnd.github.shadow-cat-preview+json"
	pulls_url="${base_url}/repos/${INPUT_OVERLAY_REPO}/pulls"
	repo_base="${INPUT_OVERLAY_REPO%/*}"

    # Check if the branch already has a pull request open
    query_url="${pulls_url}?base=${tgt}&head=${repo_base}:${src}&state=open"
    echo "curl -sSL -H \"${auth_hdr}\" -H \"${header}\" --user \"${GITHUB_ACTOR}:\" -X GET \"${query_url}\""
    resp=$(curl -sSL -H "${auth_hdr}" -H "${header}" --user "${GITHUB_ACTOR}:" -X GET "${query_url}")
    echo -e "Raw response:\n${resp}"
    pr=$(echo "${resp}" | jq --raw-output '.[] | .head.ref')
    echo "Response ref: ${pr}"

    if [[ -n "${pr}" ]]; then
	    # A pull request is already open
        echo "Pull request from ${src} to ${tgt} is already open!"
    else
        # Post new pull request
        data="{ \"base\":\"${tgt}\", \"head\":\"${src}\", \"title\":\"${title}\", \"body\":\"${body}\", \"draft\":${draft} }"
        echo "curl -sSL -H \"${auth_hdr}\" -H \"${header}\" --user \"${GITHUB_ACTOR}:\" -X POST --data \"${data}\" \"${pulls_url}\""
        curl -sSL -H "${auth_hdr}" -H "${header}" --user "${GITHUB_ACTOR}:" -X POST --data "${data}" "${pulls_url}" || \
        	die "Unable to create pull request"
    fi
}

SEMVER_REGEX="^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*$"

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

                https://github.com/hacking-gentoo/action-ebuild-test              (c) 2019 Max Hacking 
------------------------------------------------------------------------------------------------------------------------
INPUT_PACKAGE_ONLY="${INPUT_PACKAGE_ONLY}"
GITHUB_ACTOR="${GITHUB_ACTOR}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY}"
GITHUB_REF="${GITHUB_REF}"
git_branch="${git_branch}"
git_tag="${git_tag}"
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
cp -r ".gentoo/${ebuild_cat}/${ebuild_pkg}"/* "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/"
unexpand --first-only -t 4 ".gentoo/${ebuild_path}" > "${repo_path}/${repo_id}/${ebuild_path}"
if [[ "${INPUT_PACKAGE_ONLY}" != "true" ]]; then
	sed-or-die "GITHUB_REPOSITORY" "${GITHUB_REPOSITORY}" "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}"
	sed-or-die "GITHUB_REF" "${git_branch:-master}" "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}"
fi
ebuild "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}" manifest

# Enable test use-flag for package
update_use "${ebuild_cat}/${ebuild_pkg}" "test"

# Install dependencies of test ebuild
emerge --autounmask y --autounmask-write y --autounmask-only y "${ebuild_cat}/${ebuild_pkg}::${repo_id}" || \
    die "Unable to un-mask dependencies"
etc-update --automode -5
emerge --onlydeps "${ebuild_cat}/${ebuild_pkg}::${repo_id}" || die "Unable to merge dependencies"

# Test the ebuild
TERM="dumb" ebuild "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}" test || die "Package failed tests"

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
