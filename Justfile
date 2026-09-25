bst2_image := "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:64eb0b4930d57a92710822898fb73af6cc1ae35d"
image_ref := "ghcr.io/projectbluefin/ps-printer-app:build"

default:
    @just --list

bst *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream"
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{ justfile_directory() }}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -w /src \
        "{{ bst2_image }}" \
        bash -c 'bst "$@"' -- --no-interactive {{ ARGS }}

validate:
    #!/usr/bin/env bash
    set -euo pipefail
    tracked="$(sed -n 's/^[[:space:]]*track: \(debian\/.*\)$/\1/p' elements/printer-app/hplip-ps.bst)"
    locked="$(sed -n 's/^[[:space:]]*ref: \(debian\/.*\)-[0-9]*-g[0-9a-f]*$/\1/p' elements/printer-app/hplip-ps.bst)"
    [[ -n "$tracked" && "$tracked" == "$locked" ]] || { echo 'HPLIP track and immutable ref differ' >&2; exit 1; }
    just bst show --deps all oci/ps-printer-app.bst

fetch:
    just bst source fetch --ignore-project-source-remotes --source-remote https://cache.projectbluefin.io:11001 --deps all oci/ps-printer-app.bst
    just bst source fetch --ignore-project-source-remotes --source-remote https://cache.projectbluefin.io:11001 --deps all printer-app/autoadd-test.bst

build:
    just bst build oci/ps-printer-app.bst
    just export

export:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf .build-out
    just bst artifact checkout oci/ps-printer-app.bst --directory /src/.build-out
    image_id="$(podman pull -q oci:.build-out)"
    rm -rf .build-out
    podman tag "$image_id" "{{ image_ref }}"

verify-cups-patch-chain:
    tests/cups-patch-chain.sh

verify-autoadd:
    just bst build printer-app/autoadd-test.bst

verify:
    just validate
    just verify-cups-patch-chain
    just verify-autoadd
    just build
    tests/verify-oci.sh

sbom:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream" "${HOME}/.cache/pip"
    git_sha="$(git rev-parse HEAD)"
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{ justfile_directory() }}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -v "${HOME}/.cache/pip:/root/.cache/pip:rw" \
        -w /src \
        -e GIT_SHA="$git_sha" \
        "{{ bst2_image }}" \
        bash -c '
            pip install --quiet \
              git+https://gitlab.com/BuildStream/buildstream-sbom.git@0706fec3bedf6f73bd9d2fed32c2aed585feef8d
            buildstream-sbom oci/ps-printer-app.bst \
                --spdx-name ps-printer-app \
                --spdx-namespace "https://github.com/projectbluefin/ps-printer-app/sbom/${GIT_SHA}" \
                --spdx-creator "Tool: buildstream-sbom" \
                --spdx-creator "Organization: projectbluefin" \
                --deps all \
                --output /src/ps-printer-app.spdx.json
        '
