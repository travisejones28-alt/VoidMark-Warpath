# VoidMark Warpath Gear Sim tests. No dependencies: Windows PowerShell 5.1 or PowerShell 7.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\Sim-Tests.ps1
# Fixtures: gear-sim-addon.txt is written by the addon's own tests (VoidMark-Gear-Simulation
# Tests/run.lua), so both sides agree on the format; gear-sim-soulreaver.txt is a level 60
# Shadow Priest with real Classic item tooltips.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$fixtures=Join-Path $PSScriptRoot 'fixtures'
if(-not ('Warpath.GearSim.Reader' -as [type])) {
    $refs=if($PSVersionTable.PSEdition -eq 'Core'){@('System.Text.RegularExpressions','System.Linq','System.Collections','System.Runtime')}else{@('System.Core')}
    Add-Type -Path (Join-Path $repo 'Warpath.Sim.cs') -ReferencedAssemblies $refs
}
$script:passed=0;$script:failed=@()
function Assert-True($Condition,[string]$Message){if(-not $Condition){throw ('Assert failed: '+$Message)}}
function Assert-Equal($Expected,$Actual,[string]$Message){if($Expected -ne $Actual){throw ('Assert failed: '+$Message+' (expected '+$Expected+', got '+$Actual+')')}}
function Assert-Near([double]$Expected,[double]$Actual,[double]$Tolerance,[string]$Message){if([Math]::Abs($Expected-$Actual) -gt $Tolerance){throw ('Assert failed: '+$Message+' (expected '+$Expected+', got '+$Actual+')')}}
function Test-Case([string]$Name,[scriptblock]$Body) {
    try {& $Body;$script:passed++;Write-Host ('  ok    '+$Name) -ForegroundColor Green}
    catch {$script:failed+=$Name;Write-Host ('  FAIL  '+$Name+"`n        "+$_.Exception.Message+' @ line '+$_.InvocationInfo.ScriptLineNumber) -ForegroundColor Red}
}
function Read-Fixture([string]$Name){[IO.File]::ReadAllText((Join-Path $fixtures $Name),[Text.Encoding]::UTF8)}
function Get-Item2($Snap,[string]$Name){@($Snap.Items | Where-Object {$_.Name -eq $Name})[0]}

Test-Case 'Addon text parses: character, sheet, talents, worn and spare gear' {
    $s=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-addon.txt'))
    Assert-Equal 'Voidmark Soulreaver' $s.Name 'name'
    Assert-Equal 'PRIEST' $s.Class 'class'
    Assert-Equal 3747 $s.Health 'health'
    Assert-Equal 264 $s.SheetShadow 'shadow damage'
    Assert-Equal 5 $s.Talents['Shadow Focus'] 'talent rank'
    Assert-Equal 'Power Word: "Fortitude"' $s.Buffs[1] 'escaped quotes survive'
    $crown=Get-Item2 $s 'Devout Crown'
    Assert-Equal 1 $crown.Worn 'crown worn'
    Assert-Equal 13 $crown.Stats.Sta 'crown stamina from tooltip'
    Assert-Equal 'Devout Garb' $crown.SetName 'set name'
    Assert-Equal 23 ($crown.SetBonuses | Where-Object {$_.Count -eq 4}).Stats.Sp '4-piece bonus'
    $hat=Get-Item2 $s 'Crimson Felt Hat'
    Assert-Equal 2 $hat.Bags 'two hats in bags'
    Assert-Equal 30 $hat.Stats.Sp 'hat spell damage'
    $emblem=Get-Item2 $s 'Draconic Infused Emblem'
    Assert-Equal 100 $emblem.Use.Sp 'emblem on-use'
    Assert-Equal 15 $emblem.Use.Duration 'emblem duration'
    Assert-Equal 75 $emblem.Use.Cooldown 'emblem cooldown 1 min 15 sec'
    Assert-Equal 1 (Get-Item2 $s 'Dragonrider Boots').Bank 'bank boots'
}

Test-Case 'Damaged or cut-off text is refused with a plain message' {
    $text=Read-Fixture 'gear-sim-addon.txt'
    foreach($bad in @($text.Substring(0,$text.Length-40),($text -replace 'Crimson','Crimsun'),'hello')) {
        $threw=$false;try{[void][Warpath.GearSim.Reader]::FromText($bad)}catch{$threw=$true;Assert-True ($_.Exception.InnerException.Message -match 'cut off|changed|damaged|VoidMark Gear Sim') ('message: '+$_.Exception.InnerException.Message)}
        Assert-True $threw 'refused'
    }
}

Test-Case 'Tooltip lines: Classic wording, enchants, ratings, ignored lines' {
    $st=New-Object Warpath.GearSim.Stats
    foreach($l in @('Equip: Increases damage and healing done by magical spells and effects by up to 36.','+30 Spell Damage and Healing',
                    'Equip: Increases damage done by Shadow spells and effects by up to 20.','Stamina +7','+3 All Stats',
                    'Equip: Improves your chance to hit with spells by 1%.','Equip: Improves your chance to get a critical strike with spells by 2%.',
                    'Equip: Restores 6 mana per 5 sec.','71 Armor')) {Assert-True ([Warpath.GearSim.Reader]::LineStats($l,$st)) ('understood: '+$l)}
    Assert-Equal 66 $st.Sp 'spell damage'
    Assert-Equal 20 $st.ShadowSp 'shadow damage'
    Assert-Equal 10 $st.Sta 'stamina'
    Assert-Equal 3 $st.Int 'all stats'
    Assert-Equal 1 $st.Hit 'spell hit'
    Assert-Equal 2 $st.Crit 'spell crit'
    Assert-Equal 6 $st.Mp5 'mp5'
    Assert-Equal 71 $st.Armor 'armor'
    $none=New-Object Warpath.GearSim.Stats
    Assert-True (-not [Warpath.GearSim.Reader]::LineStats('Equip: Increases damage done to Undead by magical spells and effects by up to 48.',$none)) 'undead only'
    Assert-True (-not [Warpath.GearSim.Reader]::LineStats('Equip: Improves your chance to hit by 1%.',$none)) 'melee hit'
    Assert-Equal 0 ($none.Sp+$none.Hit) 'nothing added'
}

Test-Case 'Base stats: the current gear reproduces the character sheet exactly' {
    $s=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-soulreaver.txt'))
    $plan=[Warpath.GearSim.Gear]::Optimize($s,(New-Object Warpath.GearSim.Options),[string[]]@('Burst','Balanced','Tanky'))
    Assert-Near 264 $plan.Current.SpellDamage 0.01 'sheet shadow damage'
    Assert-Near 3747 $plan.Current.Health 0.01 'sheet health'
    Assert-Near 5200 $plan.Current.Mana 0.01 'sheet mana'
    Assert-True $plan.Searched 'every combination checked'
}

Test-Case 'Fight math (Forever numbers): first 6 seconds by hand' {
    $s=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-addon.txt'))
    $o=New-Object Warpath.GearSim.Options;$o.TargetHealth=1
    $b=0.0;$m=0.0;$d=0.0;$l=0.0
    # Talents in the fixture: Shadow Focus 5, Darkness 5, Shadowform 1. No Mind Flay.
    [void][Warpath.GearSim.Gear]::Fight($s,$o,264,99,0,5000,0,$null,[ref]$b,[ref]$m,[ref]$d,[ref]$l)
    Assert-Near 3.0 $l 0.01 'first SW:P tick at 3 s kills a 1 HP target'
    Assert-Near (470*0.5) $m 0.01 'only the SW:P cast was needed, at half cost in Shadowform'
    $o.TargetHealth=100000;$o.FightSeconds=6
    [void][Warpath.GearSim.Gear]::Fight($s,$o,264,99,0,5000,0,$null,[ref]$b,[ref]$m,[ref]$d,[ref]$l)
    $mod=1.10*1.10   # Darkness 5/5 and Shadowform
    $swp=(127+264*0.20)*0.99*$mod
    $dp=(106+264*0.10)*0.99*$mod
    $mb=(490+264*0.429)*0.99*$mod
    $swd=(458+264*0.429)*0.99*$mod
    # SW:P at 0 (ticks at 3 and 6), Devouring Plague at 1.5 (tick at 4.5), Mind Blast at 3.0 lands 4.5, SW:Death at 4.5.
    Assert-Near (2*$swp+$dp+$mb+$swd) $b 0.5 'damage in the first 6 seconds'
}

Test-Case 'Optimizer: keeps set bonuses, uses the Emblem, respects one copy and bank items' {
    $s=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-soulreaver.txt'))
    $plan=[Warpath.GearSim.Gear]::Optimize($s,(New-Object Warpath.GearSim.Options),[string[]]@('Burst','Balanced','Tanky'))
    $bal=$plan.Best['Balanced']
    Assert-True ($bal.Kill -lt $plan.Current.Kill) 'faster kill than now'
    Assert-True ($bal.Health -gt $plan.Current.Health) 'more health than now'
    $names=@($bal.Gear.Values | Where-Object {$_} | ForEach-Object {$_.Name})
    Assert-True ($names -contains 'Draconic Infused Emblem') 'emblem chosen'
    Assert-True ($names -notcontains 'Rune of the Dawn') 'undead-only trinket dropped'
    Assert-True ($names -contains 'Skyshroud Leggings') 'skyshroud'
    Assert-True (@($bal.ActiveSets | Where-Object {$_ -like 'Vestments of the Devout*'}).Count -eq 1) 'devout bonus kept'
    Assert-True ($plan.Best['Burst'].Kill -le $bal.Kill) 'burst kills fastest'
    Assert-True ($plan.Best['Tanky'].EffectiveHealth -ge $bal.EffectiveHealth) 'tanky survives longest'
    foreach($r in $plan.Best.Values){
        $rings=@($r.Gear['Ring1'],$r.Gear['Ring2'] | Where-Object {$_})
        if($rings.Count -eq 2){Assert-True ($rings[0].Link -ne $rings[1].Link) 'same single ring twice'}
        Assert-True ($null -eq ($r.Gear.Values | Where-Object {$_ -and -not $_.Usable})) 'only usable gear'
    }
    $swaps=[Warpath.GearSim.Gear]::Swaps($plan.Current.Gear,$bal.Gear)
    Assert-True (@($swaps | Where-Object {$_ -like 'Legs:*Skyshroud Leggings*(bags)*'}).Count -eq 1) 'swap line says where the item is'
}

Test-Case 'Priest limits: fishing pole and wrong armor are left out' {
    $s=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-soulreaver.txt'))
    Assert-True (-not (Get-Item2 $s "Nat Pagle's Extreme Angler FC-5000").Usable) 'fishing pole'
}

Test-Case 'Load from WoW: reads .export from SavedVariables (Lua escapes, UTF-8)' {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('gearsim-'+[guid]::NewGuid().ToString('N'))
    try {
        $addons=Join-Path $root 'Interface\AddOns';[IO.Directory]::CreateDirectory($addons)|Out-Null
        $sv=Join-Path $root 'WTF\Account\ACCOUNT1\SavedVariables';[IO.Directory]::CreateDirectory($sv)|Out-Null
        $text=Read-Fixture 'gear-sim-addon.txt'
        $lua=$text.Replace('\','\\').Replace('"','\"')
        [IO.File]::WriteAllText((Join-Path $sv 'VoidMarkGearSim.lua'),("VoidMarkGearSimDB = {`n[""chars""] = {`n[""Voidmark Soulreaver-Realm""] = {`n[""export""] = """+$lua+""",`n},`n},`n}`n"),(New-Object Text.UTF8Encoding($false)))
        $problems=New-Object 'System.Collections.Generic.List[string]'
        $found=[Warpath.GearSim.Reader]::FromGameFolder($addons,$problems)
        Assert-Equal 0 $problems.Count ('problems: '+($problems -join '; '))
        Assert-Equal 1 $found.Count 'one character'
        Assert-Equal 'Power Word: "Fortitude"' $found[0].Buffs[1] 'escapes'
        Assert-Equal 0 ([Warpath.GearSim.Reader]::FromGameFolder((Join-Path $root 'nope\x\y'),$problems)).Count 'missing folder'
    } finally {Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}

Test-Case 'Buffs are taken out: buffed and unbuffed copies give the same base numbers' {
    $clean=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-soulreaver.txt'))
    $buffed=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-buffed.txt'))
    Assert-Near $clean.Health $buffed.Health 0.5 'health'
    Assert-Near $clean.Mana $buffed.Mana 0.5 'mana'
    Assert-Near $clean.SheetShadow $buffed.SheetShadow 0.01 'shadow damage (Shadow Power removed)'
    Assert-Near $clean.SheetSta $buffed.SheetSta 0.01 'stamina (Fortitude removed)'
    Assert-Near $clean.SheetSpi $buffed.SheetSpi 0.01 'spirit (Divine Spirit removed)'
    Assert-True ($buffed.BuffsRemoved -contains 'Arcane Intellect') 'listed as removed'
    Assert-True ($buffed.BuffsUnknown -contains 'Mystery Charm') 'unknown buff listed'
    Assert-True ($buffed.BuffsUnknown -notcontains 'Shadowform') 'shadowform is modeled, not a stat buff'
    $notes=[Warpath.GearSim.Gear]::Notes($buffed)
    Assert-True (@($notes | Where-Object {$_ -like '*Mystery Charm*'}).Count -eq 1) 'note for unknown buff'
}

Test-Case 'All goals: Max Stamina has the most health, Static DPS the most boss DPS, Spell power the most spell damage' {
    $s=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-soulreaver.txt'))
    $modes=[string[]]([Warpath.GearSim.Gear]::PvpModes+[Warpath.GearSim.Gear]::RaidModes)
    $plan=[Warpath.GearSim.Gear]::Optimize($s,(New-Object Warpath.GearSim.Options),$modes)
    foreach($m in $modes){Assert-True $plan.Best.ContainsKey($m) ('result for '+$m)}
    $all=@($plan.Best.Values)+@($plan.Current)
    Assert-Equal (($all | Measure-Object Health -Maximum).Maximum) $plan.Best['Max Stamina'].Health 'max stamina'
    Assert-Near (($all | Measure-Object StaticDps -Maximum).Maximum) $plan.Best['Static DPS'].StaticDps 0.001 'static dps'
    Assert-Equal (($all | Measure-Object SpellDamage -Maximum).Maximum) $plan.Best['Spell power'].SpellDamage 'spell power'
    Assert-True ($plan.Best['Static DPS'].StaticDps -gt 150) ('boss dps is realistic: '+$plan.Best['Static DPS'].StaticDps)
    Assert-Near 88 $plan.Current.RaidHit 0.01 'boss hit: 83% base + 5% Shadow Focus (Forever: 1% a rank)'
}

Test-Case 'Healing-only lines count for Healing power, not spell damage' {
    $st=New-Object Warpath.GearSim.Stats
    Assert-True ([Warpath.GearSim.Reader]::LineStats('Equip: Increases healing done by spells and effects by up to 44.',$st)) 'healing line'
    Assert-True ([Warpath.GearSim.Reader]::LineStats('+24 Healing Spells',$st)) 'healing enchant'
    Assert-Equal 68 $st.Heal 'healing'
    Assert-Equal 0 $st.Sp 'not spell damage'
}

Test-Case 'Talent check: points, and what each modeled talent is worth' {
    $s=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-soulreaver.txt'))
    $o=New-Object Warpath.GearSim.Options
    $lines=[Warpath.GearSim.Talents]::Report($s,$o,[Warpath.GearSim.Gear]::Worn($s))
    Assert-True ($lines[0] -like 'TALENTS: 30 of 51 points spent*21 unspent*') $lines[0]
    Assert-True (@($lines | Where-Object {$_ -like '*Shadowform 1/1*worth*boss DPS*'}).Count -eq 1) 'shadowform value'
    Assert-True (@($lines | Where-Object {$_ -like '*Mental Strength 0/5*one more point*mana*'}).Count -eq 1) 'mental strength suggestion'
    Assert-Equal 5 $s.Talents['Darkness'] 'talents restored after the check'
}

Test-Case 'Wand damage per second is read from the wand tooltip' {
    $it=New-Object Warpath.GearSim.Item;$it.Loc='INVTYPE_RANGEDRIGHT'
    $lines=New-Object 'System.Collections.Generic.List[string]';$lines.Add('Ranged | Wand');$lines.Add('70 - 131 Shadow Damage | Speed 1.80');$lines.Add('(55.8 damage per second)')
    [Warpath.GearSim.Reader]::ParseLines($it,$lines,$null)
    Assert-Near 55.8 $it.Stats.WandDps 0.001 'wand dps'
    Assert-Equal 0 $it.NotCounted.Count 'nothing left over'
}

Test-Case 'Live Forever export: new tooltip wording, item auras and Dark Inspiration' {
    $s=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-forever-live.txt'))
    $robe=Get-Item2 $s 'Robes of the Exalted'
    Assert-Equal 13 $robe.Stats.Sp 'damage part of "healing 40 and damage 13"'
    Assert-Equal 27 $robe.Stats.Heal 'the extra healing'
    Assert-Near 1.0 (Get-Item2 $s 'Eye of the Beast').Stats.Crit 0.001 'decimal percent (1.0%)'
    Assert-Equal 72 (Get-Item2 $s 'Witchblade').Stats.Sp 'Forever Witchblade'
    Assert-True ($s.BuffsRemoved -contains 'Dark Inspiration') 'Dark Inspiration removed'
    Assert-True ($s.BuffsUnknown -notcontains 'Briarwood Reed') "the trinket's own aura isn't a buff"
    Assert-True (-not (Get-Item2 $s 'Fishing Pole').Usable) 'fishing pole'
    $notes=[Warpath.GearSim.Gear]::Notes($s)
    Assert-True (@($notes | Where-Object {$_ -like '*mount speed*'}).Count -eq 0) 'travel lines left out of notes'
    $plan=[Warpath.GearSim.Gear]::Optimize($s,(New-Object Warpath.GearSim.Options),[string[]]([Warpath.GearSim.Gear]::PvpModes+[Warpath.GearSim.Gear]::RaidModes))
    Assert-Near 307 $plan.Current.SpellDamage 0.01 'sheet shadow damage reproduced'
    Assert-Near 2867 $plan.Current.Health 0.01 'health without Warchief''s Blessing (3167 - 300)'
}

Write-Host ''
if($script:failed.Count){Write-Host ('FAILED: '+$script:failed.Count+' of '+($script:passed+$script:failed.Count)) -ForegroundColor Red;exit 1}
Write-Host ('PASS: '+$script:passed+' tests') -ForegroundColor Green
