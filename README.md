# action-ebuild-test

Automatically install an ebuild (including dependencies), run unit tests and (optionally) upload 
coverage reports to [codecov.io](https://codecov.io/).

## Basic Usage

An example workflow:

```yaml
name: Ebuild Tests

on: [push]

jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@master
    - uses: hacking-gentoo/action-ebuild-test@master
```

You will also need to create an ebuild template:

```bash
# Copyright 1999-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="A test package"
HOMEPAGE="https://github.com/hacking-actions/test-package"
LICENSE="MIT"

if [[ ${PV} = *9999* ]]; then
    inherit git-r3
    EGIT_REPO_URI="https://github.com/GITHUB_REPOSITORY"
    EGIT_BRANCH="GITHUB_REF"
else
    SRC_URI="https://github.com/GITHUB_REPOSITORY/archive/${P}.tar.gz"
fi

KEYWORDS="amd64 x86"
IUSE="test"
SLOT="0"

RESTRICT="!test? ( test )"

RDEPEND=""
DEPEND="test? ( ${RDEPEND} )"

src_test() {
    ...
}

src_install() {
    ...
}
```

And the usual [metadata.xml](https://devmanual.gentoo.org/ebuild-writing/misc-files/metadata/index.html)

## Coverage Reports

To produce test coverage reports a `CODECOV_TOKEN` must be supplied in the step `env`:

```yaml
name: Test Coverage

on: [push]

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@master
    - uses: hacking-actions/bats-kcov@master
      env:
        CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
```

And a `coverage.sh` file:

```bash
#!/usr/bin/env bash

kcov --bash-dont-parse-binary-dir \
     --include-path=. \
     /var/tmp/coverage \
     bats -t tests
```

This is an example using [bats](https://github.com/bats-core/bats-core) and 
[kcov](https://github.com/SimonKagstrom/kcov), although many other combinations of test runner and 
coverage report generator should be possible. The important point to note is that coverage reports
should be placed in `/var/tmp/coverage` so they can be located by the upload tool.
