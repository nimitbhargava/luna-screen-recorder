using System;
using System.Diagnostics;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using Luna.Core;
using ScreenRecorderLib;
using Forms = System.Windows.Forms;
using CaptureMode = Luna.Core.CaptureMode;

namespace Luna.App;

internal sealed class AreaOverlay : Window
{
    private readonly Forms.Screen screen;
    private readonly Canvas canvas = new();
    private readonly System.Windows.Shapes.Path shade = new() { Fill = new SolidColorBrush(Color.FromArgb(89, 0, 0, 0)), IsHitTestVisible = false };
    private readonly Rectangle stroke = new() { Stroke = Brushes.Cyan, StrokeThickness = 2, RadiusX = 4, RadiusY = 4, IsHitTestVisible = false };
    private readonly TextBlock size = new() { Foreground = Brushes.White, Background = Brushes.Black, IsHitTestVisible = false };
    private System.Drawing.Point start;
    private bool dragging;
    private readonly Action<CaptureTarget?> finish;
    private double Scale => Native.ScaleAt(screen.Bounds.Left, screen.Bounds.Top);
    internal AreaOverlay(Forms.Screen screen, Action<CaptureTarget?> finish)
    {
        this.screen = screen; this.finish = finish;
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent; ShowInTaskbar = false; Topmost = true; Cursor = Cursors.Cross; ResizeMode = ResizeMode.NoResize;
        Left = screen.Bounds.Left / Scale; Top = screen.Bounds.Top / Scale; Width = screen.Bounds.Width / Scale; Height = screen.Bounds.Height / Scale;
        Content = canvas; canvas.Background = Brushes.Transparent; canvas.Children.Add(shade); canvas.Children.Add(stroke); canvas.Children.Add(size);
        var tip = new TextBlock { Text = "Drag to select area • Click to record this screen • Esc to cancel", Foreground = Brushes.White, Background = Brushes.Black, FontSize = 16 };
        canvas.Children.Add(tip); Canvas.SetTop(tip, 24); Canvas.SetLeft(tip, 24);
        Native.Exclude(this);
        SourceInitialized += (_, _) => Native.PositionWindow(this, screen.Bounds);
        Loaded += (_, _) => Draw(new System.Drawing.Rectangle());
        KeyDown += (_, args) => { if (args.Key == Key.Escape) finish(null); };
        MouseLeftButtonDown += (_, _) => { start = Forms.Cursor.Position; dragging = true; CaptureMouse(); };
        MouseMove += (_, _) => { if (dragging) Draw(Selection()); };
        MouseLeftButtonUp += (_, _) =>
        {
            if (!dragging) return;
            dragging = false; ReleaseMouseCapture(); var selected = Selection();
            if (AreaGesture.IsScreen(selected.Width, selected.Height)) finish(CaptureTarget.Screen(screen));
            else if (AreaGesture.MustRetry(selected.Width, selected.Height)) Draw(new System.Drawing.Rectangle());
            else finish(CaptureTarget.Area(screen, selected));
        };
    }
    private System.Drawing.Rectangle Selection()
    {
        var end = Forms.Cursor.Position; var b = screen.Bounds;
        return System.Drawing.Rectangle.FromLTRB(Math.Clamp(Math.Min(start.X, end.X), b.Left, b.Right), Math.Clamp(Math.Min(start.Y, end.Y), b.Top, b.Bottom), Math.Clamp(Math.Max(start.X, end.X), b.Left, b.Right), Math.Clamp(Math.Max(start.Y, end.Y), b.Top, b.Bottom));
    }
    internal void Draw(System.Drawing.Rectangle selection)
    {
        var hole = new Rect((selection.Left - screen.Bounds.Left) / Scale, (selection.Top - screen.Bounds.Top) / Scale, selection.Width / Scale, selection.Height / Scale);
        var whole = new RectangleGeometry(new Rect(0, 0, Width, Height));
        var hasArea = selection.Width > 0 && selection.Height > 0;
        shade.Data = !hasArea ? whole : new CombinedGeometry(GeometryCombineMode.Exclude, whole, new RectangleGeometry(hole));
        stroke.Width = hole.Width; stroke.Height = hole.Height; Canvas.SetLeft(stroke, hole.Left); Canvas.SetTop(stroke, hole.Top);
        if (!hasArea) size.Text = "";
        else { var output = Luna.Core.Encoding.Size(selection.Width, selection.Height, Scale, CaptureMode.Area); size.Text = $"{output.Width} × {output.Height}"; Canvas.SetLeft(size, hole.Left); Canvas.SetTop(size, hole.Bottom + 24 > Height ? hole.Top - 24 : hole.Bottom + 4); }
    }
    internal static CaptureTarget? Choose()
    {
        CaptureTarget? result = null; var frame = new DispatcherFrame();
        var windows = Forms.Screen.AllScreens.Select(s => new AreaOverlay(s, target => { result = target; frame.Continue = false; })).ToArray();
        try { foreach (var window in windows) window.Show(); Dispatcher.PushFrame(frame); }
        finally { foreach (var window in windows) window.Close(); }
        return result;
    }
}

internal sealed class CapturePicker : Window
{
    private readonly ListBox windows = new(), screens = new();
    private IntPtr thumbnail;
    private readonly Border preview = new() { Height = 240, Background = Brushes.Black, Margin = new Thickness(0, 12, 0, 12) };
    private CaptureTarget? selected;
    private readonly System.Windows.Controls.Image screenPreview = new() { Stretch = Stretch.Uniform };
    private readonly DispatcherTimer previewTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private CapturePicker()
    {
        Title = "Choose Window or Screen"; Width = 650; Height = 600; Native.Exclude(this);
        var panel = new DockPanel { Margin = new Thickness(20) }; Content = panel;
        var controls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right }; DockPanel.SetDock(controls, Dock.Bottom); panel.Children.Add(controls);
        var cancel = new Button { Content = "Cancel", Margin = new Thickness(8) }; cancel.Click += (_, _) => Close(); controls.Children.Add(cancel);
        var record = new Button { Content = "Record", Margin = new Thickness(8), IsDefault = true }; record.Click += (_, _) => Accept(); controls.Children.Add(record);
        DockPanel.SetDock(preview, Dock.Bottom); panel.Children.Add(preview);
        var tabs = new TabControl(); panel.Children.Add(tabs); tabs.Items.Add(new TabItem { Header = "Window", Content = windows }); tabs.Items.Add(new TabItem { Header = "Entire Screen", Content = screens });
        foreach (var window in Recorder.GetWindows().Where(w => w.Pid != Environment.ProcessId && !w.IsMinmimized() && Native.EligibleWindow(w.Handle)))
        {
            var title = string.IsNullOrWhiteSpace(window.Title) ? "Untitled Window" : window.Title; if (title.Length > 35) title = title[..32] + "...";
            var name = "App"; try { if (window.Pid is int pid) name = Process.GetProcessById(pid).ProcessName; } catch (ArgumentException) { }
            windows.Items.Add(new ListBoxItem { Content = name + ": " + title, Tag = window.Handle });
        }
        foreach (var screen in Forms.Screen.AllScreens) screens.Items.Add(new ListBoxItem { Content = screen.DeviceName + $" ({screen.Bounds.Width} × {screen.Bounds.Height})", Tag = screen });
        windows.SelectionChanged += (_, _) => { if (windows.SelectedItem is ListBoxItem item) { selected = CaptureTarget.ForWindow((IntPtr)item.Tag); Preview((IntPtr)item.Tag); } };
        screens.SelectionChanged += (_, _) => { ClearPreview(); if (screens.SelectedItem is ListBoxItem item) { selected = CaptureTarget.Screen((Forms.Screen)item.Tag); RefreshScreenPreview(); } };
        tabs.SelectionChanged += (_, _) => { previewTimer.Stop(); if (tabs.SelectedIndex == 1) { preview.Child = screenPreview; previewTimer.Start(); RefreshScreenPreview(); } else { preview.Child = null; if (windows.SelectedItem is ListBoxItem item) Preview((IntPtr)item.Tag); } if (tabs.SelectedIndex == 0 && windows.SelectedItem is ListBoxItem w) selected = CaptureTarget.ForWindow((IntPtr)w.Tag); else if (tabs.SelectedIndex == 1 && screens.SelectedItem is ListBoxItem s) selected = CaptureTarget.Screen((Forms.Screen)s.Tag); else selected = null; };
        windows.MouseDoubleClick += (_, _) => Accept(); screens.MouseDoubleClick += (_, _) => Accept(); KeyDown += (_, args) => { if (args.Key == Key.Escape) Close(); };
        previewTimer.Tick += (_, _) => RefreshScreenPreview();
        Closed += (_, _) => { previewTimer.Stop(); ClearPreview(); };
    }
    private void RefreshScreenPreview()
    {
        if (screens.SelectedItem is not ListBoxItem item || preview.Child != screenPreview) return;
        var bounds = ((Forms.Screen)item.Tag).Bounds;
        using var bitmap = new System.Drawing.Bitmap(bounds.Width, bounds.Height);
        using (var graphics = System.Drawing.Graphics.FromImage(bitmap)) graphics.CopyFromScreen(bounds.Location, System.Drawing.Point.Empty, bounds.Size);
        var handle = bitmap.GetHbitmap();
        try { screenPreview.Source = Imaging.CreateBitmapSourceFromHBitmap(handle, IntPtr.Zero, Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions()); }
        finally { Native.DeleteObject(handle); }
    }
    private void Accept() { if (selected == null) return; DialogResult = true; }
    private void ClearPreview() { if (thumbnail != IntPtr.Zero) Native.DwmUnregisterThumbnail(thumbnail); thumbnail = IntPtr.Zero; }
    private void Preview(IntPtr source)
    {
        ClearPreview(); if (Native.DwmRegisterThumbnail(new WindowInteropHelper(this).Handle, source, out thumbnail) != 0) return;
        var point = preview.TranslatePoint(new Point(0, 0), this); var scale = VisualTreeHelper.GetDpi(this).DpiScaleX;
        Native.UpdateThumbnail(thumbnail, new System.Drawing.Rectangle((int)(point.X * scale), (int)(point.Y * scale), (int)(preview.ActualWidth * scale), (int)(preview.ActualHeight * scale)));
    }
    internal static CaptureTarget? Choose() { var picker = new CapturePicker(); return picker.ShowDialog() == true ? picker.selected : null; }
}
