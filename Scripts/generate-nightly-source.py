#!/usr/bin/env python3
"""Generate the nightly app source from the IPA being released (no network)."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
from urllib.parse import quote
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    with zipfile.ZipFile(args.ipa) as archive:
        plists = [name for name in archive.namelist()
                  if name.startswith("Payload/")
                  and name.endswith(".app/Info.plist")
                  and name.count("/") == 2]
        if len(plists) != 1:
            parser.error("IPA must contain exactly one top-level app Info.plist")
        info = plistlib.loads(archive.read(plists[0]))

    root = Path(__file__).resolve().parents[1]
    with (root / "entitlements.plist").open("rb") as file:
        entitlements = plistlib.load(file)

    repository = os.environ["GITHUB_REPOSITORY"]
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
    website = f"{server}/{repository}"
    sha = os.environ["GITHUB_SHA"]
    commit = sha[:7]
    headline = os.environ["COMMIT_SUBJECT"].strip()
    description = (
        f"Nightly build from [{commit}]({website}/commit/{sha}): {headline}\n\n"
        "This is a nightly release "
        "[created automatically with GitHub Actions workflow]"
        f"({os.environ['NIGHTLY_LINK']})."
    )
    date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    release_url = f"{website}/releases/download/nightly"
    download_url = f"{release_url}/{quote(args.ipa.name)}"
    json_url = f"{release_url}/source.json"
    # LiveExec32 has no standalone icon asset; use the repository owner's avatar.
    icon_url = f"{server}/{repository.split('/')[0]}.png"
    version = {
        "version": info["CFBundleShortVersionString"],
        "buildVersion": info["CFBundleVersion"],
        "date": date,
        "localizedDescription": description,
        "downloadURL": download_url,
        "size": args.ipa.stat().st_size,
        "minOSVersion": info["MinimumOSVersion"],
        "commit": commit,
        "headline": headline,
    }
    app = {
        "name": "LiveExec32 (nightly)",
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "LiveContainer Team",
        "localizedDescription": "Run 32-bit iOS applications on 64-bit devices.",
        "iconURL": icon_url,
        "category": "utilities",
        "appPermissions": {
            "entitlements": list(entitlements),
            "privacy": {key: value for key, value in info.items()
                        if "UsageDescription" in key},
        },
        "versions": [version],
        # Keep the legacy fields and LiveContainer's nightly commit metadata.
        "version": version["version"],
        "buildVersion": version["buildVersion"],
        "versionDate": date,
        "versionDescription": description,
        "downloadURL": download_url,
        "size": version["size"],
        "minOSVersion": version["minOSVersion"],
        "commit": commit,
        "headline": headline,
        # AltStore Classic and SideStore reject this as a notarized source.
        # A nonnumeric ID also blocks AltStore PAL. LiveContainer ignores it.
        "marketplaceID": "LiveContainer",
    }
    source = {
        "name": "LiveExec32 (nightly)",
        "identifier": "com.kdt.LiveExec32.source.nightly",
        "website": website,
        "iconURL": icon_url,
        "apps": [app],
        "news": [
            {
                "title": "LiveExec32",
                "identifier": "NeedLC",
                "tintColor": "FF0F0F",
                "caption": "Cannot use it here! This LiveExec32 repo is only meant to be installed in LiveContainer. Tap here to add it to LiveContainer.",
                "url": f"https://altdirect.app/?url={json_url}&r=livecontainer",
                "date": "2026-10-04T00:00",
                "notify": False
            },
        ],
    }
    args.output.write_text(json.dumps(source, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
