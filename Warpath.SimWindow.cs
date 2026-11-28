// VoidMark Warpath: Gear Sim window. Self-contained (own colors), so a problem here can
// never stop the rest of Warpath from opening. C# 5 for Windows PowerShell 5.1.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Linq;
using System.Windows.Forms;

namespace Warpath.GearSim {
    public class SimWindow : Form {
        static readonly Color Back = ColorTranslator.FromHtml("#07040C"), Panel = ColorTranslator.FromHtml("#120A1E"), Input = ColorTranslator.FromHtml("#0A0512"),
            Accent = ColorTranslator.FromHtml("#8B3DFF"), Highlight = ColorTranslator.FromHtml("#C77DFF"), Fore = ColorTranslator.FromHtml("#F3E9FF"),
            Muted = ColorTranslator.FromHtml("#B08CE6"), Good = ColorTranslator.FromHtml("#4ADE80"), Warn = ColorTranslator.FromHtml("#FFC450"), Bad = ColorTranslator.FromHtml("#F87171");
        static readonly string[] AllModes = Gear.PvpModes.Concat(Gear.RaidModes).ToArray();
        string[] Modes { get { return simType.SelectedIndex == 1 ? Gear.RaidModes : Gear.PvpModes; } }

        readonly string addOns;
        readonly ComboBox character = new ComboBox(), goal = new ComboBox(), simType = new ComboBox();
        readonly TextBox paste = new TextBox(), details = new TextBox();
        readonly NumericUpDown targetHp = new NumericUpDown(), targetResist = new NumericUpDown(), raidSeconds = new NumericUpDown();
        readonly CheckBox trinkets = new CheckBox(), potions = new CheckBox();
        readonly ListView table = new ListView();
        readonly Label status = new Label();
        List<Snapshot> found = new List<Snapshot>();
        Snapshot current;
        Gear.Plan plan;
        Options options;

        public static void Open(IWin32Window owner, string addOnsFolder) {
            using (var w = new SimWindow(addOnsFolder)) { if (owner != null) w.ShowDialog(owner); else w.ShowDialog(); }
        }

        public SimWindow(string addOnsFolder) {
            addOns = addOnsFolder;
            Text = "VoidMark Warpath — Gear Sim"; ClientSize = new Size(900, 800); BackColor = Back; ForeColor = Fore;
            Font = new Font("Segoe UI", 10); StartPosition = FormStartPosition.CenterParent; FormBorderStyle = FormBorderStyle.FixedSingle; MaximizeBox = false;
            AutoScaleMode = AutoScaleMode.Dpi;

            var title = MakeLabel("GEAR SIM — PRIEST", 20, 12, 600, 30); title.Font = new Font("Georgia", 15, FontStyle.Bold); title.ForeColor = Highlight;
            var help = MakeLabel("Ranks every gear combination you own (worn, bags, bank). Buffs are taken out, so it works unbuffed. In game: open your bank once, click Sim on your character window (or /vmsim), then /reload and press Load from WoW.", 20, 44, 860, 40);
            help.ForeColor = Muted;

            MakeLabel("Character", 20, 92, 90, 24);
            character.SetBounds(110, 89, 430, 28); character.DropDownStyle = ComboBoxStyle.DropDownList; Style(character);
            character.SelectedIndexChanged += delegate { if (character.SelectedIndex >= 0 && character.SelectedIndex < found.Count) { current = found[character.SelectedIndex]; Run(); } };
            var reload = MakeButton("Load from WoW", 552, 86, 160, 34); reload.Click += delegate { LoadFromGame(true); };

            MakeLabel("Or paste", 20, 130, 90, 24);
            paste.SetBounds(110, 127, 600, 28); Style(paste); paste.Font = new Font("Consolas", 9);
            paste.MaxLength = int.MaxValue; // Windows text boxes stop at 32,767 characters by default; gear text is longer.
            var use = MakeButton("Paste from clipboard", 722, 124, 158, 34); use.Click += delegate { UsePaste(); };

            MakeLabel("Sim", 20, 172, 90, 24);
            simType.SetBounds(110, 169, 150, 28); simType.DropDownStyle = ComboBoxStyle.DropDownList; simType.Items.AddRange(new object[] { "PvP", "Raid & stats" }); simType.SelectedIndex = 0; Style(simType);
            simType.SelectedIndexChanged += delegate { FillGoals(); ShowResults(); };
            MakeLabel("Goal", 20, 212, 90, 24);
            goal.SetBounds(110, 209, 150, 28); goal.DropDownStyle = ComboBoxStyle.DropDownList; Style(goal); FillGoals();
            goal.SelectedIndexChanged += delegate { ShowResults(); };
            MakeLabel("Boss fight (s)", 280, 212, 105, 24);
            raidSeconds.SetBounds(388, 209, 90, 28); raidSeconds.Minimum = 30; raidSeconds.Maximum = 900; raidSeconds.Increment = 30; raidSeconds.Value = 180; Style(raidSeconds);
            potions.Text = "Mana potion + rune every 2 min"; potions.Checked = true; potions.SetBounds(496, 210, 260, 26); potions.ForeColor = Fore; potions.BackColor = Back; Controls.Add(potions);
            raidSeconds.ValueChanged += delegate { Run(); }; potions.CheckedChanged += delegate { Run(); };
            MakeLabel("Enemy health", 280, 172, 105, 24);
            targetHp.SetBounds(388, 169, 90, 28); targetHp.Minimum = 1000; targetHp.Maximum = 15000; targetHp.Increment = 250; targetHp.Value = 4000; Style(targetHp);
            MakeLabel("Enemy shadow resist", 496, 172, 150, 24);
            targetResist.SetBounds(648, 169, 70, 28); targetResist.Minimum = 0; targetResist.Maximum = 300; targetResist.Increment = 10; targetResist.Value = 0; Style(targetResist);
            trinkets.Text = "Use trinkets"; trinkets.Checked = true; trinkets.SetBounds(734, 170, 150, 26); trinkets.ForeColor = Fore; trinkets.BackColor = Back; Controls.Add(trinkets);
            targetHp.ValueChanged += delegate { Run(); }; targetResist.ValueChanged += delegate { Run(); }; trinkets.CheckedChanged += delegate { Run(); };

            table.SetBounds(20, 250, 860, 290); table.View = View.Details; table.FullRowSelect = true; table.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            table.BackColor = Panel; table.ForeColor = Fore; table.BorderStyle = BorderStyle.FixedSingle; table.Font = new Font("Segoe UI", 10);
            Controls.Add(table);

            details.SetBounds(20, 550, 860, 214); details.Multiline = true; details.ReadOnly = true; details.ScrollBars = ScrollBars.Vertical; Style(details);
            details.Font = new Font("Segoe UI", 10); Controls.Add(details);

            status.SetBounds(20, 770, 860, 24); status.ForeColor = Muted; status.BackColor = Back; Controls.Add(status);
            Shown += delegate { LoadFromGame(false); };
        }

        Label MakeLabel(string text, int x, int y, int w, int h) {
            var l = new Label { Text = text, Location = new Point(x, y), Size = new Size(w, h), ForeColor = Fore, BackColor = Back };
            Controls.Add(l); return l;
        }
        Button MakeButton(string text, int x, int y, int w, int h) {
            var b = new Button { Text = text, Location = new Point(x, y), Size = new Size(w, h), FlatStyle = FlatStyle.Flat, BackColor = Accent, ForeColor = Color.White, Cursor = Cursors.Hand };
            b.FlatAppearance.BorderColor = Highlight; Controls.Add(b); return b;
        }
        void Style(Control c) { c.BackColor = Input; c.ForeColor = Fore; Controls.Add(c); }

        void LoadFromGame(bool told) {
            var problems = new List<string>();
            try { found = Reader.FromGameFolder(addOns, problems); }
            catch (Exception e) { found = new List<Snapshot>(); problems.Add(e.Message); }
            character.Items.Clear();
            foreach (var s in found) character.Items.Add(s.Label + "   " + Age(s.At));
            if (found.Count > 0) { character.SelectedIndex = 0; return; }
            string why = string.IsNullOrEmpty(addOns) ? "Pick your AddOns folder in Warpath first." :
                "No saved gear found yet. Install VoidMark Gear Sim, log in, click Sim on your character window (or /vmsim), then /reload and press Load from WoW. Or paste the text above.";
            if (problems.Count > 0) why += " (" + problems[0] + ")";
            SetStatus(why, told ? Warn : Muted);
        }

        // Reads the copied text straight from the clipboard (the box is only a fallback),
        // so a long paste never depends on the text box.
        void UsePaste() {
            try {
                string text = null;
                try { if (Clipboard.ContainsText()) text = Clipboard.GetText(); } catch { }
                if (string.IsNullOrEmpty(text) || text.IndexOf(Reader.Header, StringComparison.Ordinal) < 0) text = paste.Text;
                if (string.IsNullOrEmpty(text) || text.IndexOf(Reader.Header, StringComparison.Ordinal) < 0)
                    throw new FormatException("Nothing to use. In game: click Sim (or /vmsim), press Ctrl+C in the box, then click Paste from clipboard here.");
                var s = Reader.FromText(text);
                found.Insert(0, s);
                character.Items.Insert(0, s.Label + "   pasted");
                character.SelectedIndex = 0;
                if (current != s) { current = s; Run(); }
                paste.Text = "";
            } catch (Exception e) { SetStatus(e.Message, Bad); }
        }

        static string Age(double at) {
            if (at <= 0) return "";
            var then = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(at).ToLocalTime();
            var ago = DateTime.Now - then;
            if (ago.TotalMinutes < 2) return "saved just now";
            if (ago.TotalHours < 1) return "saved " + (int)ago.TotalMinutes + " min ago";
            if (ago.TotalDays < 1) return "saved " + (int)ago.TotalHours + " h ago";
            return "saved " + then.ToString("MMM d", CultureInfo.CurrentCulture);
        }

        void FillGoals() {
            goal.Items.Clear(); goal.Items.AddRange(Modes); goal.SelectedIndex = simType.SelectedIndex == 1 ? 0 : 1;
        }

        void SetStatus(string text, Color color) { status.Text = text; status.ForeColor = color; }

        void Run() {
            if (current == null) return;
            var o = new Options();
            o.TargetHealth = (double)targetHp.Value; o.TargetShadowResist = (double)targetResist.Value; o.UseTrinkets = trinkets.Checked;
            o.RaidSeconds = (double)raidSeconds.Value; o.RaidPotions = potions.Checked; options = o;
            Cursor = Cursors.WaitCursor;
            try {
                var watch = System.Diagnostics.Stopwatch.StartNew();
                plan = Gear.Optimize(current, o, AllModes);
                int bank = current.Items.Count(x => x.Bank > 0 && x.Usable);
                if (current.BankAt <= 0 || bank == 0)
                    SetStatus("Your bank gear isn't included. In game: open your bank, click Sim, /reload, then press Load from WoW.", Warn);
                else
                    SetStatus(string.Format("Checked {0:N0} gear combinations in {1:0.0} s, including {2} bank items (bank read {3}).", plan.Tried, watch.Elapsed.TotalSeconds, bank, Age(current.BankAt).Replace("saved ", "")), Muted);
            } catch (Exception e) { plan = null; SetStatus("Couldn't run the sim: " + e.Message, Bad); }
            finally { Cursor = Cursors.Default; }
            ShowResults();
        }

        void ShowResults() {
            table.Items.Clear(); details.Text = "";
            table.Columns.Clear();
            var modes = Modes; int w = (860 - 200 - 24) / (modes.Length + 1);
            table.Columns.Add("", 200); table.Columns.Add("Now", w, HorizontalAlignment.Right);
            foreach (var m in modes) table.Columns.Add(m == "Healing (whole fight)" ? "Heal (fight)" : m == "Burst healing" ? "Heal (burst)" : m, w, HorizontalAlignment.Right);
            if (plan == null) return;
            var cols = new List<Result> { plan.Current };
            foreach (var m in modes) { Result r; cols.Add(plan.Best.TryGetValue(m, out r) ? r : plan.Current); }
            Row("Shadow spell damage", cols, r => r.SpellDamage.ToString("0"), r => r.SpellDamage, true);
            Row("Health", cols, r => r.Health.ToString("N0"), r => r.Health, true);
            Row("Mana", cols, r => r.Mana.ToString("N0"), r => r.Mana, true);
            Row("Spell hit", cols, r => r.Hit.ToString("0.#") + "%", r => r.Hit, true);
            Row("Mind Blast crit", cols, r => r.Crit.ToString("0.0") + "%", r => r.Crit, true);
            Row("Spell haste (sheet)", cols, r => r.Haste.ToString("0.#") + "%", r => r.Haste, true);
            Row("Armor", cols, r => r.Armor.ToString("N0"), r => r.Armor, true);
            Row("Time to kill", cols, r => r.Kill >= 99 ? "no kill" : r.Kill.ToString("0.0") + " s", r => r.Kill, false);
            Row("Time to kill, no trinket", cols, r => r.KillNoTrinket >= 99 ? "no kill" : r.KillNoTrinket.ToString("0.0") + " s", r => r.KillNoTrinket, false);
            Row("Damage in first 6 s", cols, r => r.Burst6.ToString("N0"), r => r.Burst6, true);
            Row("Kills per full mana bar", cols, r => r.Fights.ToString("0.0"), r => r.Fights, true);
            Row("Survive vs melee (eff. HP)", cols, r => r.EffectiveHealth.ToString("N0"), r => r.EffectiveHealth, true);
            Row("Healing power", cols, r => r.Healing.ToString("0"), r => r.Healing, true);
            Row("Healing per second (fight)", cols, r => r.HealHps.ToString("0"), r => r.HealHps, true);
            Row("Burst healing (Flash, 10 s)", cols, r => r.HealBurst.ToString("0"), r => r.HealBurst, true);
            Row("Boss DPS (whole fight)", cols, r => r.StaticDps.ToString("0"), r => r.StaticDps, true);
            Row("Boss hit chance", cols, r => r.RaidHit.ToString("0.#") + "%", r => r.RaidHit, true);

            string mode = modes[Math.Max(0, Math.Min(modes.Length - 1, goal.SelectedIndex))];
            Result best; plan.Best.TryGetValue(mode, out best);
            var lines = new List<string>();
            lines.Add(mode.ToUpperInvariant() + " SET for " + current.Label);
            if (best == null) lines.Add("No result.");
            else {
                var swaps = Gear.Swaps(plan.Current.Gear, best.Gear);
                if (swaps.Count == 0) lines.Add("What you're wearing is already the best " + mode.ToLowerInvariant() + " set you own.");
                else { lines.Add("Swap these (everything else stays):"); foreach (var l in swaps) lines.Add("  • " + l); }
                if (best.ActiveSets.Count > 0) lines.Add("Set bonuses on: " + string.Join(", ", best.ActiveSets));
            }
            lines.Add("");
            lines.Add(Explain(mode));
            lines.Add("Model (WoW Forever numbers, from wowsims/forever): Shadow Word: Pain, Devouring Plague, Mind Blast, Shadow Word: Death, Mind Flay filler, with your Forever talents. On-use trinkets are popped at the start and again off cooldown. Boss: level 63 (17% base miss, small level resist), wand when out of mana. SW:Death backlash isn't counted.");
            lines.Add("");
            try { lines.AddRange(Talents.Report(current, options ?? new Options(), plan.Current.Gear)); } catch (Exception e) { lines.Add("Talent check failed: " + e.Message); }
            var notes = Gear.Notes(current);
            if (notes.Count > 0) { lines.Add(""); lines.AddRange(notes); }
            details.Text = string.Join(Environment.NewLine, lines);
        }

        static string Explain(string mode) {
            switch (mode) {
                case "Burst": return "Burst: fastest PvP kill.";
                case "Tanky": return "Tanky: survival first, still killing.";
                case "Max Stamina": return "Max Stamina: the most health your gear can give (spell damage breaks ties).";
                case "Static DPS": return "Static DPS: most damage over the whole boss fight, mana included.";
                case "Spell power": return "Spell power: the highest shadow spell damage on your sheet.";
                case "Healing power": return "Healing power: the highest +healing on your sheet.";
                case "Healing (whole fight)": return "Healing (whole fight): most healing over the boss fight on one target, Renew kept up and Greater Heal between, mana included (overhealing not counted).";
                case "Burst healing": return "Burst healing: most healing per second from Flash Heal over 10 s (mana not a limit).";
                default: return "Balanced: how long you survive compared with how long the PvP kill takes.";
            }
        }

        void Row(string name, List<Result> cols, Func<Result, string> text, Func<Result, double> value, bool higherIsBetter) {
            var item = new ListViewItem(name); item.UseItemStyleForSubItems = false; item.ForeColor = Muted; item.BackColor = Panel;
            double now = value(cols[0]);
            for (int i = 0; i < cols.Count; i++) {
                var sub = item.SubItems.Add(text(cols[i])); sub.BackColor = Panel; sub.ForeColor = Fore;
                // Color only when the shown number changes (10.7 vs 10.7 stays plain).
                if (i > 0 && text(cols[i]) != text(cols[0])) {
                    double d = value(cols[i]) - now;
                    sub.ForeColor = (d > 0) == higherIsBetter ? Good : Bad;
                }
            }
            table.Items.Add(item);
        }
    }
}
