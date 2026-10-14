using System;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Threading;
using Xunit;
using Forms = System.Windows.Forms;

namespace Luna.App.Tests;

public class PopupExclusionTests
{
    [DllImport("user32.dll")] private static extern bool GetWindowDisplayAffinity(IntPtr window, out uint affinity);

    [Fact]
    public void WpfMenusSubmenusTooltipsAndComboPopupsUseExcludedHwnds()
    {
        OnSta(() =>
        {
            var combo = new ComboBox { ItemsSource = new[] { 7, 15, 30, 60 }, SelectedIndex = 0 };
            var window = new Window { Title = "Owned Luna popup test", Width = 300, Height = 200, Content = combo };
            Native.Exclude(window); Native.Exclude(combo);
            var submenu = new MenuItem { Header = "Owned submenu" }; submenu.Items.Add(new MenuItem { Header = "Owned choice" });
            var menu = new ContextMenu { PlacementTarget = combo }; menu.Items.Add(submenu);
            var tip = new ToolTip { Content = "Owned tooltip", PlacementTarget = combo };
            try
            {
                window.Show(); Pump();
                AssertExcluded(new WindowInteropHelper(window).Handle);
                combo.IsDropDownOpen = true; Pump();
                var popup = (Popup)combo.Template.FindName("PART_Popup", combo);
                AssertExcluded(((HwndSource)PresentationSource.FromVisual(popup.Child)).Handle);
                combo.IsDropDownOpen = false;
                menu.IsOpen = true; Pump(); AssertExcluded(((HwndSource)PresentationSource.FromVisual(menu)).Handle);
                submenu.IsSubmenuOpen = true; Pump();
                var nested = (Popup)submenu.Template.FindName("PART_Popup", submenu);
                AssertExcluded(((HwndSource)PresentationSource.FromVisual(nested.Child)).Handle);
                menu.IsOpen = false; tip.IsOpen = true; Pump();
                AssertExcluded(((HwndSource)PresentationSource.FromVisual(tip)).Handle);
                // Reopening exercises popup HWND recreation as well as the initial open.
                tip.IsOpen = false; combo.IsDropDownOpen = true; Pump();
                AssertExcluded(((HwndSource)PresentationSource.FromVisual(popup.Child)).Handle);
            }
            finally { tip.IsOpen = false; menu.IsOpen = false; combo.IsDropDownOpen = false; window.Close(); }
        });
    }

    [Fact]
    public void TrayMenuAndMicrophoneSubmenuUseExcludedHwnds()
    {
        OnSta(() =>
        {
            using var menu = new Forms.ContextMenuStrip();
            var mic = new Forms.ToolStripMenuItem("Owned microphone menu"); mic.DropDownItems.Add("Owned microphone"); menu.Items.Add(mic);
            Native.Exclude(menu);
            menu.Show(100, 100); AssertExcluded(menu.Handle);
            mic.ShowDropDown(); AssertExcluded(mic.DropDown.Handle);
            mic.HideDropDown(); menu.Close(); menu.Show(100, 100); AssertExcluded(menu.Handle); menu.Close();
        });
    }

    private static void AssertExcluded(IntPtr handle)
    {
        Assert.NotEqual(IntPtr.Zero, handle); Assert.True(GetWindowDisplayAffinity(handle, out var affinity)); Assert.Equal(0x11u, affinity);
    }
    private static void Pump()
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(100) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; }; timer.Start(); Dispatcher.PushFrame(frame);
    }
    private static void OnSta(Action test)
    {
        Exception? error = null;
        var thread = new Thread(() => { try { test(); } catch (Exception ex) { error = ex; } });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (error != null) ExceptionDispatchInfo.Capture(error).Throw();
    }
}
