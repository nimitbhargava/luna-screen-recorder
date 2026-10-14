using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using Luna.Core;
namespace Luna.App;

internal sealed class StorageWindow : Window
{
    internal StorageWindow(App app)
    {
        Title = "Recording storage"; Width = 480; Height = 290; ResizeMode = ResizeMode.NoResize; Native.Exclude(this);
        var panel = new StackPanel { Margin = new Thickness(24) }; Content = panel;
        var total = new TextBlock(); var reclaim = new TextBlock { Margin = new Thickness(0, 8, 0, 12) }; panel.Children.Add(total); panel.Children.Add(reclaim);
        var days = new ComboBox { ItemsSource = new[] { 7, 15, 30, 60 }, SelectedItem = app.Settings.RetentionDays, Margin = new Thickness(0, 0, 0, 12) }; panel.Children.Add(days); Native.Exclude(days);
        var automatic = new CheckBox { Content = "Delete old recordings automatically", IsChecked = app.Settings.AutoDelete, Margin = new Thickness(0, 0, 0, 12) }; panel.Children.Add(automatic);
        var clean = new Button { Padding = new Thickness(8, 6, 8, 6) }; panel.Children.Add(clean);
        var savedDays = app.Settings.RetentionDays; var savedAutomatic = app.Settings.AutoDelete;
        void Refresh()
        {
            var files = Directory.EnumerateFiles(app.Recordings, "Recording_*.mp4").Select(f => new FileInfo(f)).Where(f => f.Length > 0).ToArray();
            var expired = Retention.Candidates(files.Select(f => new ClipFile(f.FullName, f.LastWriteTimeUtc)), DateTimeOffset.Now, (int)days.SelectedItem).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var bytes = files.Where(f => expired.Contains(f.FullName)).Sum(f => f.Length);
            total.Text = $"Total used: {files.Sum(f => f.Length) / 1048576.0:0.0} MB ({files.Length} recordings)";
            reclaim.Text = $"Can free now: {bytes / 1048576.0:0.0} MB ({expired.Count} older than {days.SelectedItem} days)";
            clean.Content = $"Clean up now (free {bytes / 1048576.0:0.0} MB)";
        }
        days.SelectionChanged += (_, _) => Refresh();
        void SyncSettings()
        {
            if (savedDays != app.Settings.RetentionDays) days.SelectedItem = app.Settings.RetentionDays;
            if (savedAutomatic != app.Settings.AutoDelete) automatic.IsChecked = app.Settings.AutoDelete;
            savedDays = app.Settings.RetentionDays; savedAutomatic = app.Settings.AutoDelete;
            Refresh();
        }
        app.SettingsSaved += SyncSettings; Closed += (_, _) => app.SettingsSaved -= SyncSettings;
        clean.Click += (_, _) => { app.CleanUp((int)days.SelectedItem); Refresh(); };
        var done = new Button { Content = "Done", IsDefault = true, Padding = new Thickness(8, 6, 8, 6), Margin = new Thickness(0, 12, 0, 0) }; done.Click += (_, _) => { app.Settings.RetentionDays = (int)days.SelectedItem; app.Settings.AutoDelete = automatic.IsChecked == true; app.Save(); Close(); }; panel.Children.Add(done); Refresh();
    }
}
