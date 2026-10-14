using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Luna.App;

internal sealed class ToastWindow : Window
{
    internal ToastWindow(string title, string? subtitle = null, Action? view = null, string actionLabel = "View")
    {
        Width = 390; Height = 48; WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        ShowInTaskbar = false; ShowActivated = false; Topmost = true; ResizeMode = ResizeMode.NoResize;
        Native.Exclude(this); Native.NoActivate(this);
        var body = new Border { Background = new SolidColorBrush(Color.FromRgb(30, 35, 48)), CornerRadius = new CornerRadius(24), Padding = new Thickness(18, 4, 18, 4) };
        var row = new DockPanel(); body.Child = row; Content = body;
        if (view != null) { var button = new Button { Content = actionLabel, Margin = new Thickness(12, 0, 0, 0) }; DockPanel.SetDock(button, Dock.Right); row.Children.Add(button); button.Click += (_, _) => { view(); Close(); }; body.MouseLeftButtonUp += (_, _) => { view(); Close(); }; }
        var text = new StackPanel(); row.Children.Add(text); text.Children.Add(new TextBlock { Text = title, Foreground = Brushes.White, FontWeight = FontWeights.SemiBold, FontSize = 13, TextTrimming = TextTrimming.CharacterEllipsis });
        if (subtitle != null) text.Children.Add(new TextBlock { Text = subtitle, Foreground = Brushes.LightGray, FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis });
        var screen = Forms.Screen.FromPoint(Forms.Cursor.Position); var scale = Native.ScaleAt(screen.Bounds.Left, screen.Bounds.Top);
        Left = (screen.WorkingArea.Left + (screen.WorkingArea.Width - Width * scale) / 2) / scale; Top = (screen.WorkingArea.Top + 20) / scale;
        Loaded += (_, _) => { BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromSeconds(0.25))); var move = new TranslateTransform(0, -10); body.RenderTransform = move; move.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(-10, 0, TimeSpan.FromSeconds(0.25))); };
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3.2) }; timer.Tick += (_, _) => { timer.Stop(); Close(); }; Closed += (_, _) => timer.Stop(); timer.Start();
    }
}
