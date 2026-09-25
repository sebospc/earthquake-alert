#!/usr/bin/env python3
"""Integrity for the backup: AES-CBC (openssl enc) has none, so a truncated or corrupted
archive would decrypt to garbage or half a tar. pack prepends the plaintext's sha256; open
checks it and writes the tar.gz only if it matches.

    ... | envelope.py pack | openssl enc ...
    openssl enc -d ... | envelope.py open > backup.tar.gz     (exit 1, no output, on mismatch)
"""
import hashlib, sys

MAGIC = b"AEA-BACKUP v1 sha256="


def pack(payload):
    return MAGIC + hashlib.sha256(payload).hexdigest().encode() + b"\n" + payload


def open_envelope(data):
    header, separator, payload = data.partition(b"\n")
    if not separator or not header.startswith(MAGIC):
        raise ValueError("not an aea backup (wrong passphrase?)")
    if hashlib.sha256(payload).hexdigest().encode() != header[len(MAGIC):]:
        raise ValueError("backup corrupted or truncated: sha256 mismatch")
    return payload


if __name__ == "__main__":
    data = sys.stdin.buffer.read()
    try:
        result = pack(data) if sys.argv[1] == "pack" else open_envelope(data)
    except ValueError as error:
        sys.exit(f"BACKUP_INVALID: {error}")
    sys.stdout.buffer.write(result)
