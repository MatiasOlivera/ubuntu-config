# Install and integrity exceptions

This register records setup tools that stay on a lower install-method rung or
without publisher-provided integrity material when every higher or verified
path is unavailable or unsuitable. It documents why the preferred path is
unavailable, why automatic installation remains useful, and the risk accepted
for each exception. The install-method ladder is in
[`0008-install-method-priority.md`](decisions/0008-install-method-priority.md);
the integrity standards remain in
[`0003-remote-installer-integrity.md`](decisions/0003-remote-installer-integrity.md)
and
[`0007-artifact-integrity-source-priority.md`](decisions/0007-artifact-integrity-source-priority.md).

## Entries

| Application | Version reviewed | Checked on | Exception | Why the preferred path is unavailable or unsuitable | Reference |
| --- | --- | --- | --- | --- | --- |
| Cursor CLI | `2026.11.19-f005e9d` | 2026-11-19 | Integrity | Cursor's official installer downloads and extracts a versioned archive without a publisher checksum or signature. | [Cursor forum request](https://forum.cursor.com/t/publish-integrity-metadata-for-cursor-cli-releases/178866) |
| Ollama | unpinned — the installer fetches the current release; `OLLAMA_VERSION` is the upstream pin knob | 2026-11-20 | Integrity | Upstream publishes `sha256sum.txt` for release assets, but `ollama.com/install.sh` does not consume it. A verified-artifact install would replace upstream GPU detection, ROCm/JetPack bundle selection, NVIDIA driver setup and systemd configuration with a partial reimplementation. Accepts unverified installer execution and downloads. | [Upstream request](https://github.com/ollama/ollama/issues/19787) |

Automatic installation is retained when a tool is part of the configured
workstation and installing it during setup keeps the fresh-machine environment
complete. An integrity exception means setup may execute or install content
without an independent integrity check; an install-method exception means a
tool stays below the preferred rung. Both accept risk: a compromise of the
publisher or delivery path could result in malicious code running with the
setup user's privileges, and updates may follow a path this repo does not run.

## Updating the register

Add one row for each accepted exception, name its kind (integrity or install
method), record the application version and date examined, keep the reason and
accepted risk specific to that application, and link the upstream request or
tracking issue when one exists. Update the version and date when the publisher's
delivery, integrity material or available install methods are re-evaluated.
