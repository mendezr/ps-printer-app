#!/usr/bin/env bash
set -euo pipefail

cflags="-Iretrofit $(pkg-config --cflags pappl libppd libcupsfilters libpappl-retrofit) $(cups-config --cflags)"
libs="$(pkg-config --libs pappl libppd libcupsfilters libpappl-retrofit) $(cups-config --image --libs)"

# Build the repository callback and use the real pinned retrofit matcher.
# The test binary is never installed in the OCI runtime.
# shellcheck disable=SC2086
cc $cflags -Dmain=ps_app_test_main -c ps-printer-app.c -o autoadd-app.o
# shellcheck disable=SC2086
cc $cflags autoadd-no-match.c autoadd-app.o -o autoadd-no-match $libs -ljpeg
./autoadd-no-match
