kind: manual
description: Install the PS-specific rootless launcher and convert the upstream test page to PDF.

sources:
  - kind: local
    path: files/container-entrypoint.sh
  - kind: local
    path: testpage.ps

build-depends:
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/ghostscript.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst

config:
  build-commands:
    - gs -q -dSAFER -dBATCH -dNOPAUSE -sDEVICE=pdfwrite -sOutputFile=testpage.pdf testpage.ps
  install-commands:
    - install -D -m 0755 container-entrypoint.sh "%{install-root}/usr/libexec/ps-printer-app/container-entrypoint"
    - install -D -m 0644 testpage.pdf "%{install-root}/usr/share/ps-printer-app/testpage.pdf"
    - install -d -m 0777 "%{install-root}/var/lib/ps-printer-app" "%{install-root}/var/spool/ps-printer-app"
