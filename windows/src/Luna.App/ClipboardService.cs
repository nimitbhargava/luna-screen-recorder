using System;
using System.Collections.Specialized;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Forms = System.Windows.Forms;
namespace Luna.App;

internal static class ClipboardService
{
    internal static Task Text(string text) => Retry(() =>
    {
        var data = new Forms.DataObject(); data.SetText(text, Forms.TextDataFormat.UnicodeText);
        Forms.Clipboard.SetDataObject(data, true, 0, 0);
    });
    internal static Task Files(string[] paths) => Retry(() =>
    {
        var files = new StringCollection(); files.AddRange(paths);
        var data = new Forms.DataObject(); data.SetFileDropList(files);
        Forms.Clipboard.SetDataObject(data, true, 0, 0);
    });
    private static async Task Retry(Action action)
    {
        // Disable the framework's synchronous retries above; this is the single async retry policy.
        for (var i = 0; i < 10; i++)
        {
            try { action(); return; } catch (ExternalException) when (i < 9) { await Task.Delay(50); }
        }
    }
}
