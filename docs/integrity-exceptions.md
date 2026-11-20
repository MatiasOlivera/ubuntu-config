# Integrity exceptions

This register records setup tools that remain installable despite lacking
publisher-provided integrity material, or where a verified install would drop
setup the tool needs to work. It documents why the verified path is unavailable
or unsuitable, why automatic installation remains useful, and the risk accepted
for each exception. The general integrity standard remains in
[`0003-remote-installer-integrity.md`](decisions/0003-remote-installer-integrity.md).

## Entries

| Application | Version reviewed | Checked on | Why a verified install is unavailable | Upstream request |
| --- | --- | --- | --- | --- |
| Cursor CLI | `2026.11.19-f005e9d` | 2026-11-19 | Cursor's official installer downloads and extracts a versioned archive without a publisher checksum or signature. | [Cursor forum request](https://forum.cursor.com/t/publish-integrity-metadata-for-cursor-cli-releases/178866) |
| Ollama | unpinned — the installer fetches the current release; `OLLAMA_VERSION` is the upstream pin knob | 2026-11-20 | Upstream publishes `sha256sum.txt` for release assets, but `ollama.com/install.sh` does not consume it. A verified-artifact install would replace upstream GPU detection, ROCm/JetPack bundle selection, NVIDIA driver setup and systemd configuration with a partial reimplementation. Accepts unverified installer execution and downloads. | None filed; re-evaluate if the official installer starts verifying the published checksums |

Automatic installation is retained when a tool is part of the configured
workstation and installing it during setup keeps the fresh-machine environment
complete. These exceptions mean setup may execute or install content without an
independent integrity check; a compromise of the publisher or delivery path
could result in malicious code running with the setup user's privileges.

## Updating the register

Add one row for each accepted exception. Record the application version and date
examined, keep the reason and accepted risk specific to that application, and
link the upstream request when it has been filed. Update the version and date
when the publisher's delivery or integrity material is re-evaluated.
