# action-ebuild-test

Automatically install an ebuild (including dependencies), run unit tests, (optionally) upload 
coverage reports to [codecov.io](https://codecov.io/) and (optionally) update a live ebuild in
a hosted repository.

## Functionality

Once configured pushing to a branch will automatically:
  * create a new live ebuild from the supplied template
  * run the ebuild test phase
  * generate / upload test coverage reports (optional)
  * deploy to an overlay repository (optional)
  * create / update a pull request (optional)

Automatic ebuild generation on release testing can be easily included using
[action-ebuild-release](https://github.com/hacking-gentoo/action-ebuild-release).

## Basic Use

### 1. Create a `.gentoo` folder in the root of your repository.

### 2. Create a live ebuild template in the appropriate sub-directory.

`.gentoo/dev-libs/hacking-bash-lib/hacking-bash-lib-9999.ebuild`

```bash
# Copyright 1999-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="A library script to log output and manage the generated log files"
HOMEPAGE="https://github.com/GITHUB_REPOSITORY"
LICENSE="LGPL-3"

if [[ ${PV} = *9999* ]]; then
    inherit git-r3
    EGIT_REPO_URI="https://github.com/GITHUB_REPOSITORY"
    EGIT_BRANCH="GITHUB_REF"
else
    SRC_URI="https://github.com/GITHUB_REPOSITORY/archive/${PV}.tar.gz -> ${P}.tar.gz"
fi

KEYWORDS=""
IUSE="test"
SLOT="0"

RESTRICT="!test? ( test )"

RDEPEND="app-arch/bzip2
    mail-client/mutt
    sys-apps/util-linux"
DEPEND="test? (
    ${RDEPEND}
    dev-util/bats-assert
    dev-util/bats-file
)"

src_test() {
    bats --tap tests || die "Tests failed"
}

src_install() {
    einstalldocs

    insinto /usr/lib
    doins usr/lib/*
}
```

The special markers `GITHUB_REPOSITORY` and `GITHUB_REF` will be automatically replaced with appropriate values
when the action is executed.

### 3. Create a metadata.xml file

`.gentoo/dev-libs/hacking-bash-lib/metadata.xml`

```xml
<?xml version='1.0' encoding='UTF-8'?>
<!DOCTYPE pkgmetadata SYSTEM "http://www.gentoo.org/dtd/metadata.dtd">

<pkgmetadata>
    <maintainer type="person">
        <email>overlay-maintainer@example.com</email>
        <name>Overlay Maintainer</name>
    </maintainer>
    <upstream>
        <maintainer>
	    <email>default-package-maintainer@example.com</email>
	    <name>Default Package Maintainer</name>
	</maintainer>
	<bugs-to>https://github.com/MADhacking/bash-outlogger/issues</bugs-to>
	<doc>https://github.com/MADhacking/bash-outlogger</doc>
    </upstream>
</pkgmetadata>
```

### 4. (Optional) Add any overlays required for the build / test to an overlays file.

`.gentoo/overlays`

```
mad-hacking    https://github.com/MADhacking/overlay.git
```

### 5. (Optional) Add a `coverage.sh` script to generate test coverage reports.

`.gentoo/coverage.sh`

```bash
#!/usr/bin/env bash

kcov --bash-dont-parse-binary-dir \
     --include-path=. \
     /var/tmp/coverage \
     bats -t tests
```

Your coverage script will need to output coverage reports to `/var/tmp/coverage`

### 6. Create a GitHub workflow file

`.github/workflows/run-ebuild-tests.yml`

```yaml
name: Ebuild Tests

on:
  push:
    branches:
      - '**'
    tags-ignore:
      - '*.*'
    paths-ignore:
      - 'README.md'
      - 'LICENSE'
      - '.github/**'

jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
    # Check out the repository
    - uses: actions/checkout@master

    # Prepare the environment
    - name: Prepare
      id: prepare
      run: |
        echo "::set-output name=datetime::$(date +"%Y%m%d%H%M")"
        echo "::set-output name=workspace::${GITHUB_WORKSPACE}"
        mkdir -p "${GITHUB_WORKSPACE}/distfiles" "${GITHUB_WORKSPACE}/binpkgs"

    # Cache distfiles and binary packages
    - name: Cache distfiles
      id: cache-distfiles
      uses: gerbal/always-cache@v1.0.3
      with:
        path: ${{ steps.prepare.outputs.workspace }}/distfiles
        key: distfiles-${{ steps.prepare.outputs.datetime }}
        restore-keys: |
          distfiles-${{ steps.prepare.outputs.datetime }}
          distfiles
    - name: Cache binpkgs
      id: cache-binpkgs
      uses: gerbal/always-cache@v1.0.3
      with:
        path: ${{ steps.prepare.outputs.workspace }}/binpkgs
        key: binpkgs-${{ steps.prepare.outputs.datetime }}
        restore-keys: |
          binpkgs-${{ steps.prepare.outputs.datetime }}
          binpkgs

    # Run the ebuild tests
    - uses: hacking-gentoo/action-ebuild-test@v1
      env:
        # Optional code coverage token
        CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
      with:
        # Option security tokens / keys for automatic deployment
        auth_token: ${{ secrets.PR_TOKEN }}
        deploy_key: ${{ secrets.DEPLOY_KEY }}
        overlay_repo: hacking-gentoo/overlay    
```

### 7. (Optional) Create tokens / keys for automatic deployment

#### Configuring `PR_TOKEN`

The above workflow requires a [personal access token](https://help.github.com/en/github/authenticating-to-github/creating-a-personal-access-token-for-the-command-line) be configured for the user running the ebuild test action.

This access token will need to be made available to the workflow using the [secrets](https://help.github.com/en/github/automating-your-workflow-with-github-actions/virtual-environments-for-github-actions#creating-and-using-secrets-encrypted-variables)
feature and will be used to authenticate when creating a new pull request.

#### Configuring `DEPLOY_KEY`

The above workflow also requires a [deploy key](https://developer.github.com/v3/guides/managing-deploy-keys/#deploy-keys)
be configured for the destination repository.

This deploy key will also need to be made available to the workflow using the [secrets](https://help.github.com/en/github/automating-your-workflow-with-github-actions/virtual-environments-for-github-actions#creating-and-using-secrets-encrypted-variables)
feature.
