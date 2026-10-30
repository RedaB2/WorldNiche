#!/usr/bin/env python3
"""Check WorldNiche's static release configuration without printing credentials.

This does not contact any service or certify App Store/privacy compliance. A zero
exit status only means the inspected local configuration passed these checks.
"""

from __future__ import annotations

import argparse
import base64
import ipaddress
import json
import plistlib
import re
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit
from xml.parsers.expat import ExpatError


FIELDS = ("serviceURL", "publicAPIKey", "invitationHost", "privacyPolicyURL", "supportURL")
PLACEHOLDER = re.compile(r"(?:your[-_ ]?(?:project|domain|host|key|team)|replace[-_ ]?me|changeme|placeholder|<[^>]+>|\[(?:YOUR|INSERT|REPLACE|TEAM|HOST|DOMAIN|BUNDLE)[^\]]*\]|\$\([^)]*\))", re.I)
TEAM_ID = re.compile(r"[A-Z0-9]{10}\Z")
DOMAIN = re.compile(r"(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?\Z", re.I)


def public_host(host: str) -> bool:
    if not DOMAIN.fullmatch(host) or PLACEHOLDER.search(host):
        return False
    host = host.lower().rstrip(".")
    if host in {"localhost", "example.com", "example.net", "example.org"}:
        return False
    if any(host.endswith("." + ending) for ending in ("localhost", "local", "test", "invalid", "example", "example.com", "example.net", "example.org")):
        return False
    try:
        ipaddress.ip_address(host)
        return False  # Release hostnames must support owned HTTPS domain configuration.
    except ValueError:
        return True


def valid_https_url(value: str, *, service: bool = False) -> bool:
    try:
        url = urlsplit(value)
        return bool(
            value == value.strip()
            and not re.search(r"\s", value)
            and not PLACEHOLDER.search(value)
            and url.scheme == "https"
            and public_host(url.hostname or "")
            and url.username is None
            and url.password is None
            and url.port in (None, 443)
            and not url.fragment
            and (not service or (url.path in ("", "/") and not url.query))
        )
    except (ValueError, UnicodeError):
        return False


def public_key_problem(value: str) -> str | None:
    """Inspect only key type/claims; never put the value in an error message."""
    if value != value.strip() or PLACEHOLDER.search(value):
        return "publicAPIKey contains placeholder or whitespace; use the project's public publishable key."
    if value.startswith("sb_secret_"):
        return "publicAPIKey is a secret key. Remove it from the client and rotate it if it was distributed."
    if value.startswith("sb_publishable_"):
        if re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]{20,}", value):
            return None
        return "publicAPIKey has an invalid publishable-key format."
    parts = value.split(".")
    if len(parts) == 3 and all(re.fullmatch(r"[A-Za-z0-9_-]+", part) for part in parts):
        try:
            header = json.loads(base64.urlsafe_b64decode(parts[0] + "=" * (-len(parts[0]) % 4)))
            payload = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
        except (ValueError, UnicodeError):
            return "publicAPIKey is not a readable legacy Supabase public token."
        if not isinstance(header, dict) or not isinstance(payload, dict):
            return "publicAPIKey has invalid legacy token claims."
        if payload.get("role") == "service_role":
            return "publicAPIKey is a privileged service-role token. Remove it from the client and rotate it if distributed."
        if payload.get("role") != "anon" or header.get("alg") != "HS256":
            return "publicAPIKey must be a publishable key or a legacy Supabase token with role anon."
        expiry = payload.get("exp")
        if isinstance(expiry, bool) or not isinstance(expiry, (int, float)) or expiry <= time.time():
            return "publicAPIKey is a legacy token with missing or expired expiry."
        return None
    return "publicAPIKey must be a Supabase public publishable key or legacy anon key; arbitrary/secret keys are rejected."


def setting_values(path: Path, name: str) -> set[str]:
    if not path.is_file():
        return set()
    # These project settings are deliberately literal. Build-variable indirection
    # needs a resolved release configuration; it must not silently pass this gate.
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    values = set()
    for line in text.splitlines():
        line = line.split("//", 1)[0]
        match = re.search(r"\b" + re.escape(name) + r"\s*=\s*([^;\n]+)", line)
        if match:
            value = match.group(1).strip().strip('"')
            if value:
                values.add(value)
    return values


def release_setting(root: Path, name: str) -> str | None:
    shared = root / "Config/Shared.xcconfig"
    paths = [root / "Config/Release.xcconfig"]
    if shared.is_file() and re.search(r'^\s*#include\??\s+"Signing\.local\.xcconfig"', shared.read_text(), re.M):
        paths.append(root / "Config/Signing.local.xcconfig")
    paths.extend((shared, root / "WorldNiche.xcodeproj/project.pbxproj"))
    for path in paths:
        values = setting_values(path, name)
        if values:
            return next(iter(values)) if len(values) == 1 else None
    return None


def supports_invites(detail: dict) -> bool:
    paths = detail.get("paths", [])
    if isinstance(paths, list) and "/invite/*" in paths:
        return True
    components = detail.get("components", [])
    return isinstance(components, list) and any(
        isinstance(item, dict)
        and item.get("/") == "/invite/*"
        and item.get("exclude") is not True
        and "?" not in item and "#" not in item
        for item in components
    )


def check(root: Path, aasa_path: Path) -> tuple[list[str], list[str]]:
    blockers: list[str] = []
    notes: list[str] = []
    local = root / "WorldNiche/Resources/SocialConfiguration.local.json"
    path = local if local.exists() else root / "WorldNiche/Resources/SocialConfiguration.json"
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(config, dict):
            raise ValueError("not a dictionary")
    except (OSError, ValueError, UnicodeError):
        config = {}
        blockers.append(f"{path.name} is missing or invalid JSON. Restore its five configuration fields.")
    for field in FIELDS:
        value = config.get(field)
        if not isinstance(value, str) or not value.strip():
            blockers.append(f"SocialConfiguration.{field} is blank or not a string. Configure its production value.")
    for field in ("serviceURL", "privacyPolicyURL", "supportURL"):
        value = config.get(field)
        if isinstance(value, str) and value.strip() and not valid_https_url(value, service=field == "serviceURL"):
            blockers.append(f"SocialConfiguration.{field} must be an owned/configured public HTTPS URL without credentials, placeholders, or unsafe hostnames" + (" and with no path/query." if field == "serviceURL" else "."))
    host = config.get("invitationHost")
    host_valid = isinstance(host, str) and public_host(host)
    if isinstance(host, str) and host.strip() and not host_valid:
        blockers.append("SocialConfiguration.invitationHost must be a real public hostname only, without a scheme, path, port, wildcard, or placeholder.")
    key = config.get("publicAPIKey")
    if isinstance(key, str) and key.strip():
        problem = public_key_problem(key)
        if problem:
            blockers.append(problem)

    team = release_setting(root, "DEVELOPMENT_TEAM")
    team_valid = bool(team and TEAM_ID.fullmatch(team) and not PLACEHOLDER.search(team) and team not in {"ABCDEFGHIJ", "XXXXXXXXXX", "0123456789", "TEAMIDHERE"})
    if not team_valid:
        blockers.append("DEVELOPMENT_TEAM is missing, ambiguous, or a placeholder. Configure the actual 10-character Apple team ID for Release.")
    bundle = release_setting(root, "PRODUCT_BUNDLE_IDENTIFIER")
    bundle_valid = bool(bundle and re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle) and not PLACEHOLDER.search(bundle) and not bundle.startswith(("com.example.", "com.mycompany.")))
    if not bundle_valid:
        blockers.append("PRODUCT_BUNDLE_IDENTIFIER is missing, ambiguous, or a placeholder. Configure the registered application identifier.")

    try:
        with (root / "Config/WorldNiche.entitlements").open("rb") as stream:
            entitlements = plistlib.load(stream)
        domains = entitlements.get("com.apple.developer.associated-domains", [])
        if not isinstance(domains, list):
            raise ValueError("not an array")
    except (OSError, ValueError, TypeError, AttributeError, ExpatError):
        domains = []
        blockers.append("WorldNiche.entitlements is missing or invalid. Configure a valid Associated Domains entitlement.")
    if not host_valid or f"applinks:{host}" not in domains:
        blockers.append("Associated Domains lacks an exact production applinks entry for invitationHost. Add it to Config/WorldNiche.entitlements and the signed provisioning profile.")

    try:
        raw = aasa_path.read_text(encoding="utf-8")
        aasa = json.loads(raw)
        details = aasa.get("applinks", {}).get("details", [])
        if not isinstance(details, list) or PLACEHOLDER.search(raw):
            raise ValueError("invalid details or placeholder")
    except (OSError, ValueError, UnicodeError, AttributeError):
        details = []
        blockers.append("AASA file is missing, invalid, or contains placeholders. Generate apps/web/invite-site/.well-known/apple-app-site-association using real host, team, bundle ID, and App Store URL values (or pass --aasa).")
    if details:
        app_id = f"{team}.{bundle}"
        matching = [item for item in details if isinstance(item, dict) and (item.get("appID") == app_id or (isinstance(item.get("appIDs"), list) and app_id in item["appIDs"]))]
        if not team_valid or not bundle_valid or not matching:
            blockers.append("AASA does not match the configured Release team ID and bundle identifier.")
        elif not any(supports_invites(item) for item in matching):
            blockers.append("AASA needs an enabled /invite/* route for this app without query/fragment conditions.")
    elif aasa_path.exists():
        blockers.append("AASA has no valid applinks.details application entries.")

    notes.append("Static checks do not verify key signatures, service deployment, domain ownership, HTTPS reachability, email delivery, or the final signed archive.")
    notes.append("Before release, deploy and test RLS, moderation/report handling, account deletion, invitation revocation, and two-account access; verify hosted AASA without redirects and the real device universal-link flow.")
    notes.append("Publish reviewed privacy/support pages, reconcile actual retention and App Store privacy answers, and review the current App Store requirements. Passing this script is not App Store approval.")
    return blockers, notes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help="WorldNiche project root")
    parser.add_argument("--aasa", type=Path, help="Generated AASA file; defaults to apps/web/invite-site/.well-known/apple-app-site-association")
    args = parser.parse_args()
    root = args.root.resolve()
    aasa = args.aasa.resolve() if args.aasa else root.parents[1] / "apps/web/invite-site/.well-known/apple-app-site-association"
    blockers, notes = check(root, aasa)
    print("WorldNiche static release configuration: " + (f"BLOCKED ({len(blockers)})" if blockers else "PASS"))
    for blocker in blockers:
        print("BLOCKER: " + blocker)
    for note in notes:
        print("NOTE: " + note)
    return 1 if blockers else 0


if __name__ == "__main__":
    sys.exit(main())
