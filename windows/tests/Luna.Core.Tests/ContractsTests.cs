using Luna.Core;
using Xunit;

namespace Luna.Core.Tests;

public sealed class ContractsTests
{
    [Fact]
    public void DefaultsMatchThePublicContract()
    {
        var s = new Settings();
        Assert.True(s.AutoCopyForLlms && s.AutoDelete && s.SystemAudio && s.FloatingBar);
        Assert.False(s.OnboardingCompleted);
        Assert.Equal(15, s.RetentionDays);
        Assert.Equal("system_default", s.Microphone);
        Assert.Equal("Ctrl+Alt+3", s.Hotkeys["fullScreen"]);
    }
    [Theory]
    [InlineData(3840, 2160, 1.5, CaptureMode.Screen, 2560, 1440)]
    [InlineData(3840, 2160, 1.0, CaptureMode.Screen, 1920, 1080)]
    [InlineData(21, 21, 1.5, CaptureMode.Area, 160, 120)]
    [InlineData(101, 103, 1.0, CaptureMode.Window, 320, 240)]
    [InlineData(1921, 1081, 1.0, CaptureMode.Screen, 1920, 1080)]
    public void OutputUsesLogicalEvenDimensions(int w, int h, double scale, CaptureMode mode, int ew, int eh)
        => Assert.Equal(new VideoSize(ew, eh), Encoding.Size(w, h, scale, mode));
    [Theory]
    [InlineData(160, 120, 1500000)]
    [InlineData(1000, 1000, 2000000)]
    [InlineData(1920, 1080, 3500000)]
    public void BitrateFormula(int w, int h, int expected) => Assert.Equal(expected, Encoding.BitrateCeiling(new(w, h)));
    [Fact]
    public void PromptIsExactLfText()
        => Assert.Equal("C:\\Videos\\Recording.mp4\n\n### Screen Recording Context & Interaction Log\n- **Video File**: `C:\\Videos\\Recording.mp4`\n- **Environment**: Windows 11 (build 26100) | 2560×1440 @ 1.5x\n", Prompt.Create("C:\\Videos\\Recording.mp4", new(11, 26100, 2560, 1440, 1.5)));
    [Fact]
    public void MissingPromptRegeneratesFromOriginalEnvironment()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        try
        {
            var take = Path.Combine(directory, "Recording_test.mp4");
            var expected = Prompt.Write(take, new(11, 26100, 2560, 1440, 1.5));
            File.Delete(Path.ChangeExtension(take, ".prompt.md"));
            Assert.Equal(expected, Prompt.LoadOrRegenerate(take));
            Assert.Equal(expected, File.ReadAllText(Path.ChangeExtension(take, ".prompt.md")));
        }
        finally { Directory.Delete(directory, true); }
    }
    [Fact]
    public void MissingEnvironmentCannotInventPromptContext()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        try
        {
            var take = Path.Combine(directory, "Recording_legacy.mp4");
            Assert.Contains("Original recording environment is unavailable", Assert.Throws<InvalidDataException>(() => Prompt.LoadOrRegenerate(take)).Message);
            Assert.False(File.Exists(Path.ChangeExtension(take, ".prompt.md")));
        }
        finally { Directory.Delete(directory, true); }
    }
    [Fact]
    public void NamingSkipsExistingTakes()
    {
        var now = new DateTime(2026, 10, 12, 13, 2, 3);
        Assert.Equal("Recording_2026-10-12_13-02-03_3.mp4", RecordingFiles.NextName(now, name => !name.EndsWith("_3.mp4")));
    }
    [Theory]
    [InlineData(7, 7)]
    [InlineData(15, 15)]
    [InlineData(30, 30)]
    [InlineData(60, 60)]
    [InlineData(14, 15)]
    public void RetentionDaysValidated(int input, int expected) => Assert.Equal(expected, Settings.Parse($"{{\"retentionDays\":{input}}}").RetentionDays);
    [Fact]
    public void PartialSettingsRestoreMissingKeys()
    {
        var s = Settings.Parse("{\"autoCopyForLlms\":false,\"hotkeys\":{\"area\":\"Ctrl+Alt+4\"}}");
        Assert.False(s.AutoCopyForLlms); Assert.True(s.SystemAudio);
        Assert.Equal("Ctrl+Alt+4", s.Hotkeys["area"]); Assert.Equal("Ctrl+Alt+S", s.Hotkeys["stop"]);
    }
    [Fact]
    public void RetentionOnlyDeletesOwnedExpiredClosedTakes()
    {
        var now = new DateTimeOffset(2026, 10, 12, 12, 0, 0, TimeSpan.Zero);
        var files = new[] { new ClipFile("Recording_old.mp4", now.AddDays(-8)), new ClipFile("notes.mp4", now.AddDays(-8)), new ClipFile("Recording_new.mp4", now.AddDays(-7)), new ClipFile("Recording_open.mp4", now.AddDays(-8)) };
        Assert.Equal(new[] { "Recording_old.mp4" }, Retention.Candidates(files, now, 7, "Recording_open.mp4"));
    }
    [Fact]
    public void BatchPromptStartsWithPathsAndSeparator()
    {
        var text = Prompt.Batch(new[] { ("a.mp4", "a.mp4\n\ncontext a\n"), ("b.mp4", "b.mp4\n\ncontext b\n") });
        Assert.Equal("a.mp4\nb.mp4\n\n\n---\n\n\n### Recording 1: `a.mp4`\n\ncontext a\n\n### Recording 2: `b.mp4`\n\ncontext b\n", text);
    }
    [Theory]
    [InlineData("Ctrl+Alt+3", 3, 51)]
    [InlineData("Ctrl+Alt+S", 3, 83)]
    public void HotkeysParse(string value, uint mods, uint key) { var h = Hotkey.Parse(value); Assert.Equal(mods, h.Modifiers); Assert.Equal(key, h.Key); }
    [Theory]
    [InlineData("Ctrl+Alt+")]
    [InlineData("Ctrl+Alt+Banana")]
    [InlineData("Alt+Alt+3")]
    public void MalformedHotkeysFail(string value) => Assert.Throws<FormatException>(() => Hotkey.Parse(value));
    [Fact]
    public void CleanupRemovesOwnedSidecarsAndPreservesUnrelatedFiles()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        try
        {
            var take = Path.Combine(directory, "Recording_old.mp4"); File.WriteAllText(take, "take"); File.SetLastWriteTimeUtc(take, DateTime.UtcNow.AddDays(-8));
            File.WriteAllText(Path.ChangeExtension(take, ".prompt.md"), "context");
            File.WriteAllText(RecordingFiles.MetadataPath(take), "metadata");
            Directory.CreateDirectory(Path.ChangeExtension(take, ".keyframes"));
            File.WriteAllText(Path.Combine(directory, "notes.mp4"), "user content");
            var result = Retention.Clean(directory, DateTimeOffset.UtcNow, 7);
            Assert.Single(result.Deleted); Assert.Empty(result.Skipped); Assert.False(File.Exists(take)); Assert.False(File.Exists(Path.ChangeExtension(take, ".prompt.md"))); Assert.False(File.Exists(RecordingFiles.MetadataPath(take))); Assert.False(Directory.Exists(Path.ChangeExtension(take, ".keyframes"))); Assert.True(File.Exists(Path.Combine(directory, "notes.mp4")));
        }
        finally { Directory.Delete(directory, true); }
    }
    [Fact]
    public void CleanupSkipsAnOpenTakeAndItsSidecars()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        try
        {
            var take = Path.Combine(directory, "Recording_locked.mp4"); File.WriteAllText(take, "take"); File.SetLastWriteTimeUtc(take, DateTime.UtcNow.AddDays(-8)); File.WriteAllText(Path.ChangeExtension(take, ".prompt.md"), "context");
            using var open = new FileStream(take, FileMode.Open, FileAccess.Read, FileShare.Read);
            var result = Retention.Clean(directory, DateTimeOffset.UtcNow, 7);
            Assert.Empty(result.Deleted); Assert.Single(result.Skipped); Assert.True(File.Exists(take)); Assert.True(File.Exists(Path.ChangeExtension(take, ".prompt.md")));
        }
        finally { Directory.Delete(directory, true); }
    }
    [Fact]
    public void CleanupRetriesLockedSidecarOnNextRun()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        try
        {
            var take = Path.Combine(directory, "Recording_locked_sidecar.mp4");
            var sidecar = Path.ChangeExtension(take, ".prompt.md");
            File.WriteAllText(take, "take"); File.SetLastWriteTimeUtc(take, DateTime.UtcNow.AddDays(-8)); File.WriteAllText(sidecar, "context");
            using (var open = new FileStream(sidecar, FileMode.Open, FileAccess.Read, FileShare.None))
            {
                var first = Retention.Clean(directory, DateTimeOffset.UtcNow, 7);
                Assert.Empty(first.Deleted); Assert.Single(first.Skipped); Assert.True(File.Exists(take)); Assert.True(File.Exists(sidecar));
            }
            var second = Retention.Clean(directory, DateTimeOffset.UtcNow, 7);
            Assert.Single(second.Deleted); Assert.Empty(second.Skipped); Assert.False(File.Exists(take)); Assert.False(File.Exists(sidecar));
        }
        finally { Directory.Delete(directory, true); }
    }
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void CleanupPreservesEntireClipWhenLaterSidecarIsOpen(bool keyframe)
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        try
        {
            var take = Path.Combine(directory, "Recording_later_locked.mp4");
            var prompt = Path.ChangeExtension(take, ".prompt.md");
            var sidecar = keyframe ? Path.Combine(Path.ChangeExtension(take, ".keyframes"), "frame.png") : RecordingFiles.MetadataPath(take);
            File.WriteAllText(take, "take"); File.SetLastWriteTimeUtc(take, DateTime.UtcNow.AddDays(-8));
            File.WriteAllText(prompt, "context"); Directory.CreateDirectory(Path.GetDirectoryName(sidecar)!); File.WriteAllText(sidecar, "data");
            using (var open = new FileStream(sidecar, FileMode.Open, FileAccess.Read, FileShare.None))
            {
                var first = Retention.Clean(directory, DateTimeOffset.UtcNow, 7);
                Assert.Empty(first.Deleted); Assert.Single(first.Skipped);
                Assert.True(File.Exists(take)); Assert.True(File.Exists(prompt)); Assert.True(File.Exists(sidecar));
            }
            var second = Retention.Clean(directory, DateTimeOffset.UtcNow, 7);
            Assert.Single(second.Deleted); Assert.Empty(second.Skipped);
            Assert.False(File.Exists(take)); Assert.False(File.Exists(prompt)); Assert.False(File.Exists(sidecar));
        }
        finally { Directory.Delete(directory, true); }
    }
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void CleanupProbesEmptyKeyframeDirectoriesBeforeDeleting(bool nested)
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        try
        {
            var take = Path.Combine(directory, "Recording_directory_locked.mp4");
            var prompt = Path.ChangeExtension(take, ".prompt.md");
            var keyframes = Path.ChangeExtension(take, ".keyframes");
            var blocked = nested ? Path.Combine(keyframes, "nested") : keyframes;
            File.WriteAllText(take, "take"); File.SetLastWriteTimeUtc(take, DateTime.UtcNow.AddDays(-8));
            File.WriteAllText(prompt, "context"); Directory.CreateDirectory(blocked);
            var first = Retention.Clean(directory, DateTimeOffset.UtcNow, 7, probeDirectory: path => { if (path == blocked) throw new IOException("Directory is open."); });
            Assert.Empty(first.Deleted); Assert.Single(first.Skipped);
            Assert.True(File.Exists(take)); Assert.True(File.Exists(prompt)); Assert.True(Directory.Exists(blocked));
            var second = Retention.Clean(directory, DateTimeOffset.UtcNow, 7, probeDirectory: _ => { });
            Assert.Single(second.Deleted); Assert.Empty(second.Skipped);
            Assert.False(File.Exists(take)); Assert.False(File.Exists(prompt)); Assert.False(Directory.Exists(keyframes));
        }
        finally { Directory.Delete(directory, true); }
    }
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void CleanupDistinguishesMissingFromUnremovableSidecars(bool keyframe)
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        var take = Path.Combine(directory, "Recording_unremovable.mp4");
        var prompt = Path.ChangeExtension(take, ".prompt.md");
        var sidecar = keyframe ? Path.Combine(Path.ChangeExtension(take, ".keyframes"), "frame.png") : RecordingFiles.MetadataPath(take);
        try
        {
            File.WriteAllText(take, "take"); File.SetLastWriteTimeUtc(take, DateTime.UtcNow.AddDays(-8));
            File.WriteAllText(prompt, "context"); Directory.CreateDirectory(Path.GetDirectoryName(sidecar)!); File.WriteAllText(sidecar, "data");
            Assert.Null(RecordingFiles.AttributesIfPresent(Path.ChangeExtension(take, ".gif")));
            File.SetAttributes(sidecar, File.GetAttributes(sidecar) | FileAttributes.ReadOnly);
            Assert.True((RecordingFiles.AttributesIfPresent(sidecar)!.Value & FileAttributes.ReadOnly) != 0);
            var first = Retention.Clean(directory, DateTimeOffset.UtcNow, 7);
            Assert.Empty(first.Deleted); Assert.Single(first.Skipped);
            Assert.True(File.Exists(take)); Assert.True(File.Exists(prompt)); Assert.True(File.Exists(sidecar));
            File.SetAttributes(sidecar, File.GetAttributes(sidecar) & ~FileAttributes.ReadOnly);
            var second = Retention.Clean(directory, DateTimeOffset.UtcNow, 7);
            Assert.Single(second.Deleted); Assert.Empty(second.Skipped);
            Assert.False(File.Exists(take)); Assert.False(File.Exists(prompt)); Assert.False(File.Exists(sidecar));
        }
        finally
        {
            if (File.Exists(sidecar)) File.SetAttributes(sidecar, File.GetAttributes(sidecar) & ~FileAttributes.ReadOnly);
            Directory.Delete(directory, true);
        }
    }
    [Theory]
    [InlineData(false, false)]
    [InlineData(false, true)]
    [InlineData(true, false)]
    [InlineData(true, true)]
    public void AttributeLookupFailurePreservesClipForRetentionAndLibraryPreflight(bool keyframe, bool denied)
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        try
        {
            var take = Path.Combine(directory, "Recording_inaccessible.mp4");
            var prompt = Path.ChangeExtension(take, ".prompt.md");
            var sidecar = keyframe ? Path.Combine(Path.ChangeExtension(take, ".keyframes"), "frame.png") : RecordingFiles.MetadataPath(take);
            File.WriteAllText(take, "take"); File.SetLastWriteTimeUtc(take, DateTime.UtcNow.AddDays(-8));
            File.WriteAllText(prompt, "context"); Directory.CreateDirectory(Path.GetDirectoryName(sidecar)!); File.WriteAllText(sidecar, "data");
            Exception failure = denied ? new UnauthorizedAccessException("Access denied") : new IOException("Attribute lookup failed");
            FileAttributes GetAttributes(string path) => path == sidecar ? throw failure : File.GetAttributes(path);

            Assert.Same(failure, Record.Exception(() => RecordingFiles.EnsureDeletable(take, null, GetAttributes)));
            var result = Retention.Clean(directory, DateTimeOffset.UtcNow, 7, null, null, GetAttributes);
            Assert.Empty(result.Deleted); Assert.Single(result.Skipped);
            Assert.True(File.Exists(take)); Assert.True(File.Exists(prompt)); Assert.True(File.Exists(sidecar));
        }
        finally { Directory.Delete(directory, true); }
    }
    [Fact]
    public void CorruptSettingsMovedAsideAndWritesRoundTrip()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        try { var path = Path.Combine(directory, "settings.json"); File.WriteAllText(path, "{"); var store = new SettingsStore(path); var result = store.Load(); Assert.True(result.Recovered); Assert.True(File.Exists(path + ".bad")); result.Settings.RetentionDays = 7; store.Save(result.Settings); Assert.Equal(7, store.Load().Settings.RetentionDays); }
        finally { Directory.Delete(directory, true); }
    }
    [Theory]
    [InlineData(3, 4, true, false)]
    [InlineData(14, 14, true, false)]
    [InlineData(15, 14, false, true)]
    [InlineData(20, 19, false, true)]
    [InlineData(20, 20, false, false)]
    public void AreaGestureThresholds(int width, int height, bool screen, bool retry)
    {
        Assert.Equal(screen, AreaGesture.IsScreen(width, height));
        Assert.Equal(retry, AreaGesture.MustRetry(width, height));
    }
    [Fact]
    public async Task DiscardUnrecordedRemovesEmptyFileAndToleratesMissingFile()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        var take = Path.Combine(directory, "Recording_startup.mp4");
        try
        {
            File.WriteAllBytes(take, []);
            await RecordingFiles.DiscardUnrecordedAsync(take);
            Assert.False(File.Exists(take));
            await RecordingFiles.DiscardUnrecordedAsync(take);
        }
        finally { Directory.Delete(directory, true); }
    }

}
