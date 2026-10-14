using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Luna.Core;
using ScreenRecorderLib;
using Xunit;

namespace Luna.App.Tests;

public class RecoveryBoundaryTests
{
    private const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;

    [Fact]
    public async Task MetadataRefusalsAndOptimizerRefusalStayInsideApplicationRecovery()
    {
        // WPF permits one Application per process; its shutdown must not affect other tests.
        var assembly = typeof(RecoveryBoundaryTests).Assembly.Location;
        var host = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH")
            ?? Path.GetFullPath(Path.Combine(System.Runtime.InteropServices.RuntimeEnvironment.GetRuntimeDirectory(), "../../..", "dotnet.exe"));
        var start = new ProcessStartInfo(host) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "exec", "--runtimeconfig", Path.ChangeExtension(assembly, ".runtimeconfig.json"), assembly, "--recovery-boundaries" }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEndAsync(); var errors = process.StandardError.ReadToEndAsync();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        try { await process.WaitForExitAsync(timeout.Token); }
        catch (OperationCanceledException) { process.Kill(true); await process.WaitForExitAsync(); throw new TimeoutException("Owned application recovery probe did not finish."); }
        Assert.True(process.ExitCode == 0, await output + await errors);
    }

    public static int Main(string[] args)
    {
        if (args.Length != 1 || args[0] != "--recovery-boundaries") { Console.Error.WriteLine("Use --recovery-boundaries for the owned native test fixture."); return 2; }
        try { ExerciseRecoveryBoundaries(); Console.WriteLine("Application recovery boundaries passed."); return 0; }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }

    private static void ExerciseRecoveryBoundaries()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            var directory = Path.Combine(Path.GetTempPath(), "Luna.App.Tests", Guid.NewGuid().ToString());
            Directory.CreateDirectory(directory);
            var app = new IsolatedApp { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var unhandled = new List<Exception>();
            app.DispatcherUnhandledException += (_, e) => { unhandled.Add(e.Exception); e.Handled = true; };
            typeof(App).GetProperty("Recordings", Private)!.SetValue(app, directory);
            app.Settings.AutoCopyForLlms = false; app.Settings.AutoDelete = false; app.Settings.FloatingBar = false;
            app.Settings.SystemAudio = false; app.Settings.Microphone = "none";
            try
            {
                // Exercise the real async-void Copy handler without touching the clipboard.
                var index = 0;
                foreach (var metadata in new string?[] { null, "{broken", "{}" })
                {
                    var clip = Path.Combine(directory, $"Recording_refusal_{index++}.mp4");
                    File.WriteAllBytes(clip, [1]);
                    var sidecar = RecordingFiles.MetadataPath(clip);
                    if (metadata == null) File.Delete(sidecar); else File.WriteAllText(sidecar, metadata);
                    var library = new LibraryWindow(app);
                    try
                    {
                        library.SelectPath(clip);
                        // Playback is outside this test; close it before the copy action.
                        typeof(LibraryWindow).GetMethod("Release", Private)!.Invoke(library, null);
                        var notice = (TextBlock)typeof(LibraryWindow).GetField("notice", Private)!.GetValue(library)!;
                        PumpUntil(() => false, TimeSpan.FromMilliseconds(100));
                        notice.Text = "";
                        var before = unhandled.Count;
                        var copy = (Button)typeof(LibraryWindow).GetField("copy", Private)!.GetValue(library)!;
                        app.Dispatcher.BeginInvoke(() => copy.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)));
                        PumpUntil(() => notice.Text.StartsWith("Could not copy:") || unhandled.Count > before, TimeSpan.FromSeconds(2));
                        Console.WriteLine($"Metadata {metadata ?? "missing"}: notice={notice.Text}; unhandled={unhandled.Count - before}");
                        Assert.False(File.Exists(Path.ChangeExtension(clip, ".prompt.md")));
                        Assert.True(metadata == null ? !File.Exists(sidecar) : File.ReadAllText(sidecar) == metadata);
                        if (unhandled.Count == before) Assert.StartsWith("Could not copy:", notice.Text);
                    }
                    finally { library.Close(); }
                }

                // A deliberately unsupported container triggers the actual optimizer refusal.
                // This fixture verifies delivery recovery, not playable-video acceptance.
                var saved = Path.Combine(directory, "Recording_optimizer.mp4");
                byte[] original = [.. Box("ftyp", []), .. Box("mdat", [1]), .. Box("moov", []), .. Box("moof", [])];
                File.WriteAllBytes(saved, original);
                Assert.Throws<InvalidDataException>(() => Mp4FastStart.Apply(saved));
                var recorder = Recorder.CreateRecorder(new RecorderOptions
                {
                    AudioOptions = new AudioOptions { IsAudioEnabled = false },
                    SourceOptions = new SourceOptions { RecordingSources = new List<RecordingSourceBase>() },
                    VideoEncoderOptions = new VideoEncoderOptions { IsHardwareEncodingEnabled = false }
                });
                Set(app, "recorder", recorder);
                Set(app, "recordingStream", new FileStream(saved, FileMode.Open, FileAccess.ReadWrite, FileShare.Read));
                Set(app, "recordingPath", saved); Set(app, "hasFirstFrame", true);
                Set(app, "recordingEnvironment", new RecordingEnvironment(11, 26200, 1536, 864, 1.25));
                app.Dispatcher.BeginInvoke(() => typeof(App).GetMethod("CompleteRecording", Private)!.Invoke(app, new object?[] { saved, null }));
                PumpUntil(() => !app.IsBusy, TimeSpan.FromSeconds(5));
                Assert.False(app.IsBusy);
                Assert.Equal(original, File.ReadAllBytes(saved));
                Assert.True(File.Exists(Path.ChangeExtension(saved, ".prompt.md")));
                Assert.Equal(Prompt.Create(saved, new RecordingEnvironment(11, 26200, 1536, 864, 1.25)), File.ReadAllText(Path.ChangeExtension(saved, ".prompt.md")));
                Assert.Contains(app.Windows.Cast<Window>().OfType<ToastWindow>(), window => Texts(window).Any(text => text.StartsWith("MP4 index optimization failed; original video kept.")));
                Assert.Empty(Directory.GetFiles(directory, "*.tmp"));
                Assert.Empty(unhandled);
            }
            catch (Exception ex) { failure = ex; }
            finally
            {
                foreach (var window in app.Windows.Cast<Window>().ToArray()) window.Close();
                app.Shutdown();
                Directory.Delete(directory, true);
            }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure != null) ExceptionDispatchInfo.Capture(failure).Throw();
    }

    private sealed class IsolatedApp : App
    {
        protected override void OnStartup(StartupEventArgs e) { }
    }
    private static void Set(App app, string field, object value) => typeof(App).GetField(field, Private)!.SetValue(app, value);
    private static void PumpUntil(Func<bool> done, TimeSpan timeout)
    {
        var until = DateTime.UtcNow + timeout;
        while (!done() && DateTime.UtcNow < until)
        {
            var frame = new DispatcherFrame();
            Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => frame.Continue = false));
            Dispatcher.PushFrame(frame); Thread.Sleep(10);
        }
    }
    private static IEnumerable<string> Texts(System.Windows.DependencyObject root)
    {
        if (root is TextBlock text) yield return text.Text;
        for (var i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var child in Texts(System.Windows.Media.VisualTreeHelper.GetChild(root, i))) yield return child;
    }
    private static byte[] Box(string type, byte[] payload)
    {
        var bytes = new byte[payload.Length + 8]; BinaryPrimitives.WriteUInt32BigEndian(bytes, (uint)bytes.Length);
        System.Text.Encoding.ASCII.GetBytes(type).CopyTo(bytes, 4); payload.CopyTo(bytes, 8); return bytes;
    }
}
