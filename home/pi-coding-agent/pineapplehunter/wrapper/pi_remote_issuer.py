"""Host-only Pi Remote client certificate issuer."""
import asyncio
import datetime
import json
import re
import sys
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

MAX_CSR = 16 * 1024
BUS = "io.github.pineapplehunter.PiRemoteCA1"
PATH = "/io/github/pineapplehunter/PiRemoteCA1"


def issue(csr_pem: bytes, cert_path: Path, key_path: Path) -> tuple[str, str]:
    if len(csr_pem) > MAX_CSR:
        raise ValueError("CSR exceeds size limit")
    if not re.fullmatch(rb"\s*-----BEGIN CERTIFICATE REQUEST-----\s+[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE REQUEST-----\s*", csr_pem):
        raise ValueError("expected exactly one PEM CSR")
    csr = x509.load_pem_x509_csr(csr_pem)
    if not csr.is_signature_valid:
        raise ValueError("invalid CSR signature")
    pub = csr.public_key()
    if not isinstance(pub, ec.EllipticCurvePublicKey) or not isinstance(pub.curve, ec.SECP256R1):
        raise ValueError("CSR must contain an ECDSA P-256 public key")
    cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
    key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
    now = datetime.datetime.now(datetime.timezone.utc)
    if now < cert.not_valid_before_utc or now >= cert.not_valid_after_utc:
        raise ValueError("intermediate is not currently valid")
    try:
        bc = cert.extensions.get_extension_for_class(x509.BasicConstraints).value
        ku = cert.extensions.get_extension_for_class(x509.KeyUsage).value
        if not bc.ca or bc.path_length != 0 or not ku.key_cert_sign:
            raise ValueError("intermediate is not a signing CA")
    except x509.ExtensionNotFound as e:
        raise ValueError("intermediate lacks CA signing extensions") from e
    if key.public_key().public_numbers() != cert.public_key().public_numbers():
        raise ValueError("intermediate key does not match certificate")
    start = max(now - datetime.timedelta(minutes=1), cert.not_valid_before_utc)
    end = min(start + datetime.timedelta(hours=24), cert.not_valid_after_utc)
    if end <= now:
        raise ValueError("intermediate expires too soon")
    builder = (x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Pi Remote process")]))
        .issuer_name(cert.subject).public_key(pub).serial_number(x509.random_serial_number())
        .not_valid_before(start).not_valid_after(end)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CLIENT_AUTH]), critical=False)
        .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False, key_encipherment=False, data_encipherment=False, key_agreement=False, key_cert_sign=False, crl_sign=False, encipher_only=None, decipher_only=None), critical=True))
    leaf = builder.sign(key, hashes.SHA256())
    return (leaf.public_bytes(serialization.Encoding.PEM).decode(), cert.public_bytes(serialization.Encoding.PEM).decode())


def main():
    if sys.argv[1:] == ["--dbus"]:
        asyncio.run(serve())
        return
    if sys.argv[1:]:
        print("usage: pi-remote-issue-certificate < request.pem", file=sys.stderr)
        raise SystemExit(2)
    try:
        csr = sys.stdin.buffer.read(MAX_CSR + 1)
        if len(csr) > MAX_CSR:
            raise ValueError("CSR exceeds size limit")
        leaf, intermediate = asyncio.run(request(csr.decode("ascii")))
        print(json.dumps({"leafPEM": leaf, "intermediatePEM": intermediate}, separators=(",", ":")))
    except (OSError, ValueError, RuntimeError, TimeoutError):
        print("pi-remote-issue-certificate: issuance failed; check the host D-Bus service", file=sys.stderr)
        raise SystemExit(1)


async def request(csr_pem: str):
    from dbus_next import Message, MessageType
    from dbus_next.aio import MessageBus

    # The container's bus proxy allows this exact method, not introspection.
    bus = await MessageBus().connect()
    try:
        reply = await asyncio.wait_for(bus.call(Message(
            destination=BUS, path=PATH, interface=BUS, member="IssueClientCertificate",
            signature="s", body=[csr_pem],
        )), timeout=8)
        if reply is None or reply.message_type != MessageType.METHOD_RETURN or reply.signature != "ss":
            raise RuntimeError("Host issuer did not return a certificate chain")
        return reply.body
    finally:
        bus.disconnect()
        await bus.wait_for_disconnect()


async def serve():
    from dbus_next.aio import MessageBus
    from dbus_next.service import ServiceInterface, method
    from dbus_next import DBusError, NameFlag, RequestNameReply

    directory = Path.home() / ".config/pi-remote/issuer"

    class Issuer(ServiceInterface):
        def __init__(self):
            super().__init__(BUS)

        @method()
        def IssueClientCertificate(self, csrPEM: 's') -> 'ss':
            try:
                leaf, intermediate = issue(
                    csrPEM.encode(), directory / "intermediate.pem", directory / "intermediate-key.pem",
                )
                return [leaf, intermediate]
            except (ValueError, OSError):
                raise DBusError(f"{BUS}.IssueFailed", "CSR or host issuer configuration rejected") from None

    bus = await MessageBus().connect()
    bus.export(PATH, Issuer())
    reply = await bus.request_name(BUS, NameFlag.DO_NOT_QUEUE)
    if reply not in (RequestNameReply.PRIMARY_OWNER, RequestNameReply.ALREADY_OWNER):
        raise RuntimeError("Could not acquire Pi Remote issuer bus name")
    await bus.wait_for_disconnect()


if __name__ == '__main__':
    main()
