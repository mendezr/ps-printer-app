import gzip
import tempfile
import unittest
from pathlib import Path

from scripts.benchmark_foomatic_ppds import (
    PHASES,
    inventory,
    run_phase,
    stage_fsdk_install,
)

PPD_TEXT = "*PPD-Adobe: 4.3\n*CloseUI *Duplex\n*1284DeviceId: MFG:Acme;\n"


class PpdPipelineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.work = Path(self.temporary.name)
        self.build = self.work / "build"
        self.root = self.build / "PPD"
        self.root.mkdir(parents=True)

    def tearDown(self):
        self.temporary.cleanup()

    def write_gz(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(gzip.compress(text.encode("ascii")))

    def retained(self) -> list[str]:
        return sorted(p.relative_to(self.root).as_posix() for p in self.root.rglob("*") if p.is_file())

    def test_fsdk_staging_gzips_every_ppd_and_keeps_other_files(self):
        source = self.work / "source/PPD"
        (source / "Acme").mkdir(parents=True)
        (source / "Acme/printer.ppd").write_text(PPD_TEXT, encoding="ascii")
        (source / "Acme/PDF").mkdir()
        (source / "Acme/PDF/pdf.ppd").write_text(PPD_TEXT, encoding="ascii")
        (source / "Acme/ReadMe.htm").write_text("<p>notes</p>", encoding="ascii")
        (source / ".svn").mkdir()
        (source / ".svn/entries").write_text("svn", encoding="ascii")
        staged = self.work / "staged/PPD"

        stage_fsdk_install(source, staged)

        self.assertEqual(
            sorted(p.relative_to(staged).as_posix() for p in staged.rglob("*") if p.is_file()),
            ["Acme/PDF/pdf.ppd.gz", "Acme/ReadMe.htm", "Acme/printer.ppd.gz"],
        )
        self.assertEqual(
            gzip.decompress((staged / "Acme/printer.ppd.gz").read_bytes()).decode("ascii"),
            PPD_TEXT,
        )
        self.assertEqual(inventory(staged)["compressed_ppd_files"], 2)

    def test_family_removal_drops_only_pdf_pxl_pcl5_directories(self):
        for family in ("PDF", "PXL", "PCL5", "PS"):
            self.write_gz(self.root / "Acme" / family / f"{family}.ppd.gz", PPD_TEXT)
        self.write_gz(self.root / "Acme/printer.ppd.gz", PPD_TEXT)

        run_phase("family_removal", self.build)

        self.assertEqual(self.retained(), ["Acme/PS/PS.ppd.gz", "Acme/printer.ppd.gz"])

    def test_decompression_gunzips_ppd_gz_inputs(self):
        self.write_gz(self.root / "Acme/printer.ppd.gz", PPD_TEXT)
        self.write_gz(self.root / "Acme/sub/other.ppd.gz", "*PPD-Adobe: 4.3\n")

        run_phase("decompression", self.build)

        self.assertEqual(self.retained(), ["Acme/printer.ppd", "Acme/sub/other.ppd"])
        self.assertEqual((self.root / "Acme/printer.ppd").read_text(encoding="ascii"), PPD_TEXT)
        after = inventory(self.root)
        self.assertEqual((after["ppd_files"], after["compressed_ppd_files"]), (2, 0))

    def test_non_ppd_removal_deletes_other_files_and_sets_mode_0644(self):
        manufacturer = self.root / "Acme"
        manufacturer.mkdir()
        (manufacturer / "printer.ppd").write_text(PPD_TEXT, encoding="ascii")
        (manufacturer / "printer.ppd").chmod(0o755)
        (manufacturer / "private.ppd").write_text(PPD_TEXT, encoding="ascii")
        (manufacturer / "private.ppd").chmod(0o600)
        (manufacturer / "ReadMe.htm").write_text("<p>notes</p>", encoding="ascii")
        (manufacturer / "broken.ppd.gz").write_bytes(b"not gzip")

        run_phase("non_ppd_removal_and_mode", self.build)

        self.assertEqual(self.retained(), ["Acme/printer.ppd", "Acme/private.ppd"])
        for name in ("printer.ppd", "private.ppd"):
            self.assertEqual((manufacturer / name).stat().st_mode & 0o7777, 0o644, name)

    def test_sanitization_applies_both_upstream_compatibility_corrections(self):
        ppd = self.root / "Acme/printer.ppd"
        ppd.parent.mkdir()
        ppd.write_text(
            "*CloseUI *Duplex\n*CloseUI: *InputSlot\n*1284DeviceId: MFG:Acme;\n"
            "*%*CloseUI comment\n",
            encoding="ascii",
        )

        run_phase("sanitization", self.build)

        self.assertEqual(
            ppd.read_text(encoding="ascii"),
            "*CloseUI: *Duplex\n*CloseUI: *InputSlot\n*1284DeviceID: MFG:Acme;\n"
            "*%*CloseUI comment\n",
        )

    def test_full_recipe_yields_sanitized_postscript_ppds_only(self):
        self.write_gz(self.root / "Acme/printer.ppd.gz", PPD_TEXT)
        self.write_gz(self.root / "Acme/PXL/pxl.ppd.gz", PPD_TEXT)
        (self.root / "Acme/ReadMe.htm").write_text("<p>notes</p>", encoding="ascii")

        for key, _, _ in PHASES:
            run_phase(key, self.build)

        self.assertEqual(self.retained(), ["Acme/printer.ppd"])
        ppd = self.root / "Acme/printer.ppd"
        self.assertEqual(
            ppd.read_text(encoding="ascii"),
            "*PPD-Adobe: 4.3\n*CloseUI: *Duplex\n*1284DeviceID: MFG:Acme;\n",
        )
        self.assertEqual(ppd.stat().st_mode & 0o7777, 0o644)


if __name__ == "__main__":
    unittest.main()
