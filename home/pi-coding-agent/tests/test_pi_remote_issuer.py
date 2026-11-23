import datetime
import sys
import tempfile
import unittest
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "pineapplehunter/wrapper"))
from pi_remote_issuer import issue


class IssuerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.key = ec.generate_private_key(ec.SECP256R1())
        self.ca_key = ec.generate_private_key(ec.SECP256R1())
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "host issuer")])
        now = datetime.datetime.now(datetime.timezone.utc)
        cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                .public_key(self.ca_key.public_key()).serial_number(1)
                .not_valid_before(now - datetime.timedelta(days=1))
                .not_valid_after(now + datetime.timedelta(days=2))
                .add_extension(x509.BasicConstraints(ca=True, path_length=0), True)
                .add_extension(x509.KeyUsage(False, False, False, False, False, True, True, None, None), True)
                .sign(self.ca_key, hashes.SHA256()))
        self.cert_path = self.directory / "intermediate.pem"
        self.key_path = self.directory / "key.pem"
        self.cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
        self.key_path.write_bytes(self.ca_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        self.csr = (x509.CertificateSigningRequestBuilder().subject_name(name)
                    .sign(self.key, hashes.SHA256()).public_bytes(serialization.Encoding.PEM))

    def test_issues_fixed_client_leaf(self):
        leaf_pem, intermediate_pem = issue(self.csr, self.cert_path, self.key_path)
        leaf = x509.load_pem_x509_certificate(leaf_pem.encode())
        self.assertEqual(leaf.public_key().public_numbers(), self.key.public_key().public_numbers())
        self.assertEqual(leaf.extensions.get_extension_for_class(x509.BasicConstraints).value.ca, False)
        self.assertEqual(leaf.extensions.get_extension_for_class(x509.ExtendedKeyUsage).value, x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.CLIENT_AUTH]))
        self.assertIn(b"BEGIN CERTIFICATE", intermediate_pem.encode())
        self.assertLessEqual(leaf.not_valid_after_utc - leaf.not_valid_before_utc, datetime.timedelta(hours=24))

    def test_rejects_extra_pem_block_and_oversized_input(self):
        for csr in (self.csr + self.csr, b"x" * 16385):
            with self.assertRaises(ValueError):
                issue(csr, self.cert_path, self.key_path)


if __name__ == "__main__":
    unittest.main()
