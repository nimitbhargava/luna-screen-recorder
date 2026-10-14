using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Luna.App;

internal static partial class Native
{
    [StructLayout(LayoutKind.Sequential)] private struct Bounds { public int Left, Top, Right, Bottom; }
    [DllImport("gdi32.dll")] internal static extern bool DeleteObject(IntPtr handle);
    [DllImport("user32.dll")] internal static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Bounds bounds);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out int value, int size);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    internal static Rectangle WindowBounds(IntPtr window) { if (!GetWindowRect(window, out var b)) throw new InvalidOperationException("Window is no longer available."); return Rectangle.FromLTRB(b.Left, b.Top, b.Right, b.Bottom); }
    internal static bool EligibleWindow(IntPtr window)
    {
        DwmGetWindowAttribute(window, 14, out var cloaked, 4); var bounds = WindowBounds(window);
        return cloaked == 0 && bounds.Width >= 100 && bounds.Height >= 100 && (GetWindowLongPtr(window, -20).ToInt64() & 0x80) == 0;
    }
    internal static void PositionWindow(Window window, Rectangle bounds) => SetWindowPos(new WindowInteropHelper(window).Handle, new IntPtr(-1), bounds.Left, bounds.Top, bounds.Width, bounds.Height, 0x40);
    [DllImport("dwmapi.dll")] internal static extern int DwmRegisterThumbnail(IntPtr destination, IntPtr source, out IntPtr thumbnail);
    [DllImport("dwmapi.dll")] internal static extern int DwmUnregisterThumbnail(IntPtr thumbnail);
    [StructLayout(LayoutKind.Sequential)] private struct ThumbnailProperties { public uint Flags; public Bounds Destination, Source; public byte Opacity; [MarshalAs(UnmanagedType.Bool)] public bool Visible; [MarshalAs(UnmanagedType.Bool)] public bool ClientOnly; }
    [DllImport("dwmapi.dll")] private static extern int DwmUpdateThumbnailProperties(IntPtr thumbnail, ref ThumbnailProperties properties);
    internal static void UpdateThumbnail(IntPtr thumbnail, Rectangle destination)
    {
        var properties = new ThumbnailProperties { Flags = 1 | 4 | 8, Destination = new Bounds { Left = destination.Left, Top = destination.Top, Right = destination.Right, Bottom = destination.Bottom }, Opacity = 255, Visible = true };
        DwmUpdateThumbnailProperties(thumbnail, ref properties);
    }
}
