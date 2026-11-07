import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


class UriFileTests(unittest.TestCase):
    def run_decoder(self, value, *args):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "key.uri"
            path.write_bytes(value)
            return subprocess.run(
                [sys.executable, os.environ["PKCS11_URI_FROM_FILE"], *args, str(path)],
                text=True,
                capture_output=True,
                check=False,
            )

    def test_uri(self):
        result = self.run_decoder(b"pkcs11:token=signing;id=%01;type=private\n")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "pkcs11:token=signing;id=%01;type=private\n")

    def test_xml_attribute(self):
        result = self.run_decoder(
            b"pkcs11:token=signing;id=%01?pin-source=file:/run/a&b\n", "--xml"
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("a&amp;b", result.stdout)

    def test_rejects_multiple_uris(self):
        result = self.run_decoder(b"pkcs11:token=a\npkcs11:token=b\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_rejects_pem_pointer(self):
        result = self.run_decoder(
            b"-----BEGIN PKCS#11 PROVIDER URI-----\nZm9v\n-----END PKCS#11 PROVIDER URI-----\n"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
