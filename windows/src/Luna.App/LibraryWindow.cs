using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using Luna.Core;
using CaptureMode = Luna.Core.CaptureMode;
using Microsoft.VisualBasic.FileIO;

namespace Luna.App;

internal sealed class LibraryWindow : Window
{
    private readonly App app;
    private readonly ListBox list = new() { SelectionMode = SelectionMode.Extended };
    private readonly MediaElement player = new() { LoadedBehavior = MediaState.Manual, UnloadedBehavior = MediaState.Manual };
    private readonly DockPanel playerHost = new() { Height = 260 };
    private readonly TextBlock playbackTime = new() { Margin = new Thickness(8, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
    private readonly Button fullscreen = new() { Content = "Fullscreen" };
    private Window? fullscreenWindow;
    private bool reloading;
    private readonly Slider scrub = new() { Minimum = 0 };
    private readonly TextBlock details = new() { TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock count = new();
    private readonly TextBlock notice = new();
    private readonly StackPanel live = new() { Orientation = Orientation.Horizontal };
    private readonly TextBlock liveText = new();
    private readonly Button livePause = new();
    private readonly Button storage = new();
    private readonly StackPanel pane = new() { Margin = new Thickness(16, 0, 0, 0) };
    private readonly StackPanel empty = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private readonly DispatcherTimer refresh = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private readonly FileSystemWatcher watcher;
    private bool playing;
    private bool seeking;
    private readonly Button copy = new(), files = new(), delete = new();
    internal LibraryWindow(App app)
    {
        this.app = app; Title = "Luna Recordings"; Width = 940; Height = 620; MinWidth = 840; MinHeight = 530; Native.Exclude(this);
        var root = new DockPanel { Margin = new Thickness(20) }; Content = root;
        var header = new StackPanel { Orientation = Orientation.Horizontal }; DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);
        header.Children.Add(new TextBlock { Text = "Recordings", FontSize = 26, Margin = new Thickness(0, 0, 18, 16) }); header.Children.Add(count);
        var record = new Button { Content = "Record ▾", Padding = new Thickness(14, 6, 14, 6), Margin = new Thickness(24, 0, 0, 16) }; header.Children.Add(record);
        var menu = new ContextMenu();
        foreach (var mode in Enum.GetValues<CaptureMode>()) { var item = new MenuItem { Header = mode == CaptureMode.Area ? "Record Area" : mode == CaptureMode.Window ? "Choose Window or Screen" : "Record Full Screen" }; item.Click += (_, _) => app.RequestRecording(mode); menu.Items.Add(item); }
        var systemAudio = new MenuItem { Header = "Record System Audio", IsCheckable = true, IsChecked = app.Settings.SystemAudio };
        systemAudio.Click += (_, _) => { app.Settings.SystemAudio = systemAudio.IsChecked; app.Save(); }; menu.Items.Add(systemAudio);
        var mic = new MenuItem { Header = "Microphone" }; mic.SubmenuOpened += (_, _) => { mic.Items.Clear(); foreach (var item in FloatingBar.MicrophoneMenu(app).Items.Cast<MenuItem>().ToArray()) { var copyItem = new MenuItem { Header = item.Header, IsChecked = item.IsChecked, IsEnabled = item.IsEnabled }; copyItem.Click += (_, _) => item.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); mic.Items.Add(copyItem); } }; menu.Items.Add(mic);
        var settings = new MenuItem { Header = "Settings..." }; settings.Click += (_, _) => app.ShowSettings(); menu.Items.Add(settings);
        record.Click += (_, _) => { systemAudio.IsChecked = app.Settings.SystemAudio; menu.PlacementTarget = record; menu.IsOpen = true; };
        DockPanel.SetDock(live, Dock.Top); root.Children.Add(live); live.Children.Add(liveText);
        livePause.Click += (_, _) => app.PauseRecording(); live.Children.Add(livePause);
        var stop = new Button { Content = "Stop", Margin = new Thickness(12, 0, 0, 8) }; stop.Click += (_, _) => app.StopRecording(); live.Children.Add(stop);
        var wasBusy = app.IsBusy;
        void UpdateRecording()
        {
            live.Visibility = app.IsBusy ? Visibility.Visible : Visibility.Collapsed; record.IsEnabled = !app.IsBusy;
            liveText.Text = app.IsSaving ? app.SavingStatus : (app.IsPaused ? "PAUSED " : "REC ") + app.RecordingTime + " • System audio " + (app.EffectiveSystemAudio ? "On" : "Off") + " • Mic " + app.EffectiveMicrophone + "   ";
            livePause.Content = app.IsPaused ? "Resume" : "Pause";
            livePause.IsEnabled = stop.IsEnabled = !app.IsSaving;
            if (wasBusy && !app.IsBusy) Reload();
            wasBusy = app.IsBusy;
        }
        app.RecordingChanged += UpdateRecording; Closed += (_, _) => app.RecordingChanged -= UpdateRecording; UpdateRecording();
        var footer = new StackPanel { Orientation = Orientation.Horizontal }; DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        RefreshRetentionLabel(); storage.Click += (_, _) => { new StorageWindow(app) { Owner = this }.ShowDialog(); }; footer.Children.Add(storage);
        var folder = new Button { Content = "Open folder", Margin = new Thickness(12, 0, 12, 0) }; folder.Click += (_, _) => app.OpenFolder(); footer.Children.Add(folder); footer.Children.Add(notice);
        var grid = new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(300) }); grid.ColumnDefinitions.Add(new ColumnDefinition()); root.Children.Add(grid); grid.Children.Add(list);
        Grid.SetColumnSpan(empty, 2); grid.Children.Add(empty);
        empty.Children.Add(new TextBlock { Text = "No recordings yet", FontSize = 24, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 12) });
        empty.Children.Add(new TextBlock { Text = "Press Ctrl+Alt+1, Ctrl+Alt+2 or Ctrl+Alt+3 to record.", Margin = new Thickness(0, 0, 0, 20) });
        var emptyRecord = new Button { Content = "Record", Padding = new Thickness(24, 10, 24, 10), HorizontalAlignment = HorizontalAlignment.Center }; emptyRecord.Click += (_, _) => app.RequestRecording(); empty.Children.Add(emptyRecord);
        Grid.SetColumn(pane, 1); grid.Children.Add(pane); pane.Children.Add(details); pane.Children.Add(playerHost);
        var controls = new StackPanel { Orientation = Orientation.Horizontal }; DockPanel.SetDock(controls, Dock.Bottom); playerHost.Children.Add(controls);
        DockPanel.SetDock(scrub, Dock.Bottom); playerHost.Children.Add(scrub); playerHost.Children.Add(player);
        var play = new Button { Content = "Play / Pause" }; play.Click += (_, _) => { if (playing) { player.Pause(); playing = false; } else if (player.Source != null) { player.Play(); playing = true; } }; controls.Children.Add(play);
        var volume = new Slider { Minimum = 0, Maximum = 1, Value = 0.5, Width = 100, Margin = new Thickness(12, 0, 12, 0) }; volume.ValueChanged += (_, _) => player.Volume = volume.Value; controls.Children.Add(volume);
        controls.Children.Add(playbackTime);
        fullscreen.Click += (_, _) => ToggleFullscreen(); controls.Children.Add(fullscreen);
        foreach (var button in new[] { copy, files, delete }) { button.Margin = new Thickness(0, 8, 0, 0); button.Padding = new Thickness(12, 7, 12, 7); pane.Children.Add(button); }
        copy.Click += async (_, _) => { var selected = Selected(); if (selected.Length == 0) return; try { var prompts = selected.Select(path => (path, Prompt.LoadOrRegenerate(path))).ToArray(); await ClipboardService.Text(prompts.Length == 1 ? prompts[0].Item2 : Prompt.Batch(prompts)); notice.Text = "Copied for LLMs (Ctrl+V)"; } catch (Exception ex) when (ex is IOException or InvalidDataException or UnauthorizedAccessException or ExternalException) { notice.Text = "Could not copy: " + ex.Message; } };
        files.Click += async (_, _) => { var selected = Selected(); if (selected.Length == 0) return; try { await ClipboardService.Files(selected); notice.Text = "Copied MP4"; } catch (ExternalException ex) { notice.Text = "Could not copy: " + ex.Message; } };
        delete.Click += (_, _) => Delete();
        var explorer = new Button { Content = "Show in Explorer", Margin = new Thickness(0, 8, 0, 0) }; explorer.Click += (_, _) => { foreach (var path in Selected()) System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", "/select,\"" + path + "\"") { UseShellExecute = true }); }; pane.Children.Add(explorer);
        player.MediaOpened += (_, _) => { player.Pause(); playing = false; if (player.NaturalDuration.HasTimeSpan) scrub.Maximum = player.NaturalDuration.TimeSpan.TotalSeconds; }; player.MediaEnded += (_, _) => { playing = false; player.Pause(); player.Position = TimeSpan.Zero; }; player.MediaFailed += (_, args) => { Release(); notice.Text = "Could not play this recording: " + args.ErrorException.Message; };
        scrub.PreviewMouseLeftButtonDown += (_, _) => seeking = true; scrub.PreviewMouseLeftButtonUp += (_, _) => { player.Position = TimeSpan.FromSeconds(scrub.Value); seeking = false; };
        timer.Tick += (_, _) => { if (!seeking) scrub.Value = player.Position.TotalSeconds; playbackTime.Text = player.Position.ToString(@"mm\:ss") + " / " + TimeSpan.FromSeconds(scrub.Maximum).ToString(@"mm\:ss"); }; timer.Start();
        list.SelectionChanged += (_, _) => { if (!reloading) Select(); }; list.MouseDoubleClick += (_, _) => { if (Selected().Length == 1) System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Selected()[0]) { UseShellExecute = true }); }; list.KeyDown += (_, args) => { if (args.Key == Key.Delete) Delete(); };
        watcher = new FileSystemWatcher(app.Recordings, "Recording_*.mp4") { NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size, EnableRaisingEvents = true };
        watcher.Created += Changed; watcher.Deleted += Changed; watcher.Changed += Changed; watcher.Renamed += Changed;
        refresh.Tick += (_, _) => { refresh.Stop(); Reload(); }; Closed += (_, _) => { watcher.Dispose(); timer.Stop(); refresh.Stop(); Release(); }; Reload(); Select();
    }
    private void Changed(object sender, FileSystemEventArgs e) => Dispatcher.BeginInvoke(new Action(() => { refresh.Stop(); refresh.Start(); }));
    private string[] Selected() => list.SelectedItems.Cast<RecordingRow>().Select(c => c.Path).ToArray();
    private void Reload()
    {
        var selected = Selected().ToHashSet(StringComparer.OrdinalIgnoreCase);
        reloading = true;
        try { list.ItemsSource = Directory.EnumerateFiles(app.Recordings, "Recording_*.mp4").Select(path => new FileInfo(path)).Where(f => f.Length > 0 && !string.Equals(f.FullName, app.ActiveRecording, StringComparison.OrdinalIgnoreCase)).OrderByDescending(f => f.LastWriteTimeUtc).Select(f => new RecordingRow(f.FullName, f.LastWriteTime, f.Length)).ToArray(); foreach (var clip in list.Items.Cast<RecordingRow>()) if (selected.Contains(clip.Path)) list.SelectedItems.Add(clip); count.Text = $"{list.Items.Count} recordings"; if (list.Items.Count == 0) details.Text = "No recordings yet\nPress Ctrl+Alt+1, Ctrl+Alt+2 or Ctrl+Alt+3 to record."; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { notice.Text = ex.Message; }
        finally { reloading = false; Select(); }
    }
    private void Select()
    {
        var selection = list.SelectedItems.Cast<RecordingRow>().ToArray(); var n = selection.Length;
        var next = n == 1 ? selection[0].Path : null;
        if (!string.Equals(player.Source?.LocalPath, next, StringComparison.OrdinalIgnoreCase))
        {
            Release();
            if (next != null) { player.Source = new Uri(next); player.Pause(); }
        }
        empty.Visibility = list.Items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        list.Visibility = list.Items.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        pane.Visibility = n == 0 ? Visibility.Collapsed : Visibility.Visible;
        copy.Content = n > 1 ? $"Copy {n} for LLMs" : "Copy for LLMs"; files.Content = n > 1 ? $"Copy {n} MP4s" : "Copy MP4"; delete.Content = n > 1 ? $"Delete {n}" : "Delete";
        details.Text = n == 1 ? selection[0].ToString() : $"{n} recordings selected • {selection.Sum(c => c.Bytes) / 1048576.0:0.0} MB";
        foreach (var button in new[] { copy, files, delete }) { button.IsEnabled = n > 0; }
        player.Visibility = n == 1 ? Visibility.Visible : Visibility.Collapsed;
        scrub.IsEnabled = fullscreen.IsEnabled = n == 1;
        if (n == 0) details.Text = "No recordings yet\nPress Ctrl+Alt+1, Ctrl+Alt+2 or Ctrl+Alt+3 to record.";
    }
    private void Release() { fullscreenWindow?.Close(); player.Stop(); player.Close(); player.Source = null; playing = false; seeking = false; scrub.Value = scrub.Maximum = 0; }
    private void ToggleFullscreen()
    {
        if (fullscreenWindow != null) { fullscreenWindow.Close(); return; }
        if (player.Source == null) return;
        var window = new Window { Title = "Luna player", Owner = this, WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, Left = Left, Top = Top, Background = System.Windows.Media.Brushes.White };
        Native.Exclude(window);
        pane.Children.Remove(playerHost); playerHost.Height = double.NaN; window.Content = playerHost;
        fullscreenWindow = window; fullscreen.Content = "Exit fullscreen";
        window.PreviewKeyDown += (_, args) => { if (args.Key == Key.Escape) { args.Handled = true; window.Close(); } };
        window.Closed += (_, _) =>
        {
            window.Content = null; playerHost.Height = 260; pane.Children.Insert(1, playerHost);
            fullscreenWindow = null; fullscreen.Content = "Fullscreen";
        };
        window.Show(); Native.FillMonitor(window, this);
    }
    private bool ConfirmDelete(string text)
    {
        var body = new StackPanel { Margin = new Thickness(24) };
        var dialog = new Window { Title = "Delete recording?", Owner = this, SizeToContent = SizeToContent.WidthAndHeight, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner, Content = body };
        Native.Exclude(dialog);
        body.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, MaxWidth = 420 });
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) }; body.Children.Add(actions);
        var cancel = new Button { Content = "Cancel", IsCancel = true, Padding = new Thickness(16, 6, 16, 6) }; actions.Children.Add(cancel);
        var confirm = new Button { Content = "Delete", Padding = new Thickness(16, 6, 16, 6), Margin = new Thickness(12, 0, 0, 0) }; actions.Children.Add(confirm);
        confirm.Click += (_, _) => dialog.DialogResult = true;
        return dialog.ShowDialog() == true;
    }
    internal void SelectPath(string path)
    {
        Reload(); foreach (var item in list.Items.Cast<RecordingRow>()) if (string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase)) { list.SelectedItem = item; list.ScrollIntoView(item); break; }
    }
    internal void RefreshRetentionLabel() => storage.Content = app.Settings.AutoDelete ? $"{app.Settings.RetentionDays}-Day Auto-Delete" : "Auto-Delete Off";
    private void Delete()
    {
        var paths = Selected(); if (paths.Length == 0) return;
        if (!ConfirmDelete(paths.Length == 1 ? $"Delete \"{System.IO.Path.GetFileName(paths[0])}\" and its files?" : $"Delete {paths.Length} recordings and their files?")) return;
        Release();
        try { foreach (var path in paths) RecordingFiles.EnsureDeletable(path, Native.EnsureDirectoryDeletable); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { notice.Text = ex.Message; return; }
        foreach (var path in paths) foreach (var file in RecordingFiles.Sidecars(path))
        {
            try
            {
                var attributes = RecordingFiles.AttributesIfPresent(file);
                if (attributes is null) continue;
                if ((attributes.Value & FileAttributes.Directory) != 0) FileSystem.DeleteDirectory(file, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin);
                else FileSystem.DeleteFile(file, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or OperationCanceledException) { notice.Text = ex.Message; return; }
        }
        Reload(); notice.Text = "Moved to Recycle Bin";
    }
    private sealed record RecordingRow(string Path, DateTime Modified, long Bytes)
    {
        public override string ToString() { var day = Modified.Date == DateTime.Today ? "Today" : Modified.Date == DateTime.Today.AddDays(-1) ? "Yesterday" : Modified.ToString("MMM d"); return $"{day}, {Modified:h:mm tt}\n{System.IO.Path.GetFileName(Path)} • {Bytes / 1048576.0:0.0} MB"; }
    }
}
