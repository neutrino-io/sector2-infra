#!/usr/bin/env python3
"""Validate Railway TOML files against TOML 1.0 spec + Railway schema.

Run from repo root:
    python3 tests/validate-railway-toml.py
    python3 tests/validate-railway-toml.py path/to/some.toml

Exit code: 0 = valid, 1 = errors found.
"""
import sys
from pathlib import Path
import tomli


def load_with_null_support(path):
    """Load TOML. TOML 1.0 doesn't support null; Railway's parser is lenient
    but strict parsers (tomli, taplo) reject it. We strip `= null` lines so the
    file parses strictly, then warn the user that null is non-standard."""
    text = Path(path).read_text()
    text_stripped = "\n".join(
        line for line in text.splitlines() if not line.strip().endswith("= null")
    )
    try:
        data = tomli.loads(text)
        null_used = text != text_stripped
        if null_used:
            print(
                "  ⚠  WARNING: file uses `null` which is NOT valid TOML 1.0 "
                "(only TOML 1.1 draft). Use a sentinel integer instead."
            )
        return data
    except tomli.TOMLDecodeError as e:
        raise


def validate_railway_schema(data):
    errors = []
    services = data.get("services", [])
    if not services:
        errors.append("No [[services]] blocks found")
    for i, svc in enumerate(services):
        if "name" not in svc:
            errors.append(f"services[{i}] missing 'name'")
        if "dockerfilePath" in svc and "rootDirectory" not in svc:
            errors.append(
                f"services[{i}] '{svc.get('name')}': has dockerfilePath "
                "but no rootDirectory"
            )
        deploy = svc.get("deploy", {})
        if deploy:
            hcp = deploy.get("healthcheckPath")
            if hcp is not None and not isinstance(hcp, str):
                errors.append(
                    f"services[{i}].deploy.healthcheckPath must be string, "
                    f"got {type(hcp).__name__}"
                )
            hct = deploy.get("healthcheckTimeout")
            if hct is not None and not isinstance(hct, int):
                errors.append(
                    f"services[{i}].deploy.healthcheckTimeout must be int, "
                    f"got {type(hct).__name__}"
                )
            rpt = deploy.get("restartPolicyType")
            if rpt not in (None, "ALWAYS", "NEVER", "ON_FAILURE"):
                errors.append(
                    f"services[{i}].deploy.restartPolicyType '{rpt}' invalid"
                )
    return errors


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "railway.toml"
    print(f"Validating: {path}")
    try:
        data = load_with_null_support(path)
    except tomli.TOMLDecodeError as e:
        print(f"✗ TOML SYNTAX ERROR: {e}")
        sys.exit(1)
    print("✓ TOML syntax valid")
    print(f"  top-level keys: {list(data.keys())}")
    print(f"  services: {len(data.get('services', []))}")
    errors = validate_railway_schema(data)
    if errors:
        print(f"✗ Railway schema errors ({len(errors)}):")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    print("✓ Railway schema valid")
    for svc in data.get("services", []):
        deploy = svc.get("deploy", {})
        hcp = deploy.get("healthcheckPath", "(none)")
        hct = deploy.get("healthcheckTimeout", "(none)")
        print(f"  - {svc['name']}: healthcheckPath='{hcp}' timeout={hct}")


if __name__ == "__main__":
    main()
