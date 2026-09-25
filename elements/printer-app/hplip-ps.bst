kind: manual
description: Build Debian-patched HPLIP's PostScript PIN filter and manufacturer PPD archive.

sources:
  - kind: git_repo
    url: salsa:printing-team/hplip.v2.git
    # renovate: datasource=gitlab-tags depName=printing-team/hplip.v2 registryUrl=https://salsa.debian.org
    track: debian/3.26.4+dfsg0-3
    ref: debian/3.26.4+dfsg0-3-0-gf27f786d5f1060cce7c92e42488bd5e5d00ba135

build-depends:
  - ghostscript-fsdk.bst:printer-app/pyppd.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/sed.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/findutils.bst

depends:
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/cups.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/python3.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/xz.bst

config:
  build-commands:
    - |
      touch prnt/hpps/config.h
      gcc -o hpps prnt/hpps/*.c -Iprnt/hpps $(cups-config --cflags) $(cups-config --ldflags) -lcups
      rm prnt/hpps/config.h
    - |
      mkdir -p payload
      cp -a prnt/ps/. payload/
      find payload -type f ! -name '*.ppd' ! -name '*.ppd.gz' -delete
      find payload -type f -name '*.ppd' -exec chmod -x '{}' +
      find payload -type f -name '*.ppd' -exec sed -E -i 's/^\*CloseUI([[:space:]]+)/\*CloseUI:\1/; s/\*1284DeviceId/\*1284DeviceID/g' '{}' +
      pyppd -v -o hplip-ps-ppds payload
  install-commands:
    - install -D -m 0755 hpps "%{install-root}/usr/lib/cups/filter/hpps"
    - install -D -m 0755 hplip-ps-ppds "%{install-root}/usr/share/ppd/hplip-ps-ppds"
