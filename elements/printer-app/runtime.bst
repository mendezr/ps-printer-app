kind: compose
description: Compose only the runtime closure, excluding SDK build tools and development artifacts.

build-depends:
  - printer-app/stack.bst

config:
  exclude:
    - debug
    - devel
    - doc
    - locale
    - static-blocklist
    - tests
    - vm-only
