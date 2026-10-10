#!/bin/zsh
# Writes a CycloneDX software bill of materials for Hark to build/hark-sbom.cdx.json, from Package.resolved.
# Hark has one third-party package, so the file is short on purpose.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
version=$(grep -E '^## [0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | head -1 | sed -E 's/^## ([0-9.]+).*/\1/')
python3 - "$version" <<'PY'
import json, sys, datetime, uuid
version = sys.argv[1]
resolved = json.load(open("Package.resolved"))
components = []
for pin in resolved["pins"]:
    state = pin["state"]
    location = pin["location"].removesuffix(".git")
    path = location.split("://", 1)[-1]
    ref = state.get("version") or state.get("revision", "")[:12]
    components.append({
        "type": "library",
        "bom-ref": f"pkg:swift/{path}@{ref}",
        "name": pin["identity"],
        "version": ref,
        "purl": f"pkg:swift/{path}@{ref}",
        "externalReferences": [{"type": "vcs", "url": pin["location"]}],
        "properties": [{"name": "revision", "value": state.get("revision", "")}],
    })
bom = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "serialNumber": f"urn:uuid:{uuid.uuid4()}",
    "version": 1,
    "metadata": {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "component": {"type": "application", "name": "Hark", "version": version, "bom-ref": f"hark@{version}",
                      "licenses": [{"license": {"id": "MIT"}}]},
    },
    "components": components,
    "dependencies": [{"ref": f"hark@{version}", "dependsOn": [c["bom-ref"] for c in components]}],
}
json.dump(bom, open("build/hark-sbom.cdx.json", "w"), indent=2)
print(f"wrote build/hark-sbom.cdx.json ({len(components)} third-party package(s), Hark {version})")
PY
