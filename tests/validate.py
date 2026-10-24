from pathlib import Path
import re, subprocess, os, sys
root=Path(__file__).resolve().parents[1]
toc=(root/"VoidMarkWarpath.toc").read_text()
assert "## Interface: 11509" in toc
assert "## SavedVariables: VoidMarkWarpathDB" in toc
assert "## SavedVariablesPerCharacter: VoidMarkWarpathCharDB" in toc
assert not re.search(r"^## (RequiredDeps|Dependencies):",toc,re.M)
entries=[s.strip() for s in toc.splitlines() if s.strip() and not s.startswith("##")]
assert len(entries)==len(set(entries))
assert all((root/p).is_file() for p in entries)
assert entries.index("Data/AuditedEra.lua")<entries.index("Hotspots.lua")<entries.index("MapOverlay.lua")
assert entries[-1]=="Boot.lua"
assert 'WP.version = "0.2.15"' in (root/"Core.lua").read_text()
assert "## Version: 0.2.15" in toc
# Recount historical data rather than treating the old report as ground truth.
cells=(root/"Data/QuestCells.lua").read_text()
packs=[cells.split(z+"=[=[",1)[1].split("]=]",1)[0].split(",") for z in ("redridge","duskwood")]
assert [len(p) for p in packs]==[186,245]
assert [sum(int(t[-2:],16) for t in p) for p in packs]==[1062,950]
assert sum(len({int(t[:-4],36) for t in p}) for p in packs)==39
assert not any(p in entries for p in ["Data/QuestCells.lua","Data/QuestAreaCoverage.lua","Data/ClassicEraObjectives.lua"])
lua=os.environ.get("LUA","lua")
# Compile all shipped Lua files, including archived data and importer.
subprocess.run([lua,'tests/syntax.lua',*[str(p) for p in root.rglob('*.lua')]],check=True,cwd=root)
subprocess.run([lua,"tests/runtime.lua"],check=True,cwd=root)
print("PASS: syntax, manifests, standalone runtime, version consistency, historical 2012/431/39 recount")
