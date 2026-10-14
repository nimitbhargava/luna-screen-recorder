using System;
using System.Linq;
using System.Runtime.ExceptionServices;
using System.Threading;
using System.Windows.Controls;
using Luna.App;
using Xunit;
using Forms = System.Windows.Forms;

namespace Luna.App.Tests;

public class AreaOverlayTests
{
    [Theory]
    [InlineData(0, 50)]
    [InlineData(50, 0)]
    [InlineData(0, 0)]
    public void CollapsedDragRendersWithoutEncodingOrAnError(int width, int height)
    {
        OnSta(() =>
        {
            var overlay = new AreaOverlay(Forms.Screen.PrimaryScreen!, _ => { });
            try
            {
                overlay.Draw(new System.Drawing.Rectangle(350, 400, width, height));
                var labels = ((Canvas)overlay.Content).Children.OfType<TextBlock>().Select(t => t.Text).ToArray();
                Assert.Contains("", labels);
                Assert.Contains("Drag to select area • Click to record this screen • Esc to cancel", labels);
            }
            finally { overlay.Close(); }
        });
    }

    [Fact]
    public void NonemptyDragShowsOutputDimensionsAndCanCollapseAgain()
    {
        OnSta(() =>
        {
            var overlay = new AreaOverlay(Forms.Screen.PrimaryScreen!, _ => { });
            try
            {
                overlay.Draw(new System.Drawing.Rectangle(350, 400, 20, 20));
                Assert.Contains(((Canvas)overlay.Content).Children.OfType<TextBlock>(), t => t.Text == "160 × 120");
                overlay.Draw(new System.Drawing.Rectangle(350, 400, 0, 20));
                Assert.Contains(((Canvas)overlay.Content).Children.OfType<TextBlock>(), t => t.Text == "");
            }
            finally { overlay.Close(); }
        });
    }

    private static void OnSta(Action test)
    {
        Exception? error = null;
        var thread = new Thread(() => { try { test(); } catch (Exception ex) { error = ex; } });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (error != null) ExceptionDispatchInfo.Capture(error).Throw();
    }
}
