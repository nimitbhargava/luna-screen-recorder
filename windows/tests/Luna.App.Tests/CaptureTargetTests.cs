using System.Drawing;
using Luna.App;
using Luna.Core;
using ScreenRecorderLib;
using Xunit;
using Forms = System.Windows.Forms;

namespace Luna.App.Tests;

public class CaptureTargetTests
{
    [Theory]
    [InlineData(CaptureMode.Area)]
    [InlineData(CaptureMode.Screen)]
    public void DisplayTargetsUseWindowsGraphicsCapture(CaptureMode mode)
    {
        var screen = Forms.Screen.PrimaryScreen!;
        var target = mode == CaptureMode.Area
            ? CaptureTarget.Area(screen, new Rectangle(screen.Bounds.Left + 100, screen.Bounds.Top + 100, 320, 240))
            : CaptureTarget.Screen(screen);

        Assert.Equal(mode, target.Mode);
        Assert.Equal(RecorderApi.WindowsGraphicsCapture, Assert.IsType<DisplayRecordingSource>(target.Source).RecorderApi);
    }
}
