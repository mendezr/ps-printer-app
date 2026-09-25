kind: manual
description: Probe the repository's auto-add callback with the real pinned retrofit matcher.

sources:
  - kind: local
    path: ps-printer-app.c
  - kind: local
    path: tests/autoadd-no-match.c
  - kind: local
    path: tests/autoadd-no-match.sh
  # Only the private test header is consumed from this source checkout. The
  # library itself remains the single Ghostscript-junction build artifact.
  - kind: git_repo
    url: github:OpenPrinting/pappl-retrofit.git
    track: master
    ref: 1626b338fc8b92a99c2c1a483ac39c739d71b305
    directory: retrofit

build-depends:
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

depends:
  - ghostscript-fsdk.bst:printer-app/pappl-retrofit.bst

config:
  build-commands:
    - bash autoadd-no-match.sh
