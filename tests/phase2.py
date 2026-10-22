from pathlib import Path
root=Path(__file__).resolve().parents[1]
toc=(root/"VoidMarkWarpath.toc").read_text()
files=[x.strip() for x in toc.splitlines() if x.strip() and not x.startswith("##")]
assert all((root/p).is_file() for p in files)
assert files.index("Data/QuestAnchors.lua")<files.index("Hotspots.lua")<files.index("MapOverlay.lua")
anchors=(root/"Data/QuestAnchors.lua").read_text()
assert anchors.count('source="classic-1.12"')==8
assert 'map=1433' in anchors and 'map=1431' in anchors
overlay=(root/"MapOverlay.lua").read_text()
assert 'self:Clear()' in overlay
assert 'Not verified in Forever' in overlay
assert 'GetPlayerMapPosition' not in overlay and 'SendWho' not in overlay
print("PASS: Phase 2 manifest, source and safety static checks")
