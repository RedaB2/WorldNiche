#!/usr/bin/env python3
"""Build invitation site and AASA only from explicitly supplied deployment values."""
import argparse
import html
import json
from pathlib import Path
import re
import shutil
from urllib.parse import urlparse


def build(host, team, bundle, app_store_url, output):
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", host) or "." not in host or any(not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label) for label in host.split(".")):
        raise ValueError("Supply only the owned invitation hostname, without a scheme or path.")
    if any(x in host for x in ("example", "localhost", "placeholder", "your-")) or host.endswith((".test", ".invalid", ".local")):
        raise ValueError("A real owned domain is required; placeholders cannot be deployed.")
    if not re.fullmatch(r"[A-Z0-9]{10}", team) or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle):
        raise ValueError("Supply the actual Apple team ID and application bundle identifier.")
    if app_store_url:
        url = urlparse(app_store_url)
        if url.scheme != "https" or url.hostname != "apps.apple.com" or not re.search(r"/id[0-9]+(?:/|$)", url.path) or url.username or url.password:
            raise ValueError("Supply the real HTTPS App Store listing URL, or omit it while the app is in testing.")
    source = Path(__file__).resolve().parents[2] / "apps/web/invite-site"
    if output.resolve() == source.resolve():
        raise ValueError("Use a separate output directory so the source template remains reusable.")
    output.mkdir(parents=True, exist_ok=True)
    for name in ("index.html", "style.css", "invite.js", "_headers", "_redirects"):
        shutil.copyfile(source / name, output / name)
    if app_store_url:
        install_action = f'<a id="get-app" class="install" href="{html.escape(app_store_url, quote=True)}">Get WorldNiche for iPhone</a><p class="install-note">After installing, return to this invitation and tap Open in WorldNiche.</p>'
    else:
        install_action = '<div class="install"><p>WorldNiche is in early access.</p><p class="install-note">Already have the app? Open your friend’s invitation on your iPhone. Otherwise, ask them for access to the test build, then return to this link.</p></div>'
    markup = (output / "index.html").read_text().replace("__INSTALL_ACTION__", install_action)
    (output / "index.html").write_text(markup)
    app_assets = Path(__file__).resolve().parents[2] / "apps/ios/WorldNiche/Assets.xcassets/AppLogo.imageset"
    shutil.copyfile(app_assets / "AppLogo.png", output / "logo.png")
    shutil.copyfile(app_assets / "AppLogo-dark.png", output / "logo-dark.png")
    association = {"applinks": {"details": [{"appIDs": [f"{team}.{bundle}"], "components": [{"/": "/invite/*", "comment": "WorldNiche friend invitations only"}]}]}}
    wellknown = output / ".well-known"
    wellknown.mkdir(exist_ok=True)
    (wellknown / "apple-app-site-association").write_text(json.dumps(association, indent=2) + "\n")
    (output / "DEPLOYMENT.txt").write_text(f"Host: {host}\nServe AASA with HTTPS, application/json, HTTP200 and no redirects.\nConfigure the app entitlement: applinks:{host}\nThe fallback /invite/* route must serve index.html with HTTP200.\nDisable request-path logging or redact invitation tokens in all hosting/CDN logs.\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--app-store-url", default="")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        build(args.host, args.team_id, args.bundle_id, args.app_store_url, args.output)
    except ValueError as error:
        parser.error(str(error))
    print("Invitation site and AASA generated; verify domain ownership and HTTPS hosting before enabling links.")
