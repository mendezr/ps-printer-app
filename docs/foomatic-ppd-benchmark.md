# Measuring the Foomatic PostScript PPD build

Run the **Foomatic PPD build benchmark** workflow (or let it run on a PR that
changes its inputs) to profile the shipped PPD archive build on clean native
amd64 and arm64 GitHub-hosted runners. Each runner checks out the same
immutable foomatic-db and pyppd commits, applies no optimization, and reports
its own timings and output sizes in the workflow summary. It builds no image.

## Inputs

- foomatic-db `76dd1e31354c189b2edd9ae8201285d622c89395`, the commit
  freedesktop-sdk 26.08.1 builds (`components/foomatic-db.bst`, reached here
  through `fsdk-containers.bst:printing/foomatic-db.bst`).
- pyppd `29ccf6cf85781315a696774e7458a2f1f61aac57`, the pin in
  `elements/printer-app/pyppd.bst`.

FSDK builds foomatic-db with autotools. Its `make install-db` copies
`db/source/PPD` (tar, excluding `.svn`) and, since configure enables gzip
compression whenever `gzip` is found, runs `gzip` on every `*.ppd`. The
profiler reproduces that staging first, so the recipe sees the same
`.ppd.gz` tree it gets from `/usr/share/foomatic/db/source/PPD`. Staging and
the copy into the build tree are reported separately and are not build time.

## Timed phases

`scripts/benchmark_foomatic_ppds.py` runs the build-commands of
`elements/printer-app/foomatic-ps-ppds.bst`, in order, and times each phase:

1. `family_removal`: remove the `PDF`, `PXL` and `PCL5` families.
2. `decompression`: `gunzip` every `.ppd.gz`.
3. `non_ppd_removal_and_mode`: delete non-`.ppd` files, `chmod 0644`.
4. `sanitization`: the `perl` `*CloseUI` / `*1284DeviceId` header fixes.
5. `pyppd_archive_build`: `pyppd -v -o foomatic-ps-ppds PPD` (parse, xz
   compress, write the archive).

The profiler refuses to run if the element's build-commands no longer match
these phases. It reports file counts and bytes of the FSDK-staged input and
after each phase, the archive size and SHA-256, and the number of driver
entries `foomatic-ps-ppds list` exposes. Fewer than 1,000 driver entries
fails the benchmark, the existing payload test's minimum, as a guard against an
empty or grossly truncated archive. SHA-256 digests of the retained PPD path
inventory and of the driver listing make inventory comparisons with the
shipped image reproducible without dumping thousands of names into the
summary. Listing the archive is a post-build measurement, excluded from the
build-phase total.

This isolates the PPD archive work and its artifact size; it does **not**
measure complete OCI image size or BuildStream sandbox overhead. Native
architecture results are recorded separately because CPU and runner
characteristics can affect the timings, even though the generated archive is
architecture-independent. No optimization or speedup claim should be made
without comparing these baselines and confirming the full source-backed driver
inventory and real-image print path.

To run locally with checkouts at the same commits (needs `gzip`, `perl`, `xz`):

```sh
python3 scripts/benchmark_foomatic_ppds.py \
  /path/to/foomatic-db /path/to/pyppd /tmp/foomatic-ppd.json
```
