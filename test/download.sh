#!/bin/bash

## This script will setup dependencies for running tests.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# download relative dependencies
MOCKTIME_VERSION=Test-MockTime-0.17
curl -s https://cpan.metacpan.org/authors/id/D/DD/DDICK/${MOCKTIME_VERSION}.tar.gz | tar -xz -C "${DIR}"
mv "${DIR}/${MOCKTIME_VERSION}/lib/Test/MockTime.pm" "${DIR}"
rm -rf "${DIR}/Test-MockTime-0.17"
