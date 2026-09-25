kind: stack
description: PS application, its PPD/filter providers and the sole FSDK CUPS runtime.

depends:
  - printer-app/application.bst
  - printer-app/runtime-files.bst
  - printer-app/foomatic-ps-ppds.bst
  - printer-app/hplip-ps.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/avahi.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/ca-certificates.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/catatonit.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/cups-daemon-only.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/cups-filters.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/dbus.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/ghostscript.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/libcupsfilters.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/libppd.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/python3.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/xz.bst
  - ghostscript-fsdk.bst:freedesktop-sdk.bst:components/tzdata.bst
