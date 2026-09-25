#!/usr/bin/env python3
"""Measure the Foomatic PostScript PPD archive build of the shipped OCI image.

The timed phases run the build-commands of
elements/printer-app/foomatic-ps-ppds.bst, in order, against a foomatic-db
checkout staged the way its `make install` installs it in FSDK (PPDs
gzip-compressed under db/source/PPD). Staging and the build-tree copy are
reported separately from the timed phases, and no files outside a temporary
directory are edited.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Callable

# (key, summary label, shell commands). The commands are the build-commands of
# elements/printer-app/foomatic-ps-ppds.bst, split into phases and run with the
# build directory (holding PPD/) as the working directory.
PHASES: tuple[tuple[str, str, str], ...] = (
    (
        "family_removal",
        "Remove PDF/PXL/PCL5 families",
        "rm -rf PPD/*/PDF PPD/*/PXL PPD/*/PCL5",
    ),
    (
        "decompression",
        "Decompress `.ppd.gz` (gunzip)",
        "find PPD -type f -name '*.ppd.gz' -exec gunzip {} +",
    ),
    (
        "non_ppd_removal_and_mode",
        "Remove non-PPD files, chmod 0644",
        "find PPD -type f ! -name '*.ppd' -delete\n"
        "find PPD -type f -exec chmod 0644 {} +",
    ),
    (
        "sanitization",
        "Sanitize PPD headers (perl)",
        "find PPD -name '*.ppd' -exec perl -p -i -e "
        r"""'s/^\*CloseUI(\s+)/*CloseUI:\1/; s/\*1284DeviceId/*1284DeviceID/' {} +""",
    ),
)
PHASE_KEYS = tuple(key for key, _, _ in PHASES) + ("pyppd_archive_build",)
RECIPE = Path(__file__).resolve().parent.parent / "elements/printer-app/foomatic-ps-ppds.bst"
# Untimed build-tree copy before the phases, and the pyppd phase after them.
RECIPE_COPY = ("mkdir -p PPD", "cp -a /usr/share/foomatic/db/source/PPD/. PPD/")
RECIPE_PYPPD = "pyppd -v -o foomatic-ps-ppds PPD"
MINIMUM_DRIVERS = 1000


def recipe_build_commands(recipe: Path) -> list[str]:
    """Return the non-empty command lines of the element's build-commands block."""
    lines = recipe.read_text(encoding="utf-8").splitlines()
    start = lines.index("  build-commands:") + 1
    end = lines.index("  install-commands:")
    return [line.strip() for line in lines[start:end] if line.strip() not in ("", "- |")]


def benchmark_commands() -> list[str]:
    """The command lines this benchmark runs, in recipe order."""
    phase_lines = [line for _, _, script in PHASES for line in script.splitlines()]
    return [*RECIPE_COPY, *phase_lines, RECIPE_PYPPD]


def time_operation(name: str, operation: Callable[[], Any]) -> float:
    started = time.perf_counter()
    operation()
    elapsed = time.perf_counter() - started
    print(f"{name}: {elapsed:.3f}s", flush=True)
    return elapsed


def inventory(root: Path) -> dict[str, int]:
    files = [path for path in root.rglob("*") if path.is_file()]
    ppds = [path for path in files if path.name.endswith(".ppd")]
    compressed_ppds = [path for path in files if path.name.endswith(".ppd.gz")]
    return {
        "files": len(files),
        "ppd_files": len(ppds),
        "compressed_ppd_files": len(compressed_ppds),
        "bytes": sum(path.stat().st_size for path in files),
        "ppd_bytes": sum(path.stat().st_size for path in ppds),
        "compressed_ppd_bytes": sum(path.stat().st_size for path in compressed_ppds),
    }


def stage_fsdk_install(source_ppds: Path, staged_ppds: Path) -> None:
    """Reproduce foomatic-db's `make install-db` PPD install into staged_ppds.

    Makefile.in copies db/source/PPD with `tar --exclude=.svn`, then, because
    configure enables GZIP_PPDS whenever gzip is found (FSDK passes no
    --disable-gzip-ppds), gzips every *.ppd one file at a time.
    """
    shutil.copytree(source_ppds, staged_ppds, ignore=shutil.ignore_patterns(".svn"))
    subprocess.run(
        ["find", str(staged_ppds), "-name", "*.ppd", "-exec", "gzip", "{}", ";"],
        env={**os.environ, "GZIP": ""},
        check=True,
    )


def run_phase(key: str, build_dir: Path) -> None:
    commands = next(script for name, _, script in PHASES if name == key)
    subprocess.run(
        ["bash", "-euo", "pipefail", "-c", commands], cwd=build_dir, check=True
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "foomatic_source", type=Path, help="checkout of the pinned foomatic-db source"
    )
    parser.add_argument("pyppd_source", type=Path, help="checkout of the pinned pyppd source")
    parser.add_argument("report", type=Path, help="write the JSON and Markdown report here")
    args = parser.parse_args()

    foomatic_source = args.foomatic_source.resolve()
    source_ppds = foomatic_source / "db/source/PPD"
    pyppd_source = args.pyppd_source.resolve()
    pyppd_cli = pyppd_source / "bin/pyppd"
    if not source_ppds.is_dir():
        parser.error(f"Foomatic PPD source directory not found: {source_ppds}")
    if not pyppd_cli.is_file():
        parser.error(f"pyppd executable not found: {pyppd_cli}")
    if recipe_build_commands(RECIPE) != benchmark_commands():
        parser.error(f"{RECIPE} build-commands changed; update PHASES to match them")

    args.report.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="foomatic-ppd-benchmark-") as temporary:
        work = Path(temporary)
        staged_ppds = work / "staged/usr/share/foomatic/db/source/PPD"
        staging_seconds = time_operation(
            "fsdk_install_staging", lambda: stage_fsdk_install(source_ppds, staged_ppds)
        )
        staged = inventory(staged_ppds)

        build_dir = work / "build"
        ppd_root = build_dir / "PPD"
        build_dir.mkdir()
        copy_seconds = time_operation(
            "build_tree_copy",
            lambda: shutil.copytree(staged_ppds, ppd_root, symlinks=True),
        )

        phase_seconds: dict[str, float] = {}
        phase_inventory: dict[str, dict[str, int]] = {}
        for key, _, _ in PHASES:
            phase_seconds[key] = time_operation(key, lambda: run_phase(key, build_dir))
            phase_inventory[key] = inventory(ppd_root)
        archived = phase_inventory["sanitization"]
        non_0644 = sorted(
            path.relative_to(ppd_root).as_posix()
            for path in ppd_root.rglob("*")
            if path.is_file() and path.stat().st_mode & 0o7777 != 0o644
        )
        if non_0644:
            raise RuntimeError(f"PPDs not mode 0644 after chmod: {non_0644[:5]}")

        archive = build_dir / "foomatic-ps-ppds"
        pyenv = {**os.environ, "PYTHONPATH": str(pyppd_source)}
        phase_seconds["pyppd_archive_build"] = time_operation(
            "pyppd_archive_build",
            lambda: subprocess.run(
                [sys.executable, str(pyppd_cli), "-v", "-o", "foomatic-ps-ppds", "PPD"],
                cwd=build_dir,
                env=pyenv,
                check=True,
            ),
        )
        if not archive.is_file() or archive.stat().st_size == 0:
            raise RuntimeError("pyppd did not produce a non-empty archive")

        listing = work / "drivers.txt"

        def list_archive() -> None:
            with listing.open("wb") as output:
                subprocess.run(
                    [str(archive), "list"], cwd=work, env=pyenv, stdout=output, check=True
                )

        list_seconds = time_operation("archive_listing", list_archive)
        with listing.open("rb") as listing_file:
            driver_entries = sum(1 for line in listing_file if line.strip())
        if driver_entries < MINIMUM_DRIVERS:
            raise RuntimeError(
                f"pyppd archive exposes only {driver_entries} drivers; "
                f"expected at least {MINIMUM_DRIVERS}"
            )
        driver_listing_sha256 = hashlib.sha256(listing.read_bytes()).hexdigest()
        retained_paths = "\n".join(
            sorted(path.relative_to(ppd_root).as_posix() for path in ppd_root.rglob("*.ppd"))
        ) + "\n"
        retained_paths_sha256 = hashlib.sha256(retained_paths.encode("utf-8")).hexdigest()

        report: dict[str, Any] = {
            "platform": platform.platform(),
            "architecture": platform.machine(),
            "recipe": "elements/printer-app/foomatic-ps-ppds.bst",
            "source": {
                "foomatic_commit": subprocess.check_output(
                    ["git", "-C", str(foomatic_source), "rev-parse", "HEAD"], text=True
                ).strip(),
                "pyppd_commit": subprocess.check_output(
                    ["git", "-C", str(pyppd_source), "rev-parse", "HEAD"], text=True
                ).strip(),
            },
            "source_inventory": inventory(source_ppds),
            "staged_inventory": staged,
            "inventory_after_phase": phase_inventory,
            "untimed_seconds": {
                "fsdk_install_staging": round(staging_seconds, 3),
                "build_tree_copy": round(copy_seconds, 3),
                "archive_listing": round(list_seconds, 3),
            },
            "phase_seconds": {key: round(phase_seconds[key], 3) for key in PHASE_KEYS},
            "archive": {
                "bytes": archive.stat().st_size,
                "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                "drivers": driver_entries,
                "driver_listing_sha256": driver_listing_sha256,
                "listing_bytes": listing.stat().st_size,
            },
            "retained_ppd_paths_sha256": retained_paths_sha256,
        }

    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    phases = report["phase_seconds"]
    untimed = report["untimed_seconds"]
    total_build = sum(phases.values())
    slowest = max(PHASE_KEYS, key=lambda key: phases[key])
    labels = {key: label for key, label, _ in PHASES}
    labels["pyppd_archive_build"] = "pyppd parse/compress/archive"
    markdown = [
        f"### Foomatic PPD benchmark — `{report['architecture']}`",
        "",
        f"- Recipe: `{report['recipe']}` build-commands",
        f"- Source commits: foomatic-db `{report['source']['foomatic_commit']}`, "
        f"pyppd `{report['source']['pyppd_commit']}`",
        f"- FSDK-staged input: {staged['compressed_ppd_files']} `.ppd.gz` "
        f"({staged['compressed_ppd_bytes']} bytes), {staged['files']} files total",
        f"- Archived PPD files: {archived['ppd_files']} ({archived['ppd_bytes']} bytes)",
        f"- Archive: {report['archive']['bytes']} bytes; {driver_entries} discoverable driver entries",
        f"- Archive SHA-256: `{report['archive']['sha256']}`",
        f"- Retained PPD path inventory SHA-256: `{retained_paths_sha256}`",
        f"- Archive driver listing SHA-256: `{driver_listing_sha256}`",
        f"- Build phases total: {total_build:.3f}s; slowest phase: `{slowest}` "
        f"({phases[slowest]:.3f}s)",
        "",
        "| Phase | Seconds |",
        "| --- | ---: |",
        *(f"| {labels[key]} | {phases[key]:.3f} |" for key in PHASE_KEYS),
        "",
        "| Not build time | Seconds |",
        "| --- | ---: |",
        f"| Stage foomatic-db as FSDK installs it (copy + gzip) | "
        f"{untimed['fsdk_install_staging']:.3f} |",
        f"| Copy staged PPDs into the build tree | {untimed['build_tree_copy']:.3f} |",
        f"| List generated archive (measurement only) | {untimed['archive_listing']:.3f} |",
        "",
        "Timed phases are the build-commands of `elements/printer-app/foomatic-ps-ppds.bst`, "
        "in order, run on this runner outside BuildStream. No optimization is applied. The "
        "complete OCI image size and BuildStream sandbox overhead are not measured here; "
        "archive size is.",
        "",
        f"JSON report: `{args.report}`",
    ]
    markdown_text = "\n".join(markdown) + "\n"
    args.report.with_suffix(".md").write_text(markdown_text, encoding="utf-8")
    print(markdown_text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
