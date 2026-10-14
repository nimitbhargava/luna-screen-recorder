using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Microsoft.Win32.SafeHandles;

namespace Luna.App;

internal static partial class Native
{
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(Point point, uint flags);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(IntPtr monitor, int kind, out uint x, out uint y);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)] private static extern SafeFileHandle CreateFileForDelete(string path, uint access, uint sharing, IntPtr security, uint disposition, uint flags, IntPtr template);
    internal static void EnsureDirectoryDeletable(string path)
    {
        using var handle = CreateFileForDelete(path, 0x00010080, 0, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
        if (handle.IsInvalid) throw new IOException($"Recording directory cannot be deleted: {path} (Windows error {Marshal.GetLastWin32Error()}).");
    }
    internal static double ScaleAt(int x, int y) { var monitor = MonitorFromPoint(new Point { X = x, Y = y }, 2); return GetDpiForMonitor(monitor, 0, out var dpi, out _) == 0 ? dpi / 96.0 : 1; }
    internal static void NoActivate(Window window) => window.SourceInitialized += (_, _) => { var hwnd = new WindowInteropHelper(window).Handle; SetWindowLongPtr(hwnd, -20, new IntPtr(GetWindowLongPtr(hwnd, -20).ToInt64() | 0x08000000)); };
    [DllImport("user32.dll", SetLastError = true)] internal static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);
    [DllImport("user32.dll")] internal static extern bool RegisterHotKey(IntPtr hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] internal static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    [DllImport("shell32.dll")] private static extern int SHGetKnownFolderPath(ref Guid folder, uint flags, IntPtr token, out IntPtr path);
    internal static string Videos()
    {
        var folder = new Guid("18989B1D-99B5-455B-841C-AB7C74E4DDFC");
        Marshal.ThrowExceptionForHR(SHGetKnownFolderPath(ref folder, 0, IntPtr.Zero, out var path));
        try { return Marshal.PtrToStringUni(path)!; } finally { Marshal.FreeCoTaskMem(path); }
    }
    internal static void Exclude(Window window) => window.SourceInitialized += (_, _) =>
    {
        Exclude(new WindowInteropHelper(window).Handle);
    };
}
