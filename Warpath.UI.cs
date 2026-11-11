using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

namespace Warpath {
    public static class Theme {
        public static readonly Color Window=ColorTranslator.FromHtml("#07040C"), Panel=ColorTranslator.FromHtml("#120A1E"),
            Input=ColorTranslator.FromHtml("#0A0512"), Accent=ColorTranslator.FromHtml("#8B3DFF"), Hover=ColorTranslator.FromHtml("#A35CFF"),
            Highlight=ColorTranslator.FromHtml("#C77DFF"), Text=ColorTranslator.FromHtml("#F3E9FF"), Secondary=ColorTranslator.FromHtml("#B08CE6"),
            Success=ColorTranslator.FromHtml("#4ADE80"), Warning=ColorTranslator.FromHtml("#FFC450"), Error=ColorTranslator.FromHtml("#F87171"),
            Border=ColorTranslator.FromHtml("#4B2A7A");
        public static Font Serif(float size) {
            using(var fonts=new System.Drawing.Text.InstalledFontCollection())
                foreach(var f in fonts.Families) if(f.Name.Equals("Cinzel",StringComparison.OrdinalIgnoreCase)) return new Font("Cinzel",size,FontStyle.Bold);
            return new Font("Georgia",size,FontStyle.Bold);
        }
        public static GraphicsPath Round(RectangleF r,float radius) {
            var p=new GraphicsPath();float d=radius*2;
            p.AddArc(r.X,r.Y,d,d,180,90);p.AddArc(r.Right-d,r.Y,d,d,270,90);
            p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.X,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;
        }
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h,int a,ref int v,int s);
        public static void DarkTitle(Form f) { try {int v=1;DwmSetWindowAttribute(f.Handle,20,ref v,4);}catch{} }
        public static Label Label(string text,int x,int y,int w,int h) {
            return new Label {Text=text,Location=new Point(x,y),Size=new Size(w,h),BackColor=Color.Transparent,ForeColor=Text,Font=new Font("Segoe UI",10)};
        }
        public static LinkLabel Link(string text,int x,int y,int w) {
            return new LinkLabel {Text=text,Location=new Point(x,y),Size=new Size(w,26),BackColor=Color.Transparent,
                Font=new Font("Segoe UI",10),LinkColor=Secondary,ActiveLinkColor=Highlight,VisitedLinkColor=Secondary,LinkBehavior=LinkBehavior.HoverUnderline};
        }
        public static TextBox TextBox(int x,int y,int w) {
            return new TextBox {Location=new Point(x,y),Size=new Size(w,30),BackColor=Input,ForeColor=Text,BorderStyle=BorderStyle.FixedSingle,Font=new Font("Segoe UI",11)};
        }
    }
    public class DarkForm:Form {
        public DarkForm() {
            DoubleBuffered=true;SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);
            BackColor=Theme.Window;ForeColor=Theme.Text;Font=new Font("Segoe UI",10);StartPosition=FormStartPosition.CenterScreen;
            AutoScaleMode=AutoScaleMode.Dpi;FormBorderStyle=FormBorderStyle.FixedSingle;MaximizeBox=false;
            BackgroundImageLayout=ImageLayout.Stretch;
        }
        protected override void OnHandleCreated(EventArgs e){base.OnHandleCreated(e);Theme.DarkTitle(this);}
    }
    public class Card:Panel {
        public Card(){DoubleBuffered=true;BackColor=Color.Transparent;}
        protected override void OnPaint(PaintEventArgs e) {
            e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            using(var path=Theme.Round(new RectangleF(0,0,Width-1,Height-1),8))
            using(var fill=new SolidBrush(Color.FromArgb(220,Theme.Panel)))
            using(var pen=new Pen(Theme.Border,1)){e.Graphics.FillPath(fill,path);e.Graphics.DrawPath(pen,path);}
            base.OnPaint(e);
        }
    }
    public class PurpleButton:Button {
        public bool LargeAction {get;set;}
        public bool AllSet {get;set;}
        public float Glow {get;set;}
        bool hover;
        public PurpleButton() {
            FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;BackColor=Theme.Accent;ForeColor=Color.White;
            Font=new Font("Segoe UI",11,FontStyle.Bold);Cursor=Cursors.Hand;DoubleBuffered=true;
            SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);
        }
        protected override void OnMouseEnter(EventArgs e){hover=true;Invalidate();base.OnMouseEnter(e);}
        protected override void OnMouseLeave(EventArgs e){hover=false;Invalidate();base.OnMouseLeave(e);}
        protected override void OnPaint(PaintEventArgs e) {
            var g=e.Graphics;g.Clear(Theme.Window);g.SmoothingMode=SmoothingMode.AntiAlias;
            Color fill=AllSet?Color.FromArgb(22,78,48):(hover&&Enabled?Theme.Hover:Theme.Accent);
            if(!Enabled&&!AllSet) fill=Color.FromArgb(75,36,115);
            using(var p=Theme.Round(new RectangleF(4,4,Width-9,Height-9),8))
            using(var b=new SolidBrush(fill)) {
                if(LargeAction&&Enabled) {
                    for(int i=4;i>=1;i--) using(var glow=new Pen(Color.FromArgb((int)(12+Glow*20),Theme.Highlight),i*2+1)) g.DrawPath(glow,p);
                }
                g.FillPath(b,p);
                using(var pen=new Pen(AllSet?Theme.Success:Color.FromArgb((int)(110+Glow*145),Theme.Highlight),1.5f))g.DrawPath(pen,p);
            }
            TextRenderer.DrawText(g,Text,Font,ClientRectangle,AllSet?Theme.Success:Color.White,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine);
            if(Focused)ControlPaint.DrawFocusRectangle(g,new Rectangle(10,10,Width-20,Height-20),Theme.Text,fill);
        }
    }
    public class Progress:Control {
        int value;
        public int Value {get{return value;}set{this.value=Math.Max(0,Math.Min(100,value));Invalidate();}}
        public Progress(){DoubleBuffered=true;Height=14;BackColor=Theme.Panel;}
        protected override void OnPaint(PaintEventArgs e) {
            var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;
            using(var p=Theme.Round(new RectangleF(0,0,Width-1,Height-1),5))
            using(var b=new SolidBrush(Theme.Panel))using(var pen=new Pen(Theme.Border)){
                g.FillPath(b,p);g.SetClip(p);
                using(var accent=new SolidBrush(Theme.Highlight))g.FillRectangle(accent,0,0,Width*value/100f,Height);
                g.ResetClip();g.DrawPath(pen,p);
            }
        }
    }
    public class AddonRow {
        public string Repo,Name,Description,Status;
        public bool Checked,Owner,Installed,Needs,Verified;
        public AddonRow(string repo,string name,string description,string status,bool check,bool owner,bool installed,bool needs,bool verified) {
            Repo=repo;Name=name;Description=description;Status=status;Checked=check;Owner=owner;Installed=installed;Needs=needs;Verified=verified;
        }
    }
    public class AddonList:Control {
        public readonly List<AddonRow> Rows=new List<AddonRow>();
        public event EventHandler SelectionChanged;
        public int RowHeight=46;
        int focusIndex=0;
        public string EmptyText="No addons are shared for this game yet.";
        public AddonList(){DoubleBuffered=true;BackColor=Theme.Panel;ForeColor=Theme.Text;TabStop=true;Cursor=Cursors.Hand;}
        public void ClearRows(){Rows.Clear();Invalidate();}
        public void AddRow(AddonRow row){Rows.Add(row);Invalidate();}
        protected override bool IsInputKey(Keys key){return key==Keys.Up||key==Keys.Down||key==Keys.Space||base.IsInputKey(key);}
        void Toggle(int index) {
            if(!Enabled||index<0||index>=Rows.Count)return;
            Rows[index].Checked=!Rows[index].Checked;focusIndex=index;Invalidate();
            if(SelectionChanged!=null)SelectionChanged(this,EventArgs.Empty);
        }
        protected override void OnMouseDown(MouseEventArgs e){Focus();if(e.Button==MouseButtons.Left)Toggle(e.Y/RowHeight);base.OnMouseDown(e);}
        protected override void OnKeyDown(KeyEventArgs e) {
            if(e.KeyCode==Keys.Space){Toggle(focusIndex);e.Handled=true;}
            if(e.KeyCode==Keys.Up){focusIndex=Math.Max(0,focusIndex-1);e.Handled=true;Invalidate();}
            if(e.KeyCode==Keys.Down){focusIndex=Math.Min(Rows.Count-1,focusIndex+1);e.Handled=true;Invalidate();}base.OnKeyDown(e);
        }
        protected override void OnGotFocus(EventArgs e){base.OnGotFocus(e);Invalidate();}
        protected override void OnLostFocus(EventArgs e){base.OnLostFocus(e);Invalidate();}
        protected override void OnPaint(PaintEventArgs e) {
            var g=e.Graphics;g.Clear(Theme.Panel);g.SmoothingMode=SmoothingMode.AntiAlias;
            if(Rows.Count==0){TextRenderer.DrawText(g,EmptyText,Font,new Rectangle(12,24,Width-24,70),Theme.Secondary,TextFormatFlags.WordBreak);return;}
            using(var nameFont=new Font("Segoe UI",11,FontStyle.Bold))using(var small=new Font("Segoe UI",10)) {
                for(int i=0;i<Rows.Count;i++) {
                    var row=Rows[i];int y=i*RowHeight;
                    if(row.Checked)using(var b=new SolidBrush(Color.FromArgb(36,18,57)))g.FillRectangle(b,0,y,Width,RowHeight-2);
                    using(var p=Theme.Round(new RectangleF(12,y+15,23,23),4))
                    using(var b=new SolidBrush(row.Checked?Theme.Accent:Theme.Input))using(var pen=new Pen(Theme.Highlight,1.5f)){
                        g.FillPath(b,p);g.DrawPath(pen,p);
                        if(row.Checked)using(var check=new Pen(Color.White,2.5f))g.DrawLines(check,new Point[]{new Point(17,y+26),new Point(22,y+31),new Point(31,y+20)});
                    }
                    Color status=row.Status=="Update ready"?Theme.Warning:(row.Installed?Theme.Success:Theme.Secondary);
                    int pillWidth=TextRenderer.MeasureText(row.Status,small).Width+18;
                    int pillX=Width-pillWidth-12;
                    TextRenderer.DrawText(g,row.Name,nameFont,new Rectangle(48,y+1,Math.Max(80,pillX-58),23),Theme.Text,TextFormatFlags.EndEllipsis|TextFormatFlags.SingleLine);
                    TextRenderer.DrawText(g,row.Description,small,new Rectangle(48,y+24,Math.Max(80,pillX-58),22),Theme.Secondary,TextFormatFlags.EndEllipsis|TextFormatFlags.SingleLine);
                    using(var p=Theme.Round(new RectangleF(pillX,y+17,pillWidth,24),12))using(var pen=new Pen(status))g.DrawPath(pen,p);
                    TextRenderer.DrawText(g,row.Status,small,new Rectangle(pillX,y+17,pillWidth,24),status,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);
                    if(row.Owner) {
                        int nx=48+TextRenderer.MeasureText(row.Name,nameFont).Width+7;
                        if(nx+66<pillX)TextRenderer.DrawText(g,"OWNER",small,new Rectangle(nx,y+5,66,24),Theme.Warning,TextFormatFlags.VerticalCenter);
                    }
                    if(Focused&&focusIndex==i)ControlPaint.DrawFocusRectangle(g,new Rectangle(3,y+2,Width-7,RowHeight-5),Theme.Highlight,Theme.Panel);
                }
            }
        }
    }
    public class GamePicker:ComboBox {
        public GamePicker() {
            DropDownStyle=ComboBoxStyle.DropDownList;DrawMode=DrawMode.OwnerDrawFixed;ItemHeight=27;
            FlatStyle=FlatStyle.Flat;BackColor=Theme.Input;ForeColor=Theme.Text;Font=new Font("Segoe UI",11);
        }
        protected override void OnDrawItem(DrawItemEventArgs e) {
            using(var b=new SolidBrush((e.State&DrawItemState.Selected)!=0?Theme.Border:Theme.Input))e.Graphics.FillRectangle(b,e.Bounds);
            if(e.Index>=0)TextRenderer.DrawText(e.Graphics,Items[e.Index].ToString(),Font,e.Bounds,Theme.Text,TextFormatFlags.VerticalCenter|TextFormatFlags.Left);
        }
        protected override void WndProc(ref Message m) {
            base.WndProc(ref m);
            if(m.Msg==15)using(var g=Graphics.FromHwnd(Handle))PaintDark(g);
            else if((m.Msg==791||m.Msg==792)&&m.WParam!=IntPtr.Zero)using(var g=Graphics.FromHdc(m.WParam))PaintDark(g);
        }
        void PaintDark(Graphics g) {
            using(var fill=new SolidBrush(Theme.Input))g.FillRectangle(fill,0,0,Width,Height);
            TextRenderer.DrawText(g,Text,Font,new Rectangle(10,0,Width-42,Height),Theme.Text,TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine);
            using(var pen=new Pen(Focused?Theme.Highlight:Theme.Border))g.DrawRectangle(pen,0,0,Width-1,Height-1);
            using(var fill=new SolidBrush(Theme.Highlight))g.FillPolygon(fill,new Point[]{new Point(Width-21,Height/2-2),new Point(Width-11,Height/2-2),new Point(Width-16,Height/2+4)});
        }
    }
    public class MainWindow:DarkForm {
        public readonly GamePicker Game=new GamePicker();
        public readonly TextBox Folder=Theme.TextBox(16,43,550);
        public readonly PurpleButton Browse=new PurpleButton(), Action=new PurpleButton(), EditCatalog=new PurpleButton();
        public readonly AddonList Addons=new AddonList();
        public readonly Label FolderCheck,Status,Done,OwnerBadge,WowWarning;
        public readonly LinkLabel Check,OwnerLink,Lock;
        public readonly Progress Progress=new Progress();
        readonly Timer pulse=new Timer();double phase;
        public MainWindow() {
            Text="VoidMark Warpath";ClientSize=new Size(760,900);
            var gameCard=new Card {Location=new Point(22,206),Size=new Size(716,96)};
            var folderCard=new Card {Location=new Point(22,312),Size=new Size(716,126)};
            var addonCard=new Card {Location=new Point(22,448),Size=new Size(716,278)};
            Controls.AddRange(new Control[]{gameCard,folderCard,addonCard});
            var title=Theme.Label("STEP 1 — PICK YOUR GAME",16,10,680,28);title.Font=Theme.Serif(14);title.ForeColor=Theme.Highlight;gameCard.Controls.Add(title);
            Game.Location=new Point(16,46);Game.Size=new Size(684,34);Game.Items.AddRange(new object[]{"WoW Forever","WoW Classic Era"});gameCard.Controls.Add(Game);
            title=Theme.Label("STEP 2 — FIND YOUR ADDONS FOLDER",16,10,680,28);title.Font=Theme.Serif(14);title.ForeColor=Theme.Highlight;folderCard.Controls.Add(title);
            Folder.Size=new Size(550,30);folderCard.Controls.Add(Folder);
            Browse.Text="Browse";Browse.SetBounds(574,38,128,40);folderCard.Controls.Add(Browse);
            FolderCheck=Theme.Label("",16,79,684,25);folderCard.Controls.Add(FolderCheck);
            WowWarning=Theme.Label("",16,101,684,23);WowWarning.ForeColor=Theme.Warning;folderCard.Controls.Add(WowWarning);
            title=Theme.Label("STEP 3 — CHOOSE ADDONS",16,10,380,28);title.Font=Theme.Serif(14);title.ForeColor=Theme.Highlight;addonCard.Controls.Add(title);
            Check=Theme.Link("Check for updates",540,14,162);addonCard.Controls.Add(Check);
            Addons.SetBounds(8,43,700,230);addonCard.Controls.Add(Addons);
            // Footer/working area has enough room for a two-line completion message.
            Action.LargeAction=true;Action.Text="▶  CLICK HERE TO INSTALL";Action.Font=Theme.Serif(20);Action.SetBounds(18,730,724,76);Controls.Add(Action);
            Progress.SetBounds(24,812,712,12);Controls.Add(Progress);
            ClientSize=new Size(760,910);
            Status=Theme.Label("Choose your game and folder to get started.",24,831,712,26);Controls.Add(Status);
            Done=Theme.Label("",24,856,712,28);Done.Font=new Font("Segoe UI",11,FontStyle.Bold);Done.ForeColor=Theme.Success;Controls.Add(Done);
            var version=Theme.Label("Warpath v3.0.0",24,885,240,24);version.ForeColor=Theme.Secondary;Controls.Add(version);
            OwnerLink=Theme.Link("Owner",678,885,65);Controls.Add(OwnerLink);
            OwnerBadge=Theme.Label("OWNER MODE",24,179,175,25);OwnerBadge.Font=new Font("Segoe UI",11,FontStyle.Bold);OwnerBadge.ForeColor=Theme.Warning;OwnerBadge.Visible=false;Controls.Add(OwnerBadge);
            Lock=Theme.Link("Lock",205,179,65);Lock.Visible=false;Controls.Add(Lock);
            EditCatalog.Text="Edit public catalog";EditCatalog.SetBounds(530,171,208,34);EditCatalog.Visible=false;Controls.Add(EditCatalog);
            pulse.Interval=50;pulse.Tick+=delegate{phase+=0.07;Action.Glow=(float)((Math.Sin(phase)+1)/2);if(Action.Enabled)Action.Invalidate();};pulse.Start();
            FormClosed+=delegate{pulse.Stop();pulse.Dispose();};
        }
        public void ShowOwner(bool value){OwnerBadge.Visible=value;Lock.Visible=value;EditCatalog.Visible=value;OwnerLink.Visible=!value;}
        public void ApplyArt(string path,string iconPath) {
            if(File.Exists(path)) {
                using(var source=Image.FromFile(path)) {
                    BackgroundImage=Art.Background(source,ClientSize.Width,ClientSize.Height);
                    var banner=new PictureBox {Location=new Point(0,0),Size=new Size(760,190),SizeMode=PictureBoxSizeMode.Normal,BackColor=Color.Transparent,Image=Art.Banner(source,760,190)};
                    Controls.Add(banner);banner.SendToBack();
                    FormClosed+=delegate{banner.Image.Dispose();};
                    if(!File.Exists(iconPath))try{Art.CreateIcon(source,iconPath);}catch{}
                }
            } else {
                var fallback=Theme.Label("VOIDMARK WARPATH",24,55,712,80);fallback.Font=Theme.Serif(30);fallback.ForeColor=Theme.Highlight;Controls.Add(fallback);fallback.SendToBack();
            }
            if(File.Exists(iconPath))try{Icon=new Icon(iconPath);}catch{}
        }
        protected override void Dispose(bool disposing){if(disposing&&BackgroundImage!=null)BackgroundImage.Dispose();base.Dispose(disposing);}
    }
    public static class Art {
        public static Bitmap Banner(Image source,int w,int h) {
            var bmp=new Bitmap(w,h);using(var g=Graphics.FromImage(bmp)) {
                g.Clear(Theme.Window);g.InterpolationMode=InterpolationMode.HighQualityBicubic;
                float scale=Math.Min(w/(float)source.Width,h/(float)source.Height);float rw=source.Width*scale,rh=source.Height*scale;
                g.DrawImage(source,(w-rw)/2,0,rw,rh);
                using(var fade=new LinearGradientBrush(new Rectangle(0,h-55,w,55),Color.Transparent,Theme.Window,90f))g.FillRectangle(fade,0,h-55,w,55);
            }return bmp;
        }
        public static Bitmap Background(Image source,int w,int h) {
            // Downsample the right-hand flame crop before enlarging it: one-time soft blur.
            using(var tiny=new Bitmap(38,49)) {
                using(var g=Graphics.FromImage(tiny)){g.InterpolationMode=InterpolationMode.HighQualityBilinear;g.DrawImage(source,new Rectangle(0,0,38,49),new Rectangle(source.Width*2/3,0,source.Width-source.Width*2/3,source.Height),GraphicsUnit.Pixel);}
                var bmp=new Bitmap(w,h);using(var g=Graphics.FromImage(bmp)) {
                    g.InterpolationMode=InterpolationMode.HighQualityBilinear;
                    using(var ia=new ImageAttributes()) {
                        ia.SetColorMatrix(new ColorMatrix(new float[][]{new float[]{.55f,0,0,0,0},new float[]{0,.55f,0,0,0},new float[]{0,0,.55f,0,0},new float[]{0,0,0,1,0},new float[]{0,0,0,0,1}}));
                        g.DrawImage(tiny,new Rectangle(0,0,w,h),0,0,tiny.Width,tiny.Height,GraphicsUnit.Pixel,ia);
                    }
                    using(var ellipse=new GraphicsPath()) {
                        ellipse.AddEllipse(-w/3,-h/3,w*5/3,h*5/3);
                        using(var vignette=new PathGradientBrush(ellipse)) {vignette.CenterColor=Color.Transparent;vignette.SurroundColors=new Color[]{Color.FromArgb(235,Theme.Window)};g.FillRectangle(vignette,0,0,w,h);}
                    }
                    using(var veil=new SolidBrush(Color.FromArgb(75,Theme.Window)))g.FillRectangle(veil,0,0,w,h);
                }return bmp;
            }
        }
        public static void CreateIcon(Image source,string path) {
            var images=new List<byte[]>();int[] sizes={16,32,48,256};
            foreach(int size in sizes)using(var bmp=new Bitmap(size,size)) {
                using(var g=Graphics.FromImage(bmp)) {
                    g.Clear(Theme.Window);g.InterpolationMode=InterpolationMode.HighQualityBicubic;
                    // Use the left-hand emblem rather than shrinking the whole wordmark.
                    int side=Math.Min(source.Height,source.Width);g.DrawImage(source,new Rectangle(0,0,size,size),new Rectangle(0,0,side,side),GraphicsUnit.Pixel);
                }
                using(var memory=new MemoryStream()){bmp.Save(memory,ImageFormat.Png);images.Add(memory.ToArray());}
            }
            using(var f=new FileStream(path,FileMode.CreateNew))using(var writer=new BinaryWriter(f)) {
                writer.Write((ushort)0);writer.Write((ushort)1);writer.Write((ushort)4);int offset=6+16*4;
                for(int i=0;i<4;i++){writer.Write((byte)(sizes[i]==256?0:sizes[i]));writer.Write((byte)(sizes[i]==256?0:sizes[i]));writer.Write((byte)0);writer.Write((byte)0);writer.Write((ushort)1);writer.Write((ushort)32);writer.Write(images[i].Length);writer.Write(offset);offset+=images[i].Length;}
                foreach(var data in images)writer.Write(data);
            }
        }
    }
    public static class OwnerGate {
        const string Digest="043950549e7ce0e1e95856516147886ef890b7b8676842c9b4f8135a8d27c5f2";
        static int failures=0;static DateTime lockedUntil=DateTime.MinValue;
        public static bool Verify(string value) {
            using(var sha=SHA256.Create()) {
                string hex=BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(value))).Replace("-","").ToLowerInvariant();
                int difference=0;for(int i=0;i<Digest.Length;i++)difference|=hex[i]^Digest[i];return difference==0;
            }
        }
        public static bool Ask(IWin32Window parent) {
            using(var dialog=new DarkForm()) {
                dialog.Text="Owner access";dialog.ClientSize=new Size(400,215);dialog.StartPosition=FormStartPosition.CenterParent;dialog.MinimizeBox=false;
                var prompt=Theme.Label("Enter the owner password",22,18,350,28);dialog.Controls.Add(prompt);
                var input=Theme.TextBox(22,54,356);input.UseSystemPasswordChar=true;dialog.Controls.Add(input);
                var message=Theme.Label("",22,92,356,28);message.ForeColor=Theme.Error;dialog.Controls.Add(message);
                var submit=new PurpleButton{Text="Unlock",Location=new Point(20,133),Size=new Size(180,48)};
                var cancel=new PurpleButton{Text="Cancel",Location=new Point(208,133),Size=new Size(172,48),DialogResult=DialogResult.Cancel};
                dialog.Controls.AddRange(new Control[]{submit,cancel});dialog.AcceptButton=submit;dialog.CancelButton=cancel;
                var timer=new Timer{Interval=100};var shake=new Timer{Interval=35};Point origin=new Point();int shakeTick=0;
                shake.Tick+=delegate{shakeTick++;dialog.Left=origin.X+(shakeTick%2==0?-8:8);if(shakeTick>=10){shake.Stop();dialog.Location=origin;}};
                Action update=delegate {
                    int remaining=(int)Math.Ceiling((lockedUntil-DateTime.UtcNow).TotalSeconds);
                    bool locked=remaining>0;submit.Enabled=!locked;input.Enabled=!locked;
                    if(locked)message.Text="Wrong password. Try again in "+remaining+" seconds.";
                    else if(message.Text.Contains("Try again in")){message.Text="Enter your password to try again.";input.Focus();}
                };
                submit.Click+=delegate {
                    if(DateTime.UtcNow<lockedUntil)return;
                    string value=input.Text;input.Clear();
                    if(Verify(value)){failures=0;dialog.DialogResult=DialogResult.OK;dialog.Close();return;}
                    failures++;message.Text="Wrong password";
                    if(!shake.Enabled){origin=dialog.Location;shakeTick=0;shake.Start();}
                    if(failures>=3){failures=0;lockedUntil=DateTime.UtcNow.AddSeconds(30);input.Enabled=false;submit.Enabled=false;}
                    input.Focus();
                };
                timer.Tick+=delegate{update();};dialog.Shown+=delegate{update();input.Focus();timer.Start();};
                try{return dialog.ShowDialog(parent)==DialogResult.OK;}finally{timer.Stop();shake.Stop();timer.Dispose();shake.Dispose();input.Clear();}
            }
        }
    }
}
