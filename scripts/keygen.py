#!/usr/bin/env python3
"""Generate a Pro license code for a buyer's e-mail address.

Usage: scripts/keygen.py buyer@example.com
Reads the secret from source/Di2Secret.mc (local only, not in git).
"""
import hashlib, pathlib, re, sys

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = pathlib.Path(__file__).resolve().parent.parent / "source" / "Di2Secret.mc"
    m = re.search(r'SECRET\s*=\s*"([^"]*)"', src.read_text())
    if not m:
        sys.exit("No SECRET found in source/Di2Secret.mc")
    email = sys.argv[1].strip().lower()
    d = hashlib.sha256((m.group(1) + "|" + email).encode("utf-8")).digest()
    v = int.from_bytes(d[:5], "big")
    code = "".join(ALPHABET[(v >> (i * 5)) & 0x1F] for i in range(7, -1, -1))
    print(f"{email}  {code[:4]}-{code[4:]}")

if __name__ == "__main__":
    main()
