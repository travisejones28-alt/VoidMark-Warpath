from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
toc=(root/"VoidMarkWarpath.toc").read_text()
assert "## Interface: 11509" in toc
entries=[line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("##")]
assert all((root/p).is_file() for p in entries)
assert entries.index("Data/ClassicEraObjectiveSamples.lua") < entries.index("Data/ClassicEraObjectives.lua") < entries.index("Hotspots.lua") < entries.index("MapOverlay.lua")
source=(root/"Data/ClassicEraObjectives.lua").read_text()
packed=re.search(r"local encoded = \[=\[(.*?)\]=\]",source,re.S)
assert packed, "encoded quest objectives missing"
records=[line for line in packed.group(1).splitlines() if line.strip()]
assert len(records)==115
counts={"r":0,"d":0}
quests=set()
for line in records:
    zone,quest,entity,coords=line.split("|")
    assert zone in counts and quest.isdigit() and (entity.isdigit() or entity.startswith("o") and entity[1:].isdigit())
    quests.add((zone,int(quest)))
    for pair in coords.split(","):
        assert len(pair)==8 and pair.isdigit()
        x,y=int(pair[:4]),int(pair[4:])
        assert 0<=x<=10000 and 0<=y<=10000
        counts[zone]+=1
assert counts=={"r":152,"d":156}, counts
assert len(quests)==39
assert 'level=info and info.level or nil' in source
hot=(root/"Hotspots.lua").read_text()
assert "Unknown quest levels" in hot and "cell.entities[dedupe]" in hot
overlay=(root/"MapOverlay.lua").read_text()
for fragment in ["M:Clear()","OnHide","OnUpdate","GetMapID","WP.eraObjectives","Quest-associated spawn"]:
    assert fragment in overlay
assert "GetPlayerMapPosition" not in overlay
print("PASS: 308 coordinates, 39 quests, load order, unknown levels, overlay safety")

assert "Data/EraCorridors.lua" in entries
assert entries.index("Data/EraCorridors.lua") < entries.index("MapOverlay.lua")
assert (root/"Data/EraCorridors.lua").read_text().count('kind="quest-contact-connection"')==2
assert "DrawCorridors" in overlay and "type(canvas.CreateLine)" in overlay

assert "freeLines" in overlay and "table.remove(self.freeLines)" in overlay
assert 'toggle("Connections","showRoutes"' in (root/"UI.lua").read_text()

mini=(root/"MinimapButton.lua").read_text()
assert 'local dragDriver=CreateFrame("Frame",nil,b)' in mini
assert 'dragDriver:Hide()' in mini
assert 'b:HookScript("OnUpdate"' in mini
assert 'self:SetScript("OnUpdate",nil)' not in mini

coverage=(root/"Data/QuestAreaCoverage.lua").read_text()
assert coverage.count('zone="redridge"')==6
assert "1,062" in coverage
assert 'toggle("Quest areas","showAreaCoverage"' in (root/"UI.lua").read_text()
assert "WP.questAreaCoverage" in overlay

full=(root/"Data/FullCoverage.lua").read_text()
assert "WP.eraFullCoverage" in full and "QuestieDB Vanilla 1.0.6" in full
assert "WP.eraFullCoverage and" in hot and "questCount" in hot
assert entries.index("Data/FullCoverage.lua") < entries.index("Hotspots.lua")

questcells=(root/"Data/QuestCells.lua").read_text()
assert "WP.eraQuestCells" in questcells and "level=info.level" in questcells
assert entries.index("Data/QuestCells.lua") < entries.index("Hotspots.lua")
assert "WP.eraQuestCells and" in hot and "self:LevelOverlap(p,low,high)" in hot
packs=[questcells.split(zone+"=[=[",1)[1].split("]=]",1)[0] for zone in ("redridge","duskwood")]
assert [len(p.split(",")) for p in packs]==[186,245]
assert [sum(int(t[-2:],16) for t in p.split(",")) for p in packs]==[1062,950]
