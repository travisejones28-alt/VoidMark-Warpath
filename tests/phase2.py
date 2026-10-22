from pathlib import Path
root=Path(__file__).resolve().parents[1]
toc=(root/"VoidMarkWarpath.toc").read_text()
assert "## Interface: 11509" in toc
entries=[line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("##")]
assert all((root/p).is_file() for p in entries)
assert entries.index("Data/QuestAnchors.lua")<entries.index("Hotspots.lua")<entries.index("MapOverlay.lua")
anchors=(root/"Data/QuestAnchors.lua").read_text()
assert anchors.count('source="classic-1.12"')==8
overlay=(root/"MapOverlay.lua").read_text()
for safety in ['M:Clear()','OnHide','OnUpdate','Contact reference only','GetMapID']:
 assert safety in overlay
assert "GetPlayerMapPosition" not in overlay
print("PASS: Phase 2 static manifest, source and map lifecycle checks")

assert (root/"Data/ClassicEraObjectiveSamples.lua").exists()
samples=(root/"Data/ClassicEraObjectiveSamples.lua").read_text()
assert samples.count("quest=")==39
assert "WP.eraObjectiveSamples" in (root/"MapOverlay.lua").read_text()
