# Previously skipped games: approved-source audit

Checked September 26, 2026, using only [Legacy Store](https://legacystore.app/)
and the [updated IPA Archive](https://stuffed18.github.io/ipa-archive-updated/).

The earlier reports excluded a game when its issue supplied a separate IPA
link. The user has now asked to find those games through the approved catalogs.
This audit follows catalog entries, not the issue-provided download links.
Some catalog entries ultimately point to the same Internet Archive collection;
Internet Archive is the hosting destination, not an additional discovery source.

## Results

All 13 previously skipped titles have entries in the approved catalogs. Legacy
Store lists installable ARM32 copies for 12 titles, including alternative
versions of Cling Thing. Tiny Death Star is downloadable through IPA Archive.
Every selected download below returned HTTP 200 after redirects in a HEAD check.
This establishes source availability, **not LiveExec32 compatibility**.

Installation, crash debugging, and retests are tracked separately in the
[September 26 game follow-up](issue-game-followup-2026-09-26.md).
Its crash-only continuation excludes Doodle Truck and Mini Car Champion's
rendering/touch reports. It also downloaded and installed app bundles for
Jumping Finn Turbo 1.1.1 (52262) and Hero of Sparta 1.30 (60348): ZIP checks,
catalog SHA-1, and unencrypted ARM32 checks passed for both. LC generated their
metadata on first launch. Finn reached its menu; Sparta remained alive at a
blank intro. These are not full gameplay results.

| Report | Game | Version found | Approved catalog / selected download | Qualification |
| --- | --- | --- | --- | --- |
| [#58](https://github.com/LiveContainer/LiveExec32/issues/58) | Family Guy: Uncensored | **1.1.1** | [Catalog](https://legacystore.app/app/329676142), [copy 17368](https://legacystore.app/ipa/17368) | Exact reported version; ARMv6/ARMv7; 17.0 MiB. |
| [#57](https://github.com/LiveContainer/LiveExec32/issues/57) | Prince of Persia: Warrior Within HD | **1.0.0** | [Catalog](https://legacystore.app/app/391501565), [copy 41032](https://legacystore.app/ipa/41032) | Exact reported version and HD/iPad bundle `com.gameloft.POPiPad`; ARMv7; 657.3 MiB. Not the non-HD edition. |
| [#56](https://github.com/LiveContainer/LiveExec32/issues/56) | Doodle Truck | **1.7.8** | [Catalog](https://legacystore.app/app/390127968), [copy 105500](https://legacystore.app/ipa/105500) | Issue does not state a version; ARMv7; 12.7 MiB. Touch/rendering report, not a crash. |
| [#55](https://github.com/LiveContainer/LiveExec32/issues/55) | Jumping Finn Turbo | **1.1.1** | [Catalog](https://legacystore.app/app/555641530), [copy 52262](https://legacystore.app/ipa/52262) | Exact reported version; ARMv7; 49.8 MiB. Catalog also has 1.1.2. |
| [#54](https://github.com/LiveContainer/LiveExec32/issues/54), [#52](https://github.com/LiveContainer/LiveExec32/issues/52) | Hero of Sparta | **1.30**, **1.06** | [Catalog](https://legacystore.app/app/299093633), [1.30 copy 60348](https://legacystore.app/ipa/60348), [1.06 copy 27090](https://legacystore.app/ipa/27090) | 1.30 matches the stuck-video report (126.4 MiB); 1.06 matches the earlier audio-symbol report (86.2 MiB). Keep the two cases distinct. |
| [#54](https://github.com/LiveContainer/LiveExec32/issues/54) | Hero of Sparta II | **1.0.2** | [Catalog](https://legacystore.app/app/360166129), [copy 5532](https://legacystore.app/ipa/5532) | Exact reported version; ARMv6; 325.5 MiB. Separate game from Hero of Sparta. |
| [#42](https://github.com/LiveContainer/LiveExec32/issues/42) | Super Monkey Ball | **1.3** | [Catalog](https://legacystore.app/app/281966695), [copy 28142](https://legacystore.app/ipa/28142) | Exact reported version; ARMv6; 36.2 MiB. |
| [#41](https://github.com/LiveContainer/LiveExec32/issues/41) | Crash Bandicoot Nitro Kart 3D | **1.7.7** | [Catalog](https://legacystore.app/app/285005463), [copy 17357](https://legacystore.app/ipa/17357) | Bundle matches `com.vgmobile.cnk2`; issue does not state a version. ARMv6; 10.6 MiB. Catalog also has 1.0. |
| [#36](https://github.com/LiveContainer/LiveExec32/issues/36) | Boomlings | **1.43** | [Catalog](https://legacystore.app/app/23078), [copy 70193](https://legacystore.app/ipa/70193) | Exact reported version; ARMv7; 17.2 MiB. |
| [#25](https://github.com/LiveContainer/LiveExec32/issues/25) | Star Wars: Tiny Death Star | **1.4.2** (build **1.4.3019**) | [IPA Archive bundle search](https://stuffed18.github.io/ipa-archive-updated/#bundleid=com.lucasarts.tinydeathstar), entry **9404** | Issue does not state a version. Archive also lists 1.0 and 1.4.1. Legacy Store's 1.4.1 entry has an empty copies list, so it cannot supply this download. |
| [#22](https://github.com/LiveContainer/LiveExec32/issues/22) | Cling Thing | **1.1** (build **58**) or **1.2** (build **65**) | [Catalog](https://legacystore.app/app/644211512), [1.1 copy 74105](https://legacystore.app/ipa/74105), [1.2 copy 153805](https://legacystore.app/ipa/153805) | **Reported 1.1.1 not found in either catalog.** Both alternatives are installable ARMv7/ARMv7s copies (44.9 / 47.4 MiB), but neither is an exact-version reproduction. |
| [#11](https://github.com/LiveContainer/LiveExec32/issues/11) | Where's My XiYangYang? / Where's My Water? Featuring XYY | **1.0** | [Catalog](https://legacystore.app/app/650120267), [copy 42657](https://legacystore.app/ipa/42657) | Matches `com.disney.wheresmyxyy`, not the separate China bundle; ARMv7; 49.6 MiB. |
| [#37](https://github.com/LiveContainer/LiveExec32/issues/37) | Mini Car Champion / Minicar | **1.0** | [Catalog](https://legacystore.app/app/43090), [copy 157640](https://legacystore.app/ipa/157640) | Matches `com.spilgames.minicarchampion`; ARMv6/ARMv7; 36.8 MiB. Rendering report, not part of the original crash count. |

## Version and verification limits

- The reported-version search covered the full Legacy Store version lists and
  IPA Archive's current `data/ipa.json`, with bundle IDs used to disambiguate
  editions. Cling Thing's available versions are 1.0, 1.0.1, 1.1, and 1.2; no
  entry for 1.1.1 was found.
- `installable` and architecture labels above are Legacy Store metadata, not
  installation or launch results from this pass. A successful HEAD request
  does not validate ZIP integrity, executable encryption state, or game assets.
- Tiny Death Star 1.4.2 was additionally downloaded from IPA Archive entry 9404:
  ZIP integrity passed, the 73,803,700-byte IPA's MD5 matched the filename
  (`4d5d77c5757a493758545efe40a09b16`), and its actual bundle metadata confirmed
  `com.lucasarts.tinydeathstar`, version 1.4.2, build 1.4.3019. Both ARMv7 and
  ARMv7s slices have `cryptid 0`; their original SDK is 7.1 and minimum OS is 6.0.
  This is a verified unencrypted ARM32 candidate, not a successful LC launch.
- Do not count an alternative-version test as reproducing the issue's exact
  binary. In particular, retain the Cling Thing 1.1.1 mismatch in later reports.
- No runtime source changes or fixes are claimed by this source audit. No Mac
  keyboard/mouse input or network/VPN setting changes were used.

## Evidence

Local, ignored metadata and HTTP headers are under
`tmp/game-followup-20260926/`: `issues.json`, `catalog-*.json`,
`archive-ipa.json`, `archive-urls.json`, and `probe-*.headers`.
The catalog copy IDs above identify the selected binaries for future downloads;
the metadata snapshots also contain their expected sizes and SHA-1 hashes.

Previous source exclusions remain historical observations in the
[September 18 triage](issue-game-triage-2026-09-18.md) and
[September 22 follow-up](issue-game-followup-2026-09-22.md).
