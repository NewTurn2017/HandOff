#!/usr/bin/env python3
"""Mask common secret patterns in handoff markdown. Reads stdin, writes redacted markdown to stdout."""
import re
import sys

PATTERNS = [
    # API keys / tokens (long alphanumeric with common prefixes)
    (re.compile(r'(sk-[A-Za-z0-9_-]{20,})'), '[REDACTED_KEY]'),
    (re.compile(r'(pk_[A-Za-z0-9_-]{20,})'), '[REDACTED_KEY]'),
    (re.compile(r'(ghp_[A-Za-z0-9]{20,})'), '[REDACTED_GITHUB_TOKEN]'),
    (re.compile(r'(gho_[A-Za-z0-9]{20,})'), '[REDACTED_GITHUB_TOKEN]'),
    (re.compile(r'(xox[baprs]-[A-Za-z0-9-]{10,})'), '[REDACTED_SLACK_TOKEN]'),
    (re.compile(r'(AIza[0-9A-Za-z_-]{30,})'), '[REDACTED_GOOGLE_KEY]'),
    (re.compile(r'(AKIA[0-9A-Z]{16})'), '[REDACTED_AWS_KEY]'),
    # Bearer tokens
    (re.compile(r'(Bearer\s+)([A-Za-z0-9._\-]{20,})'), r'\1[REDACTED_BEARER]'),
    # Env-style assignments: KEY=value where value is long opaque string
    (re.compile(r'((?:^|[\s`"\'])[A-Z][A-Z0-9_]{2,}_(?:KEY|TOKEN|SECRET|PASSWORD|PWD)\s*=\s*)([^\s`"\']+)'), r'\1[REDACTED]'),
    # JWT-ish (three base64 parts)
    (re.compile(r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b'), '[REDACTED_JWT]'),
]


def main() -> int:
    text = sys.stdin.read()
    for pat, repl in PATTERNS:
        text = pat.sub(repl, text)
    sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
