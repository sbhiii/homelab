#!/usr/bin/env python3
"""Derive a Kubernetes-compatible JWK from an RSA public key in PEM form.

Reads {"public_key_pem": "..."} on stdin, writes {"kid","n","e"} on stdout.
Pure stdlib so it runs wherever terraform runs.
"""
import base64
import hashlib
import json
import sys


def _b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _der_from_pem(pem: str) -> bytes:
    body = "".join(l for l in pem.strip().splitlines() if not l.startswith("-----"))
    return base64.b64decode(body)


def _read_tlv(der: bytes, i: int):
    """Return (tag, value_bytes, next_index) for the DER element at i."""
    tag = der[i]
    i += 1
    n = der[i]
    i += 1
    if n & 0x80:
        k = n & 0x7F
        n = int.from_bytes(der[i:i + k], "big")
        i += k
    return tag, der[i:i + n], i + n


def rsa_params(der: bytes):
    """Pull (modulus, exponent) out of a SubjectPublicKeyInfo DER blob."""
    _, spki, _ = _read_tlv(der, 0)            # outer SEQUENCE
    _, _, j = _read_tlv(spki, 0)              # AlgorithmIdentifier, skipped
    _, bitstring, _ = _read_tlv(spki, j)      # BIT STRING
    inner = bitstring[1:]                     # drop unused-bits octet
    _, rsa_seq, _ = _read_tlv(inner, 0)       # RSAPublicKey SEQUENCE
    _, modulus, k = _read_tlv(rsa_seq, 0)
    _, exponent, _ = _read_tlv(rsa_seq, k)
    return modulus.lstrip(b"\x00"), exponent.lstrip(b"\x00")


def jwk(pem: str) -> dict:
    der = _der_from_pem(pem)
    n, e = rsa_params(der)
    return {
        "kid": _b64u(hashlib.sha256(der).digest()),
        "n": _b64u(n),
        "e": _b64u(e),
    }


if __name__ == "__main__":
    print(json.dumps(jwk(json.load(sys.stdin)["public_key_pem"])))
