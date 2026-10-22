from pathlib import Path
root=Path(__file__).resolve().parents[1]
toc=(root/"VoidMarkWarpath.toc").read_text()
assert "## Interface: 16001" in toc
assert "## SavedVariables: VoidMarkWarpathDB" in toc
assert "## SavedVariablesPerCharacter: VoidMarkWarpathCharDB" in toc
entries=[s.strip() for s in toc.splitlines() if s.strip() and not s.startswith("##")]
assert entries == ["Core.lua","Data/Zones.lua","Data/Models.lua","Storage.lua","Observations.lua","UI.lua","Boot.lua"]
for entry in entries:
    assert (root/entry).is_file(), entry
allcode="\n".join((root/x).read_text() for x in entries)
for item in ["redridge","duskwood","hillsbrad","wetlands","stranglethorn","arathi"]:
    assert item in (root/"Data/Zones.lua").read_text()
for name in ["objective","hotspot","sighting","route","zone"]:
    assert name in (root/"Data/Models.lua").read_text()
assert "WP.schema = 1" in allcode
assert "version>WP.schema" in allcode
assert "/warpath" in allcode and "/vmwarpath" in allcode
assert "ADDON_LOADED" in allcode
assert "GetPlayerMapPosition" not in allcode
assert "SendWho" not in allcode
print("PASS: phase 1 manifest, modules, zones, schemas, and API guard checks")
