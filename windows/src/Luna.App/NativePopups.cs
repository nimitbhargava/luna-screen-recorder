using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace Luna.App;

internal static partial class Native
{
    static Native()
    {
        EventManager.RegisterClassHandler(typeof(ContextMenu), ContextMenu.OpenedEvent, new RoutedEventHandler((sender, _) => ExcludeVisual((Visual)sender)));
        EventManager.RegisterClassHandler(typeof(ToolTip), ToolTip.OpenedEvent, new RoutedEventHandler((sender, _) => ExcludeVisual((Visual)sender)));
        EventManager.RegisterClassHandler(typeof(MenuItem), MenuItem.SubmenuOpenedEvent, new RoutedEventHandler((sender, _) => ExcludePopup((Control)sender)));
    }
    internal static void Exclude(ComboBox combo)
    {
        // WPF's Loaded optimization does not dispatch a class-only Loaded handler.
        // Subscribe on the owned control so the handler is present before layout.
        combo.Loaded += (_, _) => ExcludePopup(combo);
        combo.DropDownOpened += ComboOpened;
    }
    private static void ComboOpened(object? sender, EventArgs args) => ExcludePopup((Control)sender!);
    private static void ExcludePopup(Control control)
    {
        if (control.Template?.FindName("PART_Popup", control) is Popup popup)
        {
            // ComboBox.DropDownOpened can precede creation of the popup's HWND.
            popup.Opened -= PopupOpened; popup.Opened += PopupOpened;
            if (popup.Child is Visual child) ExcludeVisual(child);
        }
    }
    private static void PopupOpened(object? sender, EventArgs args) { if (sender is Popup { Child: Visual child }) ExcludeVisual(child); }
    private static void ExcludeVisual(Visual visual)
    {
        if (PresentationSource.FromVisual(visual) is HwndSource source) Exclude(source.Handle);
    }
    internal static void Exclude(Forms.ToolStripDropDown menu)
    {
        menu.HandleCreated += (_, _) => Exclude(menu.Handle);
        if (menu.IsHandleCreated) Exclude(menu.Handle);
        foreach (Forms.ToolStripItem item in menu.Items)
            if (item is Forms.ToolStripDropDownItem submenu && submenu.HasDropDownItems) Exclude(submenu.DropDown);
    }
    internal static void Exclude(IntPtr hwnd)
    {
        if (!SetWindowDisplayAffinity(hwnd, 0x11)) App.Log("Capture exclusion failed: " + Marshal.GetLastWin32Error());
    }
    [DllImport("user32.dll")] internal static extern bool DestroyIcon(IntPtr icon);
    internal static void FillMonitor(Window window, Window owner)
    {
        var bounds = Forms.Screen.FromHandle(new WindowInteropHelper(owner).Handle).Bounds;
        if (!SetWindowPos(new WindowInteropHelper(window).Handle, IntPtr.Zero, bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x0004)) App.Log("Fullscreen placement failed: " + Marshal.GetLastWin32Error());
    }
}
