import json
import pathlib
import subprocess
import unittest

HERE = pathlib.Path(__file__).parent
SCRIPT = HERE / "pem_to_jwk.py"
FIXTURE = HERE / "testdata" / "fixture.pub"

EXPECTED_KID = "Idfe4GNGXuhdv6-fYPVlFq8wDGtrQmEzOTE3e_s5iTw"
EXPECTED_E = "AQAB"
EXPECTED_N = (
    "sIK9_fVDcjlS8YOlzMTrTgZQnWC3ud4TIxW-U5AIrgb1E0MzEgp2Y3TlqDAz9Pbn"
    "als41iJoz6f0SpaKeJKVTCUknn85TmLFE8yUKva4eujLMJOU-P6qDW1zPyMwuUaF"
    "8bJ1vEStUFF2E6jeOtNi5oHMoZTyxNnm0E6mkk3-_YUtVdnFNbSIHFL-a9LcFDd9"
    "YJbLxexh87uiFLDOSZ7Ku2_tQxA2gIg9MSZjgmKELbgbZABQnsi_5lcyz9e1_bUj"
    "WkvmHGUan2OtxASXnQoai-3MC5Gtvv86gcu-wTCvUlW8zb1OqHUuE2Cm7K4nWWWn"
    "OMKhguV69DglghIWiBWdFw"
)


def run(pem: str) -> dict:
    out = subprocess.run(
        ["python3", str(SCRIPT)],
        input=json.dumps({"public_key_pem": pem}),
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(out.stdout)


class TestPemToJwk(unittest.TestCase):
    def setUp(self):
        self.result = run(FIXTURE.read_text())

    def test_kid_matches_kubernetes_derivation(self):
        # Kubernetes uses base64url(sha256(DER-encoded PKIX public key)).
        self.assertEqual(self.result["kid"], EXPECTED_KID)

    def test_modulus_is_base64url_without_padding(self):
        self.assertEqual(self.result["n"], EXPECTED_N)
        self.assertNotIn("=", self.result["n"])
        self.assertNotIn("+", self.result["n"])
        self.assertNotIn("/", self.result["n"])

    def test_exponent_is_65537(self):
        self.assertEqual(self.result["e"], EXPECTED_E)

    def test_all_values_are_strings(self):
        # data.external rejects non-string values.
        for key, value in self.result.items():
            self.assertIsInstance(value, str, f"{key} must be a string")


if __name__ == "__main__":
    unittest.main()
