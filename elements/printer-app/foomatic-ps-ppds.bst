kind: manual
description: Archive the manufacturer-supplied PostScript PPDs from FSDK's pinned Foomatic database.

build-depends:
  - ghostscript-fsdk.bst:printer-app/pyppd.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/foomatic-db.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/sed.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst

depends:
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/python3.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/xz.bst

config:
  build-commands:
    - |
      mkdir -p payload
      cp -a /usr/share/foomatic/db/source/PPD/. payload/
      rm -rf payload/*/PDF payload/*/PXL payload/*/PCL5
      find payload -type f ! -name '*.ppd' -delete
      find payload -type f -name '*.ppd' -exec chmod -x '{}' +
      find payload -type f -name '*.ppd' -exec sed -E -i 's/^\*CloseUI([[:space:]]+)/\*CloseUI:\1/; s/\*1284DeviceId/\*1284DeviceID/g' '{}' +
      pyppd -v -o foomatic-ps-ppds payload
  install-commands:
    - install -D -m 0755 foomatic-ps-ppds "%{install-root}/usr/share/ppd/foomatic-ps-ppds"
