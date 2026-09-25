kind: junction

# The referenced Ghostscript project owns the sole patched FSDK CUPS artifact,
# PAPPL's common source patches and pappl-retrofit. Never vendor its CUPS patches.
sources:
  - kind: git_repo
    url: github:projectbluefin/ghostscript-printer-app.git
    track: testing
    ref: v10.07.1-1-4-gf36174f27f5bb08421712bd77680cbddfc71862e
