kind: manual
description: Build the upstream PS Printer Application against the canonical FSDK printing stack.

sources:
  - kind: local
    path: Makefile
  - kind: local
    path: ps-printer-app.c
  - kind: local
    path: ps-printer-app.1
  - kind: local
    path: ps-printer-app.service
  - kind: local
    path: generic-ps-printer.ppd
  - kind: local
    path: testpage.ps
  - kind: local
    path: VERSION

build-depends:
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

depends:
  - ghostscript-fsdk.bst:printer-app/pappl-retrofit.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/ghostscript.bst

config:
  build-commands:
    - make clean
    - make -j2 VERSION="$(cat VERSION)" LDFLAGS="$LDFLAGS -ljpeg"
  install-commands:
    - install -D -m 0755 ps-printer-app "%{install-root}/usr/bin/ps-printer-app"
    - install -D -m 0644 ps-printer-app.1 "%{install-root}/usr/share/man/man1/ps-printer-app.1"
    - install -D -m 0644 generic-ps-printer.ppd "%{install-root}/usr/share/ppd/generic-ps-printer.ppd"
    - install -d "%{install-root}/usr/lib"
    - ln -s /usr/lib/cups "%{install-root}/usr/lib/ps-printer-app"
