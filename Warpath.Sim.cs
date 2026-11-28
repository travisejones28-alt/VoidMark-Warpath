// VoidMark Warpath gear sim engine (no UI). Reads the VoidMark Gear Sim addon's
// text (pasted, or the .export saved in VoidMarkGearSim.lua), works out each
// item's stats from its tooltip text, simulates a Shadow Priest PvP fight and
// ranks every gear combination the character owns.
// Written for the C# 5 compiler that ships with Windows PowerShell 5.1.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Warpath.GearSim {
    // ------------------------------------------------------------------ JSON
    public static class Json {
        public static object Parse(string s) { int i = 0; object v = Value(s, ref i); Skip(s, ref i); if (i != s.Length) throw new FormatException("Extra text after the data."); return v; }
        static void Skip(string s, ref int i) { while (i < s.Length && char.IsWhiteSpace(s[i])) i++; }
        static object Value(string s, ref int i) {
            Skip(s, ref i);
            if (i >= s.Length) throw new FormatException("The data ends early.");
            char c = s[i];
            if (c == '{') {
                var d = new Dictionary<string, object>(); i++; Skip(s, ref i);
                if (i < s.Length && s[i] == '}') { i++; return d; }
                while (true) {
                    Skip(s, ref i); string k = Str(s, ref i); Skip(s, ref i);
                    if (i >= s.Length || s[i] != ':') throw new FormatException("Expected ':'.");
                    i++; d[k] = Value(s, ref i); Skip(s, ref i);
                    if (i < s.Length && s[i] == ',') { i++; continue; }
                    if (i < s.Length && s[i] == '}') { i++; return d; }
                    throw new FormatException("Expected ',' or '}'.");
                }
            }
            if (c == '[') {
                var l = new List<object>(); i++; Skip(s, ref i);
                if (i < s.Length && s[i] == ']') { i++; return l; }
                while (true) {
                    l.Add(Value(s, ref i)); Skip(s, ref i);
                    if (i < s.Length && s[i] == ',') { i++; continue; }
                    if (i < s.Length && s[i] == ']') { i++; return l; }
                    throw new FormatException("Expected ',' or ']'.");
                }
            }
            if (c == '"') return Str(s, ref i);
            if (s.Length - i >= 4 && s.Substring(i, 4) == "true") { i += 4; return true; }
            if (s.Length - i >= 5 && s.Substring(i, 5) == "false") { i += 5; return false; }
            if (s.Length - i >= 4 && s.Substring(i, 4) == "null") { i += 4; return null; }
            int start = i;
            while (i < s.Length && "+-0123456789.eE".IndexOf(s[i]) >= 0) i++;
            if (start == i) throw new FormatException("Unexpected character.");
            return double.Parse(s.Substring(start, i - start), CultureInfo.InvariantCulture);
        }
        static string Str(string s, ref int i) {
            if (i >= s.Length || s[i] != '"') throw new FormatException("Expected text.");
            i++; var b = new StringBuilder();
            while (i < s.Length) {
                char c = s[i++];
                if (c == '"') return b.ToString();
                if (c != '\\') { b.Append(c); continue; }
                if (i >= s.Length) break;
                char e = s[i++];
                switch (e) {
                    case 'n': b.Append('\n'); break; case 'r': b.Append('\r'); break; case 't': b.Append('\t'); break;
                    case 'b': b.Append('\b'); break; case 'f': b.Append('\f'); break;
                    case 'u': b.Append((char)int.Parse(s.Substring(i, 4), NumberStyles.HexNumber)); i += 4; break;
                    default: b.Append(e); break;
                }
            }
            throw new FormatException("Text never ends.");
        }
        public static Dictionary<string, object> Obj(object o, string k) { var d = o as Dictionary<string, object>; object v; return d != null && d.TryGetValue(k, out v) ? v as Dictionary<string, object> : null; }
        public static List<object> Arr(object o, string k) { var d = o as Dictionary<string, object>; object v; return d != null && d.TryGetValue(k, out v) ? v as List<object> : null; }
        public static string Txt(object o, string k) { var d = o as Dictionary<string, object>; object v; return d != null && d.TryGetValue(k, out v) ? v as string : null; }
        public static double Num(object o, string k, double fallback) {
            var d = o as Dictionary<string, object>; object v;
            if (d != null && d.TryGetValue(k, out v) && v is double) return (double)v;
            return fallback;
        }
    }

    // ------------------------------------------------------------- Stats
    public class Stats {
        public double Sp, ShadowSp, Sta, Int, Spi, Hit, Crit, Armor, Mp5;
        public void Add(Stats o) { Sp += o.Sp; ShadowSp += o.ShadowSp; Sta += o.Sta; Int += o.Int; Spi += o.Spi; Hit += o.Hit; Crit += o.Crit; Armor += o.Armor; Mp5 += o.Mp5; }
        public void Sub(Stats o) { Sp -= o.Sp; ShadowSp -= o.ShadowSp; Sta -= o.Sta; Int -= o.Int; Spi -= o.Spi; Hit -= o.Hit; Crit -= o.Crit; Armor -= o.Armor; Mp5 -= o.Mp5; }
        public Stats Copy() { var s = new Stats(); s.Add(this); return s; }
        public bool AtLeast(Stats o) { return Sp + ShadowSp >= o.Sp + o.ShadowSp && Sta >= o.Sta && Int >= o.Int && Spi >= o.Spi && Hit >= o.Hit && Crit >= o.Crit && Armor >= o.Armor && Mp5 >= o.Mp5; }
    }
    public class OnUse { public double Sp, Duration, Cooldown; }
    public class SetBonus { public int Count; public Stats Stats = new Stats(); public string Text; }

    public class Item {
        public string Link, Name, Loc, Slot, Type, SetName;
        public int Id, ReqLevel, Worn, Bags, Bank;
        public bool Unique, Usable = true;
        public string WhyNot = "";
        public Stats Stats = new Stats();
        public OnUse Use;
        public List<SetBonus> SetBonuses = new List<SetBonus>();
        public List<string> NotCounted = new List<string>();
        public string ClassList;
        public int Owned { get { return Worn + Bags + Bank; } }
        public string Where { get { return Worn > 0 ? "worn" : (Bags > 0 ? "bags" : "bank"); } }
    }

    public class Snapshot {
        public string Name, Realm, Class, Race;
        public int Level;
        public double At, BankAt;
        public double Health, Mana, SheetShadow, SheetHit, SheetCrit, SheetArmor, SheetSta, SheetInt, SheetSpi, Regen;
        public Dictionary<string, int> Talents = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        public List<string> Buffs = new List<string>();
        public List<Item> Items = new List<Item>();
        public Dictionary<int, string> Slots = new Dictionary<int, string>();
        public int Pending;
        public string Label { get { return Name + " (" + Realm + ")"; } }
    }

    // ------------------------------------------------------------ Parsing
    public static class Reader {
        public const string Header = "VMGS1:";
        static readonly RegexOptions I = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
        static readonly Regex SpLine = new Regex(@"(?:damage and healing done by magical spells and effects by up to|increases spell power by|spell damage by up to) (\d+)(?!.*\bfor \d+ sec)", I);
        static readonly Regex ShadowLine = new Regex(@"damage done by shadow spells and effects by up to (\d+)", I);
        static readonly Regex PlusSp = new Regex(@"^\+(\d+) (?:spell damage(?: and healing)?|spell power|damage and healing spells|healing and spell damage)\.?$", I);
        static readonly Regex SpPlus = new Regex(@"^(?:spell damage|spell power|spell damage and healing) \+(\d+)\.?$", I);
        static readonly Regex PlusShadow = new Regex(@"^\+(\d+) shadow (?:spell )?damage\.?$", I);
        static readonly Regex PlusStat = new Regex(@"^\+(\d+) (stamina|intellect|spirit|strength|agility|all stats)\.?$", I);
        static readonly Regex StatPlus = new Regex(@"^(stamina|intellect|spirit|strength|agility|all stats) \+(\d+)\.?$", I);
        static readonly Regex SpellHit = new Regex(@"chance to hit with spells by (\d+)%", I);
        static readonly Regex SpellHitRating = new Regex(@"spell hit rating by (\d+)", I);
        static readonly Regex SpellCrit = new Regex(@"critical strike with spells by (\d+)%", I);
        static readonly Regex SpellCritRating = new Regex(@"spell critical strike rating by (\d+)", I);
        static readonly Regex ArmorLine = new Regex(@"^(\d+) armor$", I);
        static readonly Regex PlusArmor = new Regex(@"^\+(\d+) armor\.?$", I);
        static readonly Regex Mp5 = new Regex(@"restores (\d+) mana per 5 sec", I);
        static readonly Regex PlusMp5 = new Regex(@"^\+?(\d+) mana (?:every|per) 5 sec", I);
        static readonly Regex UseSp = new Regex(@"^use: .*?(?:magical spells and effects by up to|spell power by) (\d+) for (\d+) sec", I);
        static readonly Regex Cooldown = new Regex(@"\((?:(\d+) min)?,? ?(?:(\d+) sec)? ?cooldown\)", I);
        static readonly Regex SetName = new Regex(@"^(.+) \((\d+)/(\d+)\)$", I);
        static readonly Regex SetLine = new Regex(@"^\((\d+)\) set ?: (.+)$", I);
        static readonly Regex ReqLevel = new Regex(@"^requires level (\d+)$", I);
        static readonly Regex Classes = new Regex(@"^classes: (.+)$", I);
        static readonly Regex Ignore = new Regex(@"\bundead\b|\bdemons\b|healing done by spells|\bwhen struck\b|chance on hit|chance of|\bfishing\b|\bmount\b|\briding\b|run speed|resistance", I);

        // Text pasted from the game, or the .export saved in the addon file.
        public static Snapshot FromText(string text) {
            if (text == null) throw new FormatException("Nothing was pasted.");
            text = text.Trim();
            int start = text.IndexOf(Header, StringComparison.Ordinal);
            if (start < 0) throw new FormatException("That isn't VoidMark Gear Sim text. In game, click Sim on your character window (or type /vmsim) and copy the box.");
            text = text.Substring(start + Header.Length);
            int a = text.IndexOf(':'), b = a < 0 ? -1 : text.IndexOf(':', a + 1);
            if (a < 0 || b < 0) throw new FormatException("The pasted text is cut off.");
            int length;
            if (!int.TryParse(text.Substring(0, a), NumberStyles.Integer, CultureInfo.InvariantCulture, out length)) throw new FormatException("The pasted text is damaged.");
            string sum = text.Substring(a + 1, b - a - 1).ToLowerInvariant();
            string json = text.Substring(b + 1);
            byte[] bytes = Encoding.UTF8.GetBytes(json);
            if (bytes.Length < length) throw new FormatException("The pasted text is cut off. Select all of it in game (Select all) and copy again.");
            if (bytes.Length > length) { json = Encoding.UTF8.GetString(bytes, 0, length); bytes = Encoding.UTF8.GetBytes(json); }
            if (Adler32(bytes) != sum) throw new FormatException("The pasted text was changed or damaged. Copy it again from the game.");
            return FromJson(Json.Parse(json));
        }

        public static string Adler32(byte[] data) {
            uint a = 1, b = 0;
            foreach (byte x in data) { a = (a + x) % 65521; b = (b + a) % 65521; }
            return ((b << 16) | a).ToString("x8");
        }

        public static Snapshot FromJson(object root) {
            var s = new Snapshot();
            s.Name = Json.Txt(root, "name") ?? "?"; s.Realm = Json.Txt(root, "realm") ?? "?";
            s.Class = Json.Txt(root, "class") ?? ""; s.Race = Json.Txt(root, "race") ?? "";
            s.Level = (int)Json.Num(root, "level", 60); s.At = Json.Num(root, "at", 0); s.BankAt = Json.Num(root, "bankAt", 0);
            s.Pending = (int)Json.Num(root, "pending", 0);
            var st = Json.Obj(root, "stats");
            s.Health = Json.Num(st, "health", 0); s.Mana = Json.Num(st, "mana", 0);
            var sd = Json.Obj(st, "spellDamage"); s.SheetShadow = Json.Num(sd, "shadow", 0);
            var sc = Json.Obj(st, "spellCrit"); s.SheetCrit = Json.Num(sc, "shadow", 0);
            s.SheetHit = Json.Num(st, "spellHit", 0); s.SheetArmor = Json.Num(st, "armor", 0);
            s.SheetSta = Json.Num(Json.Obj(st, "stamina"), "total", 0); s.SheetInt = Json.Num(Json.Obj(st, "intellect"), "total", 0);
            s.SheetSpi = Json.Num(Json.Obj(st, "spirit"), "total", 0);
            s.Regen = Json.Num(Json.Obj(st, "regen"), "casting", 0);
            var buffs = Json.Arr(root, "buffs"); if (buffs != null) foreach (var x in buffs) { var t = x as string; if (t != null) s.Buffs.Add(t); }
            var tabs = Json.Arr(root, "talents");
            if (tabs != null) foreach (var tab in tabs) {
                var list = Json.Arr(tab, "list"); if (list == null) continue;
                foreach (var t in list) { var n = Json.Txt(t, "n"); if (n != null) s.Talents[n] = (int)Json.Num(t, "r", 0); }
            }
            var slots = Json.Obj(root, "slots");
            if (slots != null) foreach (var kv in slots) { int slot; if (int.TryParse(kv.Key, out slot) && kv.Value is string) s.Slots[slot] = (string)kv.Value; }
            var items = Json.Arr(root, "items");
            if (items != null) foreach (var o in items) {
                var it = new Item();
                it.Link = Json.Txt(o, "link") ?? ""; it.Name = Json.Txt(o, "name") ?? "?"; it.Loc = Json.Txt(o, "loc") ?? "";
                it.Id = (int)Json.Num(o, "id", 0); it.ReqLevel = (int)Json.Num(o, "req", 0);
                var where = Json.Obj(o, "where");
                it.Worn = (int)Json.Num(where, "worn", 0); it.Bags = (int)Json.Num(where, "bags", 0); it.Bank = (int)Json.Num(where, "bank", 0);
                var lines = new List<string>();
                var ls = Json.Arr(o, "lines"); if (ls != null) foreach (var l in ls) { var t = l as string; if (t != null) lines.Add(t); }
                ParseLines(it, lines, Json.Obj(o, "stats"));
                it.Slot = SlotOf(it.Loc);
                s.Items.Add(it);
            }
            Gear.CheckUsable(s);
            return s;
        }

        public static string SlotOf(string loc) {
            switch (loc) {
                case "INVTYPE_HEAD": return "Head"; case "INVTYPE_NECK": return "Neck"; case "INVTYPE_SHOULDER": return "Shoulder";
                case "INVTYPE_CLOAK": return "Back"; case "INVTYPE_CHEST": case "INVTYPE_ROBE": return "Chest";
                case "INVTYPE_WRIST": return "Wrist"; case "INVTYPE_HAND": return "Hands"; case "INVTYPE_WAIST": return "Waist";
                case "INVTYPE_LEGS": return "Legs"; case "INVTYPE_FEET": return "Feet"; case "INVTYPE_FINGER": return "Ring";
                case "INVTYPE_TRINKET": return "Trinket"; case "INVTYPE_WEAPON": case "INVTYPE_WEAPONMAINHAND": return "MainHand";
                case "INVTYPE_2HWEAPON": return "TwoHand"; case "INVTYPE_HOLDABLE": case "INVTYPE_WEAPONOFFHAND": case "INVTYPE_SHIELD": return "OffHand";
                case "INVTYPE_RANGED": case "INVTYPE_RANGEDRIGHT": case "INVTYPE_THROWN": case "INVTYPE_RELIC": return "Ranged";
            }
            return "";
        }

        static int N(string s) { return int.Parse(s, CultureInfo.InvariantCulture); }

        // Reads one line's stats into st. Returns false when nothing in it was understood.
        public static bool LineStats(string line, Stats st) {
            string t = line.Trim().TrimEnd('.');
            Match m;
            bool hit = false;
            if (Ignore.IsMatch(t) && !SpellHit.IsMatch(t)) {
                // Resistances, procs and undead-only bonuses do not count in a PvP fight.
                m = ArmorLine.Match(t); if (m.Success) { st.Armor += N(m.Groups[1].Value); return true; }
                return Regex.IsMatch(t, @"resistance", I);
            }
            m = ShadowLine.Match(t); if (m.Success) { st.ShadowSp += N(m.Groups[1].Value); hit = true; }
            else { m = SpLine.Match(t); if (m.Success) { st.Sp += N(m.Groups[1].Value); hit = true; } }
            m = PlusSp.Match(t); if (m.Success) { st.Sp += N(m.Groups[1].Value); hit = true; }
            m = SpPlus.Match(t); if (m.Success) { st.Sp += N(m.Groups[1].Value); hit = true; }
            m = PlusShadow.Match(t); if (m.Success) { st.ShadowSp += N(m.Groups[1].Value); hit = true; }
            m = PlusStat.Match(t); if (m.Success) { AddStat(st, m.Groups[2].Value, N(m.Groups[1].Value)); hit = true; }
            m = StatPlus.Match(t); if (m.Success) { AddStat(st, m.Groups[1].Value, N(m.Groups[2].Value)); hit = true; }
            m = SpellHit.Match(t); if (m.Success) { st.Hit += N(m.Groups[1].Value); hit = true; }
            else {
                m = SpellHitRating.Match(t); if (m.Success) { st.Hit += N(m.Groups[1].Value) / 8.0; hit = true; }
            }
            m = SpellCrit.Match(t); if (m.Success) { st.Crit += N(m.Groups[1].Value); hit = true; }
            else { m = SpellCritRating.Match(t); if (m.Success) { st.Crit += N(m.Groups[1].Value) / 14.0; hit = true; } }
            m = ArmorLine.Match(t); if (m.Success) { st.Armor += N(m.Groups[1].Value); hit = true; }
            m = PlusArmor.Match(t); if (m.Success) { st.Armor += N(m.Groups[1].Value); hit = true; }
            m = Mp5.Match(t); if (m.Success) { st.Mp5 += N(m.Groups[1].Value); hit = true; }
            else { m = PlusMp5.Match(t); if (m.Success) { st.Mp5 += N(m.Groups[1].Value); hit = true; } }
            return hit;
        }
        static void AddStat(Stats st, string name, int v) {
            switch (name.ToLowerInvariant()) {
                case "stamina": st.Sta += v; break; case "intellect": st.Int += v; break; case "spirit": st.Spi += v; break;
                case "all stats": st.Sta += v; st.Int += v; st.Spi += v; break;
            }
        }

        public static void ParseLines(Item it, List<string> lines, Dictionary<string, object> apiStats) {
            bool understood = false;
            foreach (var raw in lines) {
                string line = raw.Trim();
                string left = line, right = "";
                int bar = line.IndexOf(" | ", StringComparison.Ordinal);
                if (bar >= 0) { left = line.Substring(0, bar).Trim(); right = line.Substring(bar + 3).Trim(); }
                Match m;
                if (line.StartsWith("Unique", StringComparison.OrdinalIgnoreCase)) { it.Unique = true; continue; }
                m = ReqLevel.Match(line); if (m.Success) { it.ReqLevel = N(m.Groups[1].Value); continue; }
                m = Classes.Match(line); if (m.Success) { it.ClassList = m.Groups[1].Value; continue; }
                m = SetLine.Match(line);
                if (m.Success) {
                    var b = new SetBonus(); b.Count = N(m.Groups[1].Value); b.Text = m.Groups[2].Value;
                    LineStats(b.Text, b.Stats); it.SetBonuses.Add(b); continue;
                }
                m = SetName.Match(line); if (m.Success && it.SetName == null) { it.SetName = m.Groups[1].Value.Trim(); continue; }
                if (bar >= 0 && it.Type == null && IsSlotWord(left)) { it.Type = right; continue; }
                if (it.Type == null && IsSlotWord(line)) { it.Type = ""; continue; }
                m = UseSp.Match(line);
                if (m.Success) {
                    var u = new OnUse(); u.Sp = N(m.Groups[1].Value); u.Duration = N(m.Groups[2].Value);
                    var cd = Cooldown.Match(line);
                    u.Cooldown = cd.Success ? (cd.Groups[1].Success ? N(cd.Groups[1].Value) * 60 : 0) + (cd.Groups[2].Success ? N(cd.Groups[2].Value) : 0) : 120;
                    if (u.Cooldown <= 0) u.Cooldown = 120;
                    it.Use = u; continue;
                }
                bool isEquip = line.StartsWith("Equip:", StringComparison.OrdinalIgnoreCase);
                bool isUse = line.StartsWith("Use:", StringComparison.OrdinalIgnoreCase);
                if (LineStats(isEquip ? line.Substring(6) : line, it.Stats)) { understood = true; continue; }
                if (isEquip || isUse) it.NotCounted.Add(line);
            }
            // No tooltip text at all: fall back to the game's stat numbers.
            if (!understood && lines.Count == 0 && apiStats != null) {
                foreach (var kv in apiStats) {
                    if (!(kv.Value is double)) continue; double v = (double)kv.Value;
                    string k = kv.Key.ToUpperInvariant();
                    if (k.Contains("STAMINA")) it.Stats.Sta += v; else if (k.Contains("INTELLECT")) it.Stats.Int += v;
                    else if (k.Contains("SPIRIT")) it.Stats.Spi += v; else if (k.Contains("SPELL_POWER") || k.Contains("SPELL_DAMAGE")) it.Stats.Sp += v;
                    else if (k.Contains("RESISTANCE0") || k == "ITEM_MOD_ARMOR_SHORT") it.Stats.Armor += v;
                }
            }
        }
        static bool IsSlotWord(string s) {
            switch (s.ToLowerInvariant()) {
                case "head": case "neck": case "shoulder": case "back": case "chest": case "wrist": case "hands": case "waist": case "legs":
                case "feet": case "finger": case "trinket": case "main hand": case "off hand": case "one-hand": case "two-hand":
                case "ranged": case "held in off-hand": case "thrown": case "relic": return true;
            }
            return false;
        }

        // Every character's saved text in a VoidMarkGearSim.lua SavedVariables file.
        static readonly Regex ExportField = new Regex("\\[\"export\"\\]\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\"", RegexOptions.Singleline);
        public static List<string> FromSavedVariables(string luaText) {
            var list = new List<string>();
            foreach (Match m in ExportField.Matches(luaText)) list.Add(LuaUnescape(m.Groups[1].Value));
            return list;
        }
        public static string LuaUnescape(string s) {
            var b = new StringBuilder(s.Length);
            for (int i = 0; i < s.Length; i++) {
                char c = s[i];
                if (c != '\\' || i + 1 >= s.Length) { b.Append(c); continue; }
                char e = s[++i];
                switch (e) {
                    case 'n': b.Append('\n'); break; case 'r': b.Append('\r'); break; case 't': b.Append('\t'); break;
                    case '\n': b.Append('\n'); break;
                    default:
                        if (char.IsDigit(e)) {
                            int n = 0, k = 0;
                            while (k < 3 && i < s.Length && char.IsDigit(s[i])) { n = n * 10 + (s[i] - '0'); i++; k++; }
                            i--; b.Append((char)n);
                        } else b.Append(e);
                        break;
                }
            }
            // Lua writes bytes; the text is UTF-8.
            var raw = new byte[b.Length]; bool wide = false;
            for (int i = 0; i < b.Length; i++) { if (b[i] > 255) { wide = true; break; } raw[i] = (byte)b[i]; }
            return wide ? b.ToString() : Encoding.UTF8.GetString(raw);
        }

        // <AddOns folder> -> every VoidMarkGearSim.lua under <game>\WTF\Account.
        public static List<Snapshot> FromGameFolder(string addOns, List<string> problems) {
            var found = new List<Snapshot>();
            if (string.IsNullOrEmpty(addOns)) return found;
            string game = null;
            try { var d = new DirectoryInfo(addOns); if (d.Parent != null && d.Parent.Parent != null) game = d.Parent.Parent.FullName; } catch { }
            if (game == null) return found;
            string account = Path.Combine(Path.Combine(game, "WTF"), "Account");
            if (!Directory.Exists(account)) return found;
            foreach (var file in Directory.GetFiles(account, "VoidMarkGearSim.lua", SearchOption.AllDirectories)) {
                string text;
                try { text = File.ReadAllText(file, Encoding.GetEncoding(28591)); } catch (Exception e) { problems.Add(Path.GetFileName(file) + ": " + e.Message); continue; }
                foreach (var export in FromSavedVariables(text)) {
                    try { found.Add(FromText(export)); } catch (Exception e) { problems.Add(e.Message); }
                }
            }
            return found.OrderByDescending(x => x.At).ToList();
        }
    }

    // -------------------------------------------------------------- Model
    public class Options {
        public double TargetHealth = 4000, TargetShadowResist = 0, FightSeconds = 30;
        public bool UseTrinkets = true, Shadowform = true;
        public double AttackerLevel = 60;
    }

    public class Result {
        public Dictionary<string, Item> Gear = new Dictionary<string, Item>();
        public double SpellDamage, Health, Mana, Hit, Crit, Armor, Stamina, Intellect, Spirit;
        public double Kill, KillScore, KillNoTrinket, Burst6, Dps, ManaPerKill, Fights, EffectiveHealth, Score;
        public List<string> ActiveSets = new List<string>();
    }

    public static class Gear {
        public static readonly string[] Order = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Ring1", "Ring2", "Trinket1", "Trinket2", "MainHand", "OffHand", "Ranged" };
        static readonly Dictionary<int, string> SlotNames = new Dictionary<int, string> {
            {1,"Head"},{2,"Neck"},{3,"Shoulder"},{15,"Back"},{5,"Chest"},{9,"Wrist"},{10,"Hands"},{6,"Waist"},{7,"Legs"},{8,"Feet"},
            {11,"Ring1"},{12,"Ring2"},{13,"Trinket1"},{14,"Trinket2"},{16,"MainHand"},{17,"OffHand"},{18,"Ranged"} };

        // What a Priest can wear. Other classes are read but the fight model is a Shadow Priest's.
        public static void CheckUsable(Snapshot s) {
            foreach (var it in s.Items) {
                if (it.Slot == "") { it.Usable = false; it.WhyNot = "not gear"; continue; }
                if (it.ReqLevel > s.Level) { it.Usable = false; it.WhyNot = "needs level " + it.ReqLevel; continue; }
                if (it.ClassList != null && it.ClassList.IndexOf(Pretty(s.Class), StringComparison.OrdinalIgnoreCase) < 0) { it.Usable = false; it.WhyNot = "class " + it.ClassList; continue; }
                if (s.Class == "PRIEST") {
                    string t = (it.Type ?? "").ToLowerInvariant();
                    if (t == "leather" || t == "mail" || t == "plate" || t == "shield" || it.Loc == "INVTYPE_SHIELD") { it.Usable = false; it.WhyNot = "priests can't use " + it.Type; continue; }
                    if ((it.Slot == "MainHand" || it.Slot == "TwoHand" || it.Slot == "Ranged") && t != "" &&
                        !(t == "dagger" || t == "mace" || t == "staff" || t == "wand")) { it.Usable = false; it.WhyNot = "priests can't use " + it.Type; continue; }
                    if (it.Slot == "TwoHand" && t == "mace") { it.Usable = false; it.WhyNot = "priests can't use two-hand maces"; continue; }
                    if (it.Loc == "INVTYPE_WEAPONOFFHAND") { it.Usable = false; it.WhyNot = "priests can't dual wield"; continue; }
                    if (it.Name.IndexOf("Fishing", StringComparison.OrdinalIgnoreCase) >= 0) { it.Usable = false; it.WhyNot = "fishing pole"; continue; }
                }
            }
        }
        static string Pretty(string cls) { return string.IsNullOrEmpty(cls) ? "" : cls.Substring(0, 1) + cls.Substring(1).ToLowerInvariant(); }

        public static Dictionary<string, Item> Worn(Snapshot s) {
            var g = new Dictionary<string, Item>();
            foreach (var kv in s.Slots) {
                string slot; if (!SlotNames.TryGetValue(kv.Key, out slot)) continue;
                var it = s.Items.FirstOrDefault(x => x.Link == kv.Value);
                if (it != null) g[slot] = it;
            }
            return g;
        }

        public static Stats Sum(IEnumerable<Item> items, List<string> activeSets) {
            var st = new Stats(); var sets = new Dictionary<string, int>(); var bonus = new Dictionary<string, List<SetBonus>>();
            foreach (var it in items) {
                if (it == null) continue; st.Add(it.Stats);
                if (it.SetName != null) {
                    int n; sets.TryGetValue(it.SetName, out n); sets[it.SetName] = n + 1;
                    if (!bonus.ContainsKey(it.SetName) && it.SetBonuses.Count > 0) bonus[it.SetName] = it.SetBonuses;
                }
            }
            foreach (var kv in sets) {
                List<SetBonus> list; if (!bonus.TryGetValue(kv.Key, out list)) continue;
                int best = 0;
                foreach (var b in list) if (b.Count <= kv.Value) { st.Add(b.Stats); if (b.Count > best) best = b.Count; }
                if (best > 0 && activeSets != null) activeSets.Add(kv.Key + " (" + kv.Value + " pieces)");
            }
            return st;
        }

        // What the character has without any gear: the sheet minus what is worn now.
        public static Stats Base(Snapshot s) {
            var b = new Stats();
            b.Sp = s.SheetShadow; b.Sta = s.SheetSta; b.Int = s.SheetInt; b.Spi = s.SheetSpi; b.Hit = s.SheetHit; b.Crit = s.SheetCrit; b.Armor = s.SheetArmor;
            var worn = Sum(Worn(s).Values, null);
            b.Sp -= worn.Sp + worn.ShadowSp; b.Sta -= worn.Sta; b.Int -= worn.Int; b.Spi -= worn.Spi; b.Hit -= worn.Hit; b.Armor -= worn.Armor; b.Mp5 -= worn.Mp5;
            b.Crit -= worn.Crit + worn.Int / 59.5;
            return b;
        }

        static int T(Snapshot s, string name) { int r; return s.Talents.TryGetValue(name, out r) ? r : 0; }

        // Expected damage over a fight: SW:P, Mind Blast on cooldown, Mind Flay between.
        // Spell numbers are Classic level-60 max ranks.
        public static Result Evaluate(Snapshot s, Dictionary<string, Item> gear, Options o, Stats basis) {
            var active = new List<string>();
            var gearStats = Sum(gear.Values, active);
            OnUse use = null;
            foreach (var it in gear.Values) if (it != null && it.Use != null && (use == null || it.Use.Sp > use.Sp)) use = it.Use;
            var r = EvaluateStats(s, gearStats, use, o, basis);
            r.Gear = gear; r.ActiveSets = active;
            return r;
        }

        // Score for a set of gear stats. Every score only gets better with more of any stat,
        // which lets the optimizer skip whole branches of gear it can't improve on.
        public static Result EvaluateStats(Snapshot s, Stats gearStats, OnUse use, Options o, Stats basis) {
            var r = new Result();
            var st = basis.Copy(); st.Add(gearStats);
            double sp = st.Sp + st.ShadowSp;
            r.Stamina = st.Sta; r.Intellect = st.Int; r.Spirit = st.Spi; r.SpellDamage = sp; r.Armor = st.Armor;
            r.Health = s.Health + (st.Sta - s.SheetSta) * 10;
            r.Mana = s.Mana + (st.Int - s.SheetInt) * 15 * (1 + 0.02 * T(s, "Mental Strength"));
            r.Crit = st.Crit + st.Int / 59.5;
            r.Hit = Math.Min(99, 96 + st.Hit + 2 * T(s, "Shadow Focus"));
            double dr = r.Armor / (r.Armor + 400 + 85 * o.AttackerLevel);
            r.EffectiveHealth = r.Health / (1 - Math.Min(0.75, Math.Max(0, dr)));
            if (!o.UseTrinkets) use = null;
            double dmg6, manaUsed, dps, landed;
            r.KillScore = Fight(s, o, sp, r.Hit, r.Crit, r.Mana, st.Mp5, use, out dmg6, out manaUsed, out dps, out landed);
            // Shown kill times are expected values (hit and crit chances), so they move smoothly.
            r.Kill = r.KillScore; r.Burst6 = dmg6; r.ManaPerKill = manaUsed; r.Dps = dps;
            double d2, m2, p2;
            r.KillNoTrinket = use == null ? r.Kill : Fight(s, o, sp, r.Hit, r.Crit, r.Mana, st.Mp5, null, out d2, out m2, out p2);
            r.Fights = manaUsed > 0 ? r.Mana / manaUsed : 99;
            return r;
        }

        // One cast at a time: open with Shadow Word: Pain, Mind Blast on cooldown, Mind Flay between.
        // Expected values (hit chance, Mind Blast crits; Mind Flay and DoT ticks can't crit).
        public static double Fight(Snapshot s, Options o, double sp, double hitPct, double critPct, double mana, double mp5, OnUse use,
                                   out double burst6, out double manaUsed, out double dps) {
            double landed;
            return Fight(s, o, sp, hitPct, critPct, mana, mp5, use, out burst6, out manaUsed, out dps, out landed);
        }
        // Returns a smoothed kill time for ranking (small stat changes always move it a little);
        // landed is the moment the killing hit actually lands, for showing.
        public static double Fight(Snapshot s, Options o, double sp, double hitPct, double critPct, double mana, double mp5, OnUse use,
                                   out double burst6, out double manaUsed, out double dps, out double landed) {
            double hit = Math.Max(0, Math.Min(0.99, hitPct / 100.0));
            double crit = Math.Max(0, Math.Min(1, critPct / 100.0));
            double mod = 1 + 0.02 * T(s, "Darkness");
            if (o.Shadowform && T(s, "Shadowform") > 0) mod *= 1.15;
            mod *= 1 - Math.Min(0.75, o.TargetShadowResist / 400.0);
            double weaveChance = Math.Min(1, 0.2 * T(s, "Shadow Weaving")) * hit, stacks = 0;
            double mbCd = 8 - 0.5 * T(s, "Improved Mind Blast");
            bool flay = T(s, "Mind Flay") > 0;
            int swpTicks = 6 + T(s, "Improved Shadow Word: Pain");
            double horizon = Math.Max(o.FightSeconds, 60);
            var times = new double[96]; var amounts = new double[96]; int n = 0;
            var castAt = new double[64]; var castCost = new double[64]; int casts = 0;
            double t = 0, mbReady = 0, swpEnd = -1, regen = mp5 / 5.0;
            while (t < horizon && n < 90 && casts < 64) {
                double curSp = sp + (use != null && t < use.Duration ? use.Sp : 0);
                double weave = 1 + 0.03 * stacks;
                double cost;
                if (t >= swpEnd - 0.01 && mana >= 470) {
                    double tick = (852 + curSp) / 6.0 * hit * mod * weave;
                    for (int i = 1; i <= swpTicks && n < 96; i++) { times[n] = t + 3 * i; amounts[n++] = tick; }
                    swpEnd = t + 3 * swpTicks; cost = 470;
                } else if (t >= mbReady && mana >= 350) {
                    times[n] = t + 1.5; amounts[n++] = (517 + curSp * 0.4286) * hit * (1 + crit * 0.5) * mod * weave;
                    mbReady = t + 1.5 + mbCd; cost = 350;
                } else if (flay && mana >= 205) {
                    double tick = (426 + curSp * 0.45) / 3.0 * hit * mod * weave;
                    for (int i = 1; i <= 3; i++) { times[n] = t + i; amounts[n++] = tick; }
                    cost = 205;
                } else {
                    // Nothing to cast: wait for Mind Blast, Shadow Word: Pain or mana.
                    double next = Math.Min(mbReady, swpEnd);
                    if (next <= t) next = t + 1;
                    if (mana < 205 && regen <= 0) break;
                    mana += regen * (next - t); t = next; continue;
                }
                double busy = cost == 205 ? 3 : 1.5;
                castAt[casts] = t; castCost[casts++] = cost; mana -= cost;
                stacks = Math.Min(5, stacks + weaveChance);
                mana += regen * busy; t += busy;
            }
            // Damage lands in time order. The kill time is where the target's health runs out
            // between two hits, so small stat changes always move it a little.
            Array.Sort(times, amounts, 0, n);
            double done = 0, kill = -1, at = 0, prev = 0; burst6 = 0; landed = 99;
            for (int i = 0; i < n; i++) {
                double before = done; done += amounts[i];
                if (times[i] <= 6) burst6 += amounts[i];
                if (times[i] <= o.FightSeconds) at += amounts[i];
                if (kill < 0 && done >= o.TargetHealth) {
                    double share = amounts[i] > 0 ? (o.TargetHealth - before) / amounts[i] : 1;
                    kill = prev + (times[i] - prev) * share; landed = times[i];
                }
                prev = times[i];
            }
            double used = 0; double until = kill < 0 ? horizon : kill;
            for (int i = 0; i < casts; i++) if (castAt[i] < until) used += castCost[i];
            manaUsed = used;
            dps = at / o.FightSeconds;
            return kill < 0 ? 99 : kill;
        }

        public static double Score(Result r, string mode) {
            switch (mode) {
                case "Burst": return 1000.0 / r.KillScore + r.EffectiveHealth / 1e6;
                case "Tanky": return r.EffectiveHealth * r.EffectiveHealth / r.KillScore / 1e6;
                default: return r.EffectiveHealth / r.KillScore;
            }
        }

        // ----------------------------------------------------- Optimizer
        public class Plan { public Result Current; public Dictionary<string, Result> Best = new Dictionary<string, Result>(); public long Tried; public bool Searched; }

        static List<Item> Candidates(Snapshot s, string slot, Dictionary<string, Item> worn) {
            var list = s.Items.Where(x => x.Usable && x.Slot == slot).ToList();
            // Drop items other items beat in every stat (set pieces and on-use trinkets always stay).
            // Ring and trinket slots need two better items before one is dropped.
            int need = (slot == "Ring" || slot == "Trinket") ? 2 : 1;
            var keep = new List<Item>();
            foreach (var it in list) {
                int better = 0;
                if (it.SetName == null && it.Use == null)
                    foreach (var o in list)
                        if (o != it && o.SetName == null && o.Stats.AtLeast(it.Stats) && !it.Stats.AtLeast(o.Stats)) better += Math.Max(1, Math.Min(2, o.Owned));
                if (better < need || worn.Values.Contains(it)) keep.Add(it);
            }
            return keep;
        }

        class Option { public string[] Keys; public Item[] Items; public Stats St = new Stats(); public OnUse Use; public int[] Sets; }
        class Group { public List<Option> Options = new List<Option>(); public Stats Max = new Stats(); public double MaxUse; public int[] MaxSets; }

        public static Plan Optimize(Snapshot s, Options o, string[] modes) {
            var plan = new Plan();
            var basis = Base(s);
            var worn = Worn(s);
            plan.Current = Evaluate(s, worn, o, basis);
            // Sets the character owns pieces of, with their bonuses.
            var setNames = s.Items.Where(x => x.Usable && x.SetName != null).Select(x => x.SetName).Distinct().ToList();
            var bonuses = setNames.Select(n => { var it = s.Items.FirstOrDefault(x => x.SetName == n && x.SetBonuses.Count > 0); return it == null ? new List<SetBonus>() : it.SetBonuses; }).ToList();
            Func<string[], Item[], Option> make = (keys, items) => {
                var op = new Option { Keys = keys, Items = items, Sets = new int[setNames.Count] };
                foreach (var it in items) {
                    if (it == null) continue;
                    op.St.Add(it.Stats);
                    if (it.Use != null && (op.Use == null || it.Use.Sp > op.Use.Sp)) op.Use = it.Use;
                    if (it.SetName != null) op.Sets[setNames.IndexOf(it.SetName)]++;
                }
                return op;
            };
            var groups = new List<Group>();
            foreach (var slot in new[] { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Ranged" }) {
                var g = new Group();
                var c = Candidates(s, slot, worn);
                if (c.Count == 0) g.Options.Add(make(new[] { slot }, new Item[] { null }));
                foreach (var it in c) g.Options.Add(make(new[] { slot }, new[] { it }));
                groups.Add(g);
            }
            Action<string, string, List<Item[]>> pairGroup = (k1, k2, pairs) => { var g = new Group(); foreach (var pr in pairs) g.Options.Add(make(new[] { k1, k2 }, pr)); groups.Add(g); };
            pairGroup("Ring1", "Ring2", Pairs(Candidates(s, "Ring", worn)));
            pairGroup("Trinket1", "Trinket2", Pairs(Candidates(s, "Trinket", worn)));
            var weapons = new List<Item[]>();
            var mh = Candidates(s, "MainHand", worn); var oh = Candidates(s, "OffHand", worn); var th = Candidates(s, "TwoHand", worn);
            foreach (var a in mh) { weapons.Add(new Item[] { a, null }); foreach (var b in oh) weapons.Add(new Item[] { a, b }); }
            foreach (var a in th) weapons.Add(new Item[] { a, null });
            if (weapons.Count == 0) foreach (var b in oh) weapons.Add(new Item[] { null, b });
            if (weapons.Count == 0) weapons.Add(new Item[] { null, null });
            pairGroup("MainHand", "OffHand", weapons);
            foreach (var g in groups) {
                g.MaxSets = new int[setNames.Count];
                foreach (var op in g.Options) {
                    g.Max.Sp = Math.Max(g.Max.Sp, op.St.Sp); g.Max.ShadowSp = Math.Max(g.Max.ShadowSp, op.St.ShadowSp);
                    g.Max.Sta = Math.Max(g.Max.Sta, op.St.Sta); g.Max.Int = Math.Max(g.Max.Int, op.St.Int); g.Max.Spi = Math.Max(g.Max.Spi, op.St.Spi);
                    g.Max.Hit = Math.Max(g.Max.Hit, op.St.Hit); g.Max.Crit = Math.Max(g.Max.Crit, op.St.Crit);
                    g.Max.Armor = Math.Max(g.Max.Armor, op.St.Armor); g.Max.Mp5 = Math.Max(g.Max.Mp5, op.St.Mp5);
                    if (op.Use != null) g.MaxUse = Math.Max(g.MaxUse, op.Use.Sp);
                    for (int k = 0; k < setNames.Count; k++) g.MaxSets[k] = Math.Max(g.MaxSets[k], op.Sets[k]);
                }
            }
            // Big differences first: the search rules out more, sooner.
            groups = groups.OrderByDescending(g => g.Options.Count < 2 ? 0 : g.Options.Max(x => x.St.Sp + x.St.ShadowSp + x.St.Sta) - g.Options.Min(x => x.St.Sp + x.St.ShadowSp + x.St.Sta)).ToList();
            int G = groups.Count;
            // Best still possible from group d on: each stat's best option, every set bonus still reachable.
            var restMax = new Stats[G + 1]; var restUse = new double[G + 1]; var restSets = new int[G + 1][];
            restMax[G] = new Stats(); restSets[G] = new int[setNames.Count];
            for (int d = G - 1; d >= 0; d--) {
                restMax[d] = restMax[d + 1].Copy(); restMax[d].Add(groups[d].Max); restUse[d] = Math.Max(restUse[d + 1], groups[d].MaxUse);
                restSets[d] = new int[setNames.Count]; for (int k = 0; k < setNames.Count; k++) restSets[d][k] = restSets[d + 1][k] + groups[d].MaxSets[k];
            }
            OnUse anyUse = s.Items.Where(x => x.Usable && x.Use != null).Select(x => x.Use).OrderByDescending(x => x.Sp).FirstOrDefault();
            Func<int[], int[], Stats> setStats = (have, extra) => {
                var st = new Stats();
                for (int k = 0; k < setNames.Count; k++) { int n = have[k] + (extra == null ? 0 : extra[k]); foreach (var b in bonuses[k]) if (b.Count <= n) st.Add(b.Stats); }
                return st;
            };
            foreach (var mode in modes) {
                double best = Score(plan.Current, mode) - 1e-9;
                int[] pick = null; var choice = new int[G];
                var acc = new Stats(); var sets = new int[setNames.Count];
                Action<int, OnUse> dfs = null;
                dfs = (d, use) => {
                    plan.Tried++;
                    if (d == G) {
                        var total = acc.Copy(); total.Add(setStats(sets, null));
                        double sc = Score(EvaluateStats(s, total, use, o, basis), mode);
                        if (sc > best) { best = sc; pick = (int[])choice.Clone(); }
                        return;
                    }
                    // Upper bound for everything below this point.
                    var bound = acc.Copy(); bound.Add(restMax[d]); bound.Add(setStats(sets, restSets[d]));
                    OnUse bu = use; if (restUse[d] > 0 && (bu == null || restUse[d] > bu.Sp)) bu = anyUse;
                    if (Score(EvaluateStats(s, bound, bu, o, basis), mode) <= best) return;
                    var g = groups[d];
                    for (int i = 0; i < g.Options.Count; i++) {
                        var op = g.Options[i];
                        acc.Add(op.St); for (int k = 0; k < sets.Length; k++) sets[k] += op.Sets[k];
                        choice[d] = i;
                        dfs(d + 1, op.Use != null && (use == null || op.Use.Sp > use.Sp) ? op.Use : use);
                        acc.Sub(op.St); for (int k = 0; k < sets.Length; k++) sets[k] -= op.Sets[k];
                    }
                };
                dfs(0, null);
                if (pick == null) { var same = Clone(plan.Current); same.Score = Score(same, mode); plan.Best[mode] = same; continue; }
                var gear = new Dictionary<string, Item>();
                for (int d = 0; d < G; d++) { var op = groups[d].Options[pick[d]]; for (int k = 0; k < op.Keys.Length; k++) gear[op.Keys[k]] = op.Items[k]; }
                var r = Evaluate(s, gear, o, basis); r.Score = Score(r, mode); plan.Best[mode] = r;
            }
            plan.Searched = true;
            return plan;
        }
        static Item Get(Dictionary<string, Item> g, string k) { Item v; return g.TryGetValue(k, out v) ? v : null; }
        static Result Clone(Result r) {
            var c = (Result)r.GetType().GetMethod("MemberwiseClone", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic).Invoke(r, null);
            c.Gear = new Dictionary<string, Item>(r.Gear); c.ActiveSets = new List<string>(r.ActiveSets); return c;
        }
        static List<Item[]> Pairs(List<Item> list) {
            var pairs = new List<Item[]>();
            for (int i = 0; i < list.Count; i++)
                for (int j = i; j < list.Count; j++) {
                    if (i == j && (list[i].Owned < 2 || list[i].Unique)) continue;
                    if (i != j && list[i].Id == list[j].Id && list[i].Unique) continue;
                    pairs.Add(new Item[] { list[i], list[j] });
                }
            if (pairs.Count == 0) { foreach (var it in list) pairs.Add(new Item[] { it, null }); }
            if (pairs.Count == 0) pairs.Add(new Item[] { null, null });
            return pairs;
        }
        // Slot-by-slot changes from what is worn now ("" when nothing changes).
        public static List<string> Swaps(Dictionary<string, Item> from, Dictionary<string, Item> to) {
            var lines = new List<string>();
            foreach (var slot in Order) {
                if (slot.StartsWith("Ring") || slot.StartsWith("Trinket")) continue;
                var x = Get(from, slot); var y = Get(to, slot);
                if (x == y) continue;
                lines.Add(slot + ": " + (x == null ? "(empty)" : x.Name) + "  →  " + (y == null ? "(empty)" : y.Name + Place(y)));
            }
            PairSwap(lines, "Ring", from, to, "Ring1", "Ring2");
            PairSwap(lines, "Trinket", from, to, "Trinket1", "Trinket2");
            return lines;
        }
        static void PairSwap(List<string> lines, string label, Dictionary<string, Item> from, Dictionary<string, Item> to, string k1, string k2) {
            var had = new List<Item> { Get(from, k1), Get(from, k2) }.Where(x => x != null).ToList();
            var want = new List<Item> { Get(to, k1), Get(to, k2) }.Where(x => x != null).ToList();
            var add = want.Where(x => !had.Remove(x)).ToList();
            var leftover = new List<Item> { Get(from, k1), Get(from, k2) }.Where(x => x != null).ToList();
            foreach (var w in want) leftover.Remove(w);
            for (int i = 0; i < add.Count; i++)
                lines.Add(label + ": " + (i < leftover.Count ? leftover[i].Name : "(empty)") + "  →  " + add[i].Name + Place(add[i]));
        }
        static string Place(Item it) { return it.Worn > 0 ? "" : (it.Bags > 0 ? "  (bags)" : "  (bank)"); }

        // Lines the sim could not read, so the player knows what was left out.
        public static List<string> Notes(Snapshot s) {
            var notes = new List<string>();
            if (s.Class != "PRIEST") notes.Add("The fight model is a Shadow Priest's. Gear for " + Pretty(s.Class) + " is read, but the damage numbers won't fit your class yet.");
            if (s.BankAt <= 0) notes.Add("Bank gear isn't included yet: open your bank once in game, then copy again (or /reload).");
            if (s.Pending > 0) notes.Add(s.Pending + " items were still loading in game. Copy again in a moment to include them.");
            foreach (var it in s.Items.Where(x => x.Usable && x.NotCounted.Count > 0).OrderBy(x => x.Name))
                foreach (var l in it.NotCounted) notes.Add("Not counted (" + it.Name + "): " + l);
            return notes;
        }
    }
}
