using System.Globalization;
using System.Text.Json;

namespace Luna.Core;

public enum CaptureMode { Area, Window, Screen }
public readonly record struct VideoSize(int Width, int Height);
public readonly record struct RecordingEnvironment(int Major, int Build, int Width, int Height, double Scale);
public readonly record struct ClipFile(string Path, DateTimeOffset LastWriteTime);

public static class Encoding
{
    public static VideoSize Size(int physicalWidth, int physicalHeight, double scale, CaptureMode mode)
    {
        if (physicalWidth <= 0 || physicalHeight <= 0 || !double.IsFinite(scale) || scale <= 0) throw new ArgumentOutOfRangeException(nameof(scale));
        var w = (int)(physicalWidth / scale); var h = (int)(physicalHeight / scale);
        if (w > 2560) { w /= 2; h /= 2; }
        var min = mode == CaptureMode.Window ? new VideoSize(320, 240) : new VideoSize(160, 120);
        return new(Math.Max(min.Width, w & ~1), Math.Max(min.Height, h & ~1));
    }
    public static int BitrateCeiling(VideoSize size) => (int)Math.Clamp((long)size.Width * size.Height * 2, 1_500_000, 3_500_000);
}

public sealed class Settings
{
    public bool AutoCopyForLlms { get; set; } = true;
    public bool AutoDelete { get; set; } = true;
    public int RetentionDays { get; set; } = 15;
    public bool SystemAudio { get; set; } = true;
    public bool FloatingBar { get; set; } = true;
    public string Microphone { get; set; } = "system_default";
    public bool OnboardingCompleted { get; set; }
    public Dictionary<string, string> Hotkeys { get; set; } = Defaults();
    public static Dictionary<string, string> Defaults() => new() { ["area"] = "Ctrl+Alt+1", ["picker"] = "Ctrl+Alt+2", ["fullScreen"] = "Ctrl+Alt+3", ["stop"] = "Ctrl+Alt+S", ["pause"] = "Ctrl+Alt+P", ["floatingBar"] = "Ctrl+Alt+F", ["library"] = "Ctrl+Alt+R" };
    internal static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true };
    public static Settings Parse(string json)
    {
        var s = JsonSerializer.Deserialize<Settings>(json, JsonOptions) ?? throw new JsonException("Settings must be an object.");
        if (s.RetentionDays is not (7 or 15 or 30 or 60)) s.RetentionDays = 15;
        s.Microphone = string.IsNullOrWhiteSpace(s.Microphone) ? "system_default" : s.Microphone;
        var provided = s.Hotkeys; s.Hotkeys = Defaults();
        if (provided != null) foreach (var (key, value) in provided) if (s.Hotkeys.ContainsKey(key) && !string.IsNullOrWhiteSpace(value)) s.Hotkeys[key] = value;
        return s;
    }
}

public sealed class SettingsStore(string path)
{
    public (Settings Settings, bool Recovered) Load()
    {
        if (!File.Exists(path)) return (new(), false);
        try { return (Settings.Parse(File.ReadAllText(path)), false); }
        catch (JsonException) { File.Move(path, path + ".bad", true); return (new(), true); }
    }
    public void Save(Settings settings)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, JsonSerializer.Serialize(settings, Settings.JsonOptions)); File.Move(temporary, path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

public static class RecordingFiles
{
    public static string NextName(DateTime localTime, Func<string, bool> exists)
    {
        var stem = "Recording_" + localTime.ToString("yyyy-MM-dd_HH-mm-ss", CultureInfo.InvariantCulture);
        var candidate = stem + ".mp4"; var suffix = 2;
        while (exists(candidate)) candidate = stem + "_" + (suffix++) + ".mp4";
        return candidate;
    }
    public static async Task DiscardUnrecordedAsync(string path)
    {
        // A watcher may briefly hold a take after the encoder releases its output handle.
        for (var attempt = 0; ; attempt++)
        {
            try { File.Delete(path); return; }
            catch (IOException) when (attempt < 9) { await Task.Delay(50); }
        }
    }
    public static bool IsOwned(string path) => Path.GetFileName(path).StartsWith("Recording_", StringComparison.Ordinal) && Path.GetExtension(path).Equals(".mp4", StringComparison.OrdinalIgnoreCase);
    public static string MetadataPath(string mp4) => Path.ChangeExtension(mp4, ".environment.json");
    public static IEnumerable<string> Sidecars(string mp4)
    {
        var stem = Path.Combine(Path.GetDirectoryName(mp4)!, Path.GetFileNameWithoutExtension(mp4));
        return new[] { stem + ".prompt.md", MetadataPath(mp4), stem + ".events.json", stem + ".gif", stem + ".keyframes", mp4 };
    }
    public static FileAttributes? AttributesIfPresent(string path) => AttributesIfPresent(path, File.GetAttributes);
    internal static FileAttributes? AttributesIfPresent(string path, Func<string, FileAttributes> getAttributes)
    {
        try { return getAttributes(path); }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
    }
    public static void EnsureDeletable(string mp4, Action<string>? probeDirectory = null) => EnsureDeletable(mp4, probeDirectory, File.GetAttributes);
    internal static void EnsureDeletable(string mp4, Action<string>? probeDirectory, Func<string, FileAttributes> getAttributes)
    {
        foreach (var path in Sidecars(mp4))
        {
            var attributes = AttributesIfPresent(path, getAttributes);
            if (attributes is null) continue;
            if ((attributes.Value & FileAttributes.Directory) != 0)
            {
                var entries = Directory.EnumerateFileSystemEntries(path, "*", SearchOption.AllDirectories).ToArray();
                probeDirectory?.Invoke(path);
                foreach (var entry in entries)
                {
                    var entryAttributes = AttributesIfPresent(entry, getAttributes);
                    if (entryAttributes is null) continue;
                    if ((entryAttributes.Value & FileAttributes.Directory) != 0) probeDirectory?.Invoke(entry);
                    else Probe(entry, entryAttributes.Value);
                }
            }
            else Probe(path, attributes.Value);
        }
        static void Probe(string path, FileAttributes attributes)
        {
            if ((attributes & FileAttributes.ReadOnly) != 0) throw new IOException("Recording file is read-only: " + path);
            using var probe = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        }
    }
}

public static class Retention
{
    public static (IReadOnlyList<string> Deleted, IReadOnlyList<string> Skipped) Clean(string directory, DateTimeOffset now, int days, string? inProgress = null, Action<string>? probeDirectory = null) => Clean(directory, now, days, inProgress, probeDirectory, File.GetAttributes);
    internal static (IReadOnlyList<string> Deleted, IReadOnlyList<string> Skipped) Clean(string directory, DateTimeOffset now, int days, string? inProgress, Action<string>? probeDirectory, Func<string, FileAttributes> getAttributes)
    {
        var deleted = new List<string>(); var skipped = new List<string>();
        var candidates = Candidates(Directory.EnumerateFiles(directory, "Recording_*.mp4").Select(f => new ClipFile(f, File.GetLastWriteTimeUtc(f))), now, days, inProgress);
        foreach (var path in candidates)
        {
            try
            {
                RecordingFiles.EnsureDeletable(path, probeDirectory, getAttributes);
                foreach (var sidecar in RecordingFiles.Sidecars(path))
                {
                    var attributes = RecordingFiles.AttributesIfPresent(sidecar, getAttributes);
                    if (attributes is null) continue;
                    if ((attributes.Value & FileAttributes.Directory) != 0) Directory.Delete(sidecar, true);
                    else File.Delete(sidecar);
                }
                deleted.Add(path);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { skipped.Add(path); }
        }
        return (deleted, skipped);
    }
    public static IEnumerable<string> Candidates(IEnumerable<ClipFile> files, DateTimeOffset now, int days, string? inProgress = null)
    {
        if (days is not (7 or 15 or 30 or 60)) throw new ArgumentOutOfRangeException(nameof(days));
        var cutoff = now.AddDays(-days);
        return files.Where(f => RecordingFiles.IsOwned(f.Path) && f.LastWriteTime < cutoff && !string.Equals(f.Path, inProgress, StringComparison.OrdinalIgnoreCase)).Select(f => f.Path);
    }
}

public static class Prompt
{
    public static string Create(string mp4, RecordingEnvironment e) => $"{mp4}\n\n### Screen Recording Context & Interaction Log\n- **Video File**: `{mp4}`\n- **Environment**: Windows {e.Major} (build {e.Build}) | {e.Width}×{e.Height} @ {e.Scale.ToString("0.###", CultureInfo.InvariantCulture)}x\n";
    public static string Write(string mp4, RecordingEnvironment environment)
    {
        if (!Valid(environment)) throw new ArgumentException("Recording environment is incomplete.", nameof(environment));
        File.WriteAllText(RecordingFiles.MetadataPath(mp4), JsonSerializer.Serialize(environment));
        var text = Create(mp4, environment);
        File.WriteAllText(Path.ChangeExtension(mp4, ".prompt.md"), text);
        return text;
    }
    public static string LoadOrRegenerate(string mp4)
    {
        var path = Path.ChangeExtension(mp4, ".prompt.md");
        if (File.Exists(path)) return File.ReadAllText(path);
        var metadata = RecordingFiles.MetadataPath(mp4);
        if (!File.Exists(metadata)) throw new InvalidDataException("Original recording environment is unavailable; this prompt cannot be regenerated.");
        RecordingEnvironment environment;
        try { environment = JsonSerializer.Deserialize<RecordingEnvironment>(File.ReadAllText(metadata)); }
        catch (JsonException ex) { throw new InvalidDataException("Original recording environment is invalid; this prompt cannot be regenerated.", ex); }
        if (!Valid(environment)) throw new InvalidDataException("Original recording environment is invalid; this prompt cannot be regenerated.");
        return Write(mp4, environment);
    }
    private static bool Valid(RecordingEnvironment e) => e.Major > 0 && e.Build > 0 && e.Width > 0 && e.Height > 0 && double.IsFinite(e.Scale) && e.Scale > 0;
    public static string Batch(IEnumerable<(string Path, string Prompt)> clips)
    {
        var all = clips.ToArray();
        return string.Join("\n", all.Select(c => c.Path)) + "\n\n\n---\n\n\n" + string.Join("\n", all.Select((c, i) => $"### Recording {i + 1}: `{System.IO.Path.GetFileName(c.Path)}`\n" + c.Prompt[(c.Prompt.IndexOf('\n') + 1)..]));
    }
}

public readonly record struct Hotkey(uint Modifiers, uint Key)
{
    public static Hotkey Parse(string value)
    {
        var parts = value.Split('+'); uint modifiers = 0;
        foreach (var part in parts[..^1])
        {
            var bit = part.ToUpperInvariant() switch { "ALT" => 1u, "CTRL" => 2u, "SHIFT" => 4u, "WIN" => 8u, _ => throw new FormatException("Unknown modifier.") };
            if ((modifiers & bit) != 0) throw new FormatException("Duplicate modifier."); modifiers |= bit;
        }
        var key = parts[^1].ToUpperInvariant();
        if (key.Length != 1 || !char.IsAsciiLetterOrDigit(key[0])) throw new FormatException("Expected a letter or digit key.");
        return new(modifiers, key[0]);
    }
}

public static class AreaGesture
{
    public static bool IsScreen(double width, double height) => width < 15 && height < 15;
    public static bool MustRetry(double width, double height) => !IsScreen(width, height) && (width < 20 || height < 20);
}
