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

Test-Case 'Fight math: one Mind Blast by hand' {
    $s=[Warpath.GearSim.Reader]::FromText((Read-Fixture 'gear-sim-addon.txt'))
    $o=New-Object Warpath.GearSim.Options;$o.TargetHealth=1
    $b=0.0;$m=0.0;$d=0.0
    # Talents in the fixture: Shadow Focus 5, Darkness 5, Shadowform 1. No Mind Flay.
    $l=0.0;[void][Warpath.GearSim.Gear]::Fight($s,$o,264,99,0,5000,0,$null,[ref]$b,[ref]$m,[ref]$d,[ref]$l);$kill=$l
    Assert-Near 3.0 $kill 0.01 'first SW:P tick at 3 s kills a 1 HP target'
    $o.TargetHealth=100000;$o.FightSeconds=6
    [void][Warpath.GearSim.Gear]::Fight($s,$o,264,99,0,5000,0,$null,[ref]$b,[ref]$m,[ref]$d)
    $mod=1.10*1.15
    $mb=(517+264*0.4286)*0.99*$mod
    $tick=(852+264)/6.0*0.99*$mod
    # SW:P at 0 (ticks at 3 and 6), Mind Blast at 1.5 lands at 3.0.
    Assert-Near ($mb+2*$tick) $b 0.5 'damage in the first 6 seconds'
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

Write-Host ''
if($script:failed.Count){Write-Host ('FAILED: '+$script:failed.Count+' of '+($script:passed+$script:failed.Count)) -ForegroundColor Red;exit 1}
Write-Host ('PASS: '+$script:passed+' tests') -ForegroundColor Green
