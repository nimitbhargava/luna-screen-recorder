using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Threading;
using Luna.Core;
using Forms = System.Windows.Forms;

namespace Luna.App;

public partial class App : Application
{
    private Mutex? instance;
    private EventWaitHandle? activation;
    private RegisteredWaitHandle? activationWait;
    private HwndSource? messages;
    private Forms.NotifyIcon? tray;
    private Forms.ToolStripItem? trayState;
    private Icon? trayIcon;
    private string? trayIconState;
    private Window? library;
    private readonly Dictionary<int, string> hotkeys = new();
    internal Settings Settings { get; private set; } = new();
    internal event Action? SettingsSaved;
    private SettingsStore? store;
    internal string Recordings { get; private set; } = "";
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var scope = Environment.UserName;
        instance = new Mutex(true, "Local\\Luna.Windows." + scope, out var created);
        activation = new EventWaitHandle(false, EventResetMode.AutoReset, "Local\\Luna.Windows.Open." + scope);
        if (!created) { activation.Set(); Shutdown(); return; }
        activationWait = ThreadPool.RegisterWaitForSingleObject(activation, (_, _) => Dispatcher.BeginInvoke(OpenLibrary), null, Timeout.Infinite, false);
        store = new SettingsStore(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Luna", "settings.json"));
        try { var result = store.Load(); Settings = result.Settings; if (result.Recovered) Dispatcher.BeginInvoke(() => ShowNotice("Settings were corrupt. Defaults restored.")); }
        catch (Exception ex) { Log(ex.Message); ShowNotice("Settings could not be loaded: " + ex.Message); }
        Recordings = Path.Combine(Native.Videos(), "ScreenRecordings"); Directory.CreateDirectory(Recordings);
        if (Settings.AutoDelete) CleanUp();
        messages = new HwndSource(new HwndSourceParameters("Luna messages") { Width = 0, Height = 0, WindowStyle = 0 });
        messages.AddHook(Receive);
        var id = 1;
        foreach (var (action, combo) in Settings.Hotkeys)
        {
            try { var key = Hotkey.Parse(combo); if (Native.RegisterHotKey(messages.Handle, id, key.Modifiers | 0x4000, key.Key)) hotkeys[id] = action; else ShowNotice(combo + " is used by another app. Change it in settings.json."); }
            catch (FormatException) { ShowNotice("Invalid shortcut: " + combo); }
            id++;
        }
        tray = new Forms.NotifyIcon { Text = "Luna", Visible = true };
        tray.MouseClick += (_, args) => { if (args.Button == Forms.MouseButtons.Left) OpenLibrary(); };
        RefreshTray(); UpdateBar();
        if (!Settings.OnboardingCompleted) ShowWelcome();
    }
    private IntPtr Receive(IntPtr hwnd, int msg, IntPtr w, IntPtr l, ref bool handled)
    {
        if (msg == 0x312 && hotkeys.TryGetValue(w.ToInt32(), out var action)) { handled = true; if (action == "library") OpenLibrary(); else if (action == "area") RequestRecording(CaptureMode.Area); else if (action == "picker") RequestRecording(CaptureMode.Window); else if (action == "fullScreen") RequestRecording(CaptureMode.Screen); else if (action == "stop") StopRecording(); else if (action == "pause") PauseRecording(); else if (action == "floatingBar") ToggleBar(); }
        return IntPtr.Zero;
    }
    private static Icon CreateTrayIcon(string state)
    {
        using var bitmap = new Bitmap(32, 32); using (var g = Graphics.FromImage(bitmap)) { g.Clear(System.Drawing.Color.Transparent); g.FillEllipse(Brushes.White, 2, 2, 28, 28); g.FillEllipse(state == "recording" ? Brushes.Red : state is "paused" or "saving" ? Brushes.DarkOrange : Brushes.DarkSlateBlue, 5, 5, 22, 22); g.FillEllipse(Brushes.White, 11, 11, 10, 10); }
        var handle = bitmap.GetHicon();
        try { using var icon = Icon.FromHandle(handle); return (Icon)icon.Clone(); }
        finally { Native.DestroyIcon(handle); }
    }
    private void RefreshTrayStatus()
    {
        if (tray == null) return;
        var state = IsSaving ? "saving" : IsRecording ? IsPaused ? "paused" : "recording" : "idle";
        tray.Text = IsSaving ? "Luna: saving" : IsRecording ? "Luna: " + state + " " + RecordingTime : "Luna";
        if (trayState != null) trayState.Text = IsSaving ? SavingStatus : (IsPaused ? "Paused (" : "Recording (") + RecordingTime + ")";
        if (trayIconState != state)
        {
            var old = trayIcon; trayIcon = CreateTrayIcon(state); tray.Icon = trayIcon; trayIconState = state; old?.Dispose();
        }
    }
    private void RefreshTray()
    {
        if (tray == null) return;
        var menu = new Forms.ContextMenuStrip();
        trayState = null;
        if (IsSaving) { trayState = menu.Items.Add(SavingStatus); trayState.Enabled = false; }
        else if (IsRecording)
        {
            trayState = menu.Items.Add((IsPaused ? "Paused (" : "Recording (") + RecordingTime + ")"); trayState.Enabled = false;
            menu.Items.Add(IsPaused ? "Resume Recording" : "Pause Recording", null, (_, _) => PauseRecording());
            menu.Items.Add("Stop Recording", null, (_, _) => StopRecording());
        }
        else
        {
            menu.Items.Add("Record Area...", null, (_, _) => RequestRecording(CaptureMode.Area));
            menu.Items.Add("Record Full Screen", null, (_, _) => RequestRecording(CaptureMode.Screen));
            menu.Items.Add("Choose Window or Screen...", null, (_, _) => RequestRecording(CaptureMode.Window));
        }
        menu.Items.Add("Floating Recorder Bar", null, (_, _) => ToggleBar());
        var systemAudio = new Forms.ToolStripMenuItem("Record System Audio") { Checked = EffectiveSystemAudio, Enabled = !IsBusy };
        systemAudio.Click += (_, _) => { Settings.SystemAudio = !Settings.SystemAudio; Save(); }; menu.Items.Add(systemAudio);
        var mic = new Forms.ToolStripMenuItem("Microphone: " + EffectiveMicrophone) { Enabled = !IsBusy };
        foreach (var pair in ScreenRecorderLib.Recorder.GetSystemAudioCaptureDevices().Select(d => (d.FriendlyName, d.DeviceName)).Prepend(("System Default", "system_default")).Append(("Mute / No Audio", "none")))
        { var choice = new Forms.ToolStripMenuItem(pair.Item1) { Checked = Settings.Microphone == pair.Item2 }; choice.Click += (_, _) => { Settings.Microphone = pair.Item2; Save(); }; mic.DropDownItems.Add(choice); }
        menu.Items.Add(mic);
        menu.Items.Add("Open Library", null, (_, _) => OpenLibrary());
        menu.Items.Add("Open Recordings Folder", null, (_, _) => OpenFolder());
        menu.Items.Add($"Auto-Delete Old Recordings ({Settings.RetentionDays} Days)", null, (_, _) => { Settings.AutoDelete = !Settings.AutoDelete; Save(); });
        menu.Items.Add("Auto-Copy for LLMs on Stop", null, (_, _) => { Settings.AutoCopyForLlms = !Settings.AutoCopyForLlms; Save(); });
        menu.Items.Add("Settings...", null, (_, _) => ShowSettings());
        menu.Items.Add("Welcome Guide...", null, (_, _) => ShowWelcome());
        menu.Items.Add("Quit Luna", null, (_, _) => Quit());
        Native.Exclude(menu);
        var old = tray.ContextMenuStrip; tray.ContextMenuStrip = menu; old?.Dispose();
        RefreshTrayStatus();
    }
    internal void CleanUp(int? days = null)
    {
        foreach (var path in Retention.Clean(Recordings, DateTimeOffset.Now, days ?? Settings.RetentionDays, recordingPath, probeDirectory: Native.EnsureDirectoryDeletable).Skipped) Log("Retention skipped " + path);
    }
    internal void Save() { try { store?.Save(Settings); if (library is LibraryWindow window) window.RefreshRetentionLabel(); RefreshTray(); SettingsSaved?.Invoke(); } catch (Exception ex) { Log(ex.Message); ShowNotice("Settings could not be saved: " + ex.Message); } }
    internal void OpenFolder() => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Recordings) { UseShellExecute = true });
    internal void OpenLibrary()
    {
        if (library == null) { library = new LibraryWindow(this); library.Closed += (_, _) => library = null; }
        library.Show(); if (library.WindowState == WindowState.Minimized) library.WindowState = WindowState.Normal; library.Activate();
    }
    internal void ShowSettings()
    {
        var panel = new StackPanel { Margin = new Thickness(24) };
        var window = new Window { Title = "Luna Settings", Width = 480, Height = 500, Content = panel }; Native.Exclude(window);
        var copy = AddToggle(panel, "Auto-copy for LLMs on stop", Settings.AutoCopyForLlms, v => Settings.AutoCopyForLlms = v);
        panel.Children.Add(new TextBlock { Text = "Copies the file path and context. The first line is the path.", TextWrapping = TextWrapping.Wrap });
        var audio = AddToggle(panel, "Record system audio", Settings.SystemAudio, v => Settings.SystemAudio = v);
        var days = new ComboBox { ItemsSource = new[] { 7, 15, 30, 60 }, SelectedItem = Settings.RetentionDays, Margin = new Thickness(0, 12, 0, 12) };
        Native.Exclude(days);
        var retention = new CheckBox { Content = $"Auto-delete recordings older than {Settings.RetentionDays} days", IsChecked = Settings.AutoDelete };
        days.SelectionChanged += (_, _) => { if (days.SelectedItem is int selected && selected != Settings.RetentionDays) { Settings.RetentionDays = selected; Save(); } };
        retention.Click += (_, _) => { Settings.AutoDelete = retention.IsChecked == true; Save(); }; panel.Children.Add(retention); panel.Children.Add(days);
        void SyncSettings()
        {
            copy.IsChecked = Settings.AutoCopyForLlms; audio.IsChecked = Settings.SystemAudio;
            days.SelectedItem = Settings.RetentionDays; retention.IsChecked = Settings.AutoDelete;
            retention.Content = $"Auto-delete recordings older than {Settings.RetentionDays} days";
        }
        SettingsSaved += SyncSettings; window.Closed += (_, _) => SettingsSaved -= SyncSettings;
        var folder = new Button { Content = "Open recordings folder", Margin = new Thickness(0, 8, 0, 8) }; folder.Click += (_, _) => OpenFolder(); panel.Children.Add(folder);
        var cleanup = new Button { Content = "Clean up now" }; cleanup.Click += (_, _) => CleanUp(); panel.Children.Add(cleanup);
        foreach (var (action, combo) in Settings.Hotkeys) panel.Children.Add(new TextBlock { Text = action + ": " + combo });
        window.Show();
    }
    private CheckBox AddToggle(Panel panel, string text, bool initial, Action<bool> apply)
    {
        var toggle = new CheckBox { Content = text, IsChecked = initial, Margin = new Thickness(0, 12, 0, 8) }; toggle.Click += (_, _) => { apply(toggle.IsChecked == true); Save(); }; panel.Children.Add(toggle);
        return toggle;
    }
    private void ShowWelcome()
    {
        var panel = new StackPanel { Margin = new Thickness(28) };
        var window = new Window { Title = "Welcome to Luna", Width = 550, Height = 440, Content = panel }; Native.Exclude(window);
        using (var stream = typeof(App).Assembly.GetManifestResourceStream("Luna.Mascot"))
        {
            if (stream != null) { var bitmap = new System.Windows.Media.Imaging.BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad; bitmap.StreamSource = stream; bitmap.EndInit(); panel.Children.Add(new System.Windows.Controls.Image { Source = bitmap, Width = 90, Height = 90, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 12) }); }
        }
        panel.Children.Add(new TextBlock { Text = "Welcome to Luna", FontSize = 26 });
        panel.Children.Add(new TextBlock { Text = "Lightweight screen recording for AI coding workflows.", Margin = new Thickness(0, 12, 0, 12) });
        var copy = new CheckBox { Content = "Auto-copy for LLMs on stop", IsChecked = Settings.AutoCopyForLlms }; panel.Children.Add(copy);
        var retention = new CheckBox { Content = $"Auto-delete recordings after {Settings.RetentionDays} days", IsChecked = Settings.AutoDelete }; panel.Children.Add(retention);
        var savedCopy = Settings.AutoCopyForLlms; var savedDelete = Settings.AutoDelete;
        void SyncWelcome()
        {
            if (savedCopy != Settings.AutoCopyForLlms) copy.IsChecked = Settings.AutoCopyForLlms;
            if (savedDelete != Settings.AutoDelete) retention.IsChecked = Settings.AutoDelete;
            savedCopy = Settings.AutoCopyForLlms; savedDelete = Settings.AutoDelete;
            retention.Content = $"Auto-delete recordings after {Settings.RetentionDays} days";
        }
        SettingsSaved += SyncWelcome; window.Closed += (_, _) => SettingsSaved -= SyncWelcome;
        panel.Children.Add(new TextBlock { Text = "Ctrl+Alt+1 Area • Ctrl+Alt+2 Window • Ctrl+Alt+3 Screen • Ctrl+Alt+S Stop", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 16, 0, 16) });
        panel.Children.Add(new TextBlock { Text = "Luna lives in the system tray. Drag its icon out of the ^ menu onto the taskbar to keep it in view.", TextWrapping = TextWrapping.Wrap });
        var start = new Button { Content = "Get started", IsDefault = true, Margin = new Thickness(0, 18, 0, 0) }; start.Click += (_, _) => { Settings.AutoCopyForLlms = copy.IsChecked == true; Settings.AutoDelete = retention.IsChecked == true; Settings.OnboardingCompleted = true; Save(); window.Close(); }; panel.Children.Add(start);
        window.Show();
    }
    internal void ShowNotice(string text) { Log(text); new ToastWindow(text).Show(); }
    internal static void Log(string text)
    {
        try { var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Luna", "luna.log"); Directory.CreateDirectory(Path.GetDirectoryName(path)!); if (File.Exists(path) && new FileInfo(path).Length > 5 * 1024 * 1024) File.WriteAllText(path, ""); File.AppendAllText(path, DateTimeOffset.Now + " " + text + Environment.NewLine); } catch (IOException) { }
    }
    protected override void OnExit(ExitEventArgs e)
    {
        activationWait?.Unregister(null); activation?.Dispose();
        if (messages != null) { foreach (var id in hotkeys.Keys) Native.UnregisterHotKey(messages.Handle, id); messages.Dispose(); }
        if (tray != null) { tray.Visible = false; tray.Dispose(); }
        trayIcon?.Dispose();
        instance?.Dispose(); base.OnExit(e);
    }
}
