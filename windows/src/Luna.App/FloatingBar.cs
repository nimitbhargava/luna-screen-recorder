using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Luna.Core;
using ScreenRecorderLib;
using CaptureMode = Luna.Core.CaptureMode;

namespace Luna.App;

internal sealed class FloatingBar : Window
{
    private readonly App app;
    private readonly StackPanel row = new() { Orientation = Orientation.Horizontal };
    private CaptureMode mode = CaptureMode.Area;
    private TextBlock? clock;
    internal FloatingBar(App app)
    {
        this.app = app; Height = 48; SizeToContent = SizeToContent.Width; WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        Topmost = true; ShowInTaskbar = false; ShowActivated = false; ResizeMode = ResizeMode.NoResize;
        Native.Exclude(this); Native.NoActivate(this);
        Content = new Border { Background = Brushes.WhiteSmoke, BorderBrush = Brushes.Gray, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(24), Padding = new Thickness(12, 6, 12, 6), Child = row };
        MouseLeftButtonDown += (_, args) => { if (args.OriginalSource is Border) DragMove(); };
        Loaded += (_, _) => { Left = SystemParameters.WorkArea.Left + (SystemParameters.WorkArea.Width - ActualWidth) / 2; Top = SystemParameters.WorkArea.Top + 72; };
        app.SettingsSaved += Refresh; Closed += (_, _) => { app.SettingsSaved -= Refresh; };
        Refresh();
    }
    private Button Add(string text, Action action)
    {
        var button = new Button { Content = text, Padding = new Thickness(9, 2, 9, 2), Margin = new Thickness(3, 0, 3, 0) }; button.Click += (_, _) => action(); row.Children.Add(button); return button;
    }
    internal void Refresh()
    {
        row.Children.Clear(); clock = null;
        if (app.IsSaving)
        {
            clock = new TextBlock { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 6, 0) };
            row.Children.Add(clock); UpdateTime(); Add("Library", app.OpenLibrary); Add("✕", app.ToggleBar); return;
        }
        if (!app.IsRecording)
        {
            foreach (var value in Enum.GetValues<CaptureMode>())
            {
                var button = Add(value.ToString(), () => { mode = value; Refresh(); }); if (mode == value) button.FontWeight = FontWeights.Bold;
            }
        }
        else { clock = new TextBlock { Foreground = app.IsPaused ? Brushes.DarkOrange : Brushes.Red, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 6, 0) }; row.Children.Add(clock); UpdateTime(); }
        var system = Add("System audio: " + (app.EffectiveSystemAudio ? "On" : "Off"), () => { app.Settings.SystemAudio = !app.Settings.SystemAudio; app.Save(); }); system.IsEnabled = !app.IsBusy;
        var microphone = Add(app.EffectiveMicrophone + " ▾", () => { }); microphone.IsEnabled = !app.IsBusy;
        microphone.Click += (_, _) => { microphone.ContextMenu = MicrophoneMenu(app); microphone.ContextMenu.PlacementTarget = microphone; microphone.ContextMenu.IsOpen = true; };
        if (app.IsRecording) { Add(app.IsPaused ? "Resume" : "Pause", app.PauseRecording).ToolTip = "Pause recording (Ctrl+Alt+P)"; Add("Stop", app.StopRecording).ToolTip = "Stop recording (Ctrl+Alt+S)"; }
        else Add("● Record", () => app.RequestRecording(mode));
        Add("Library", app.OpenLibrary); Add("✕", app.ToggleBar);
    }
    internal void UpdateTime() { if (clock != null) clock.Text = app.IsSaving ? app.SavingStatus : (app.IsPaused ? "● PAUSED " : "● REC ") + app.RecordingTime; }
    internal static ContextMenu MicrophoneMenu(App app)
    {
        var menu = new ContextMenu(); menu.Items.Add(new MenuItem { Header = "Microphone", IsEnabled = false });
        var devices = Recorder.GetSystemAudioCaptureDevices();
        void Item(string label, string id) { var item = new MenuItem { Header = label, IsChecked = app.Settings.Microphone == id }; item.Click += (_, _) => { app.Settings.Microphone = id; app.Save(); }; menu.Items.Add(item); }
        Item("System Default (" + (devices.FirstOrDefault(d => d.IsDefaultDevice)?.FriendlyName ?? "Unavailable") + ")", "system_default");
        foreach (var device in devices) Item(device.FriendlyName, device.DeviceName);
        Item("Mute / No Audio", "none"); return menu;
    }
}
