using System.Buffers.Binary;
using Luna.Core;
using Xunit;

namespace Luna.Core.Tests;

public class Mp4FastStartTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void MovesIndexBeforeMediaAndPreservesChunkData(bool wide)
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".mp4");
        var prefix = Box("ftyp", [0, 0, 0, 0]);
        byte[] sample = [11, 22, 33, 44];
        var media = Box("mdat", sample);
        var table = new byte[wide ? 16 : 12];
        BinaryPrimitives.WriteUInt32BigEndian(table.AsSpan(4), 1);
        if (wide) BinaryPrimitives.WriteUInt64BigEndian(table.AsSpan(8), (ulong)prefix.Length + 8);
        else BinaryPrimitives.WriteUInt32BigEndian(table.AsSpan(8), (uint)prefix.Length + 8);
        var index = Box("moov", Box("trak", Box("mdia", Box("minf", Box("stbl", Box(wide ? "co64" : "stco", table))))));
        try
        {
            File.WriteAllBytes(path, [.. prefix, .. media, .. index]);
            var reports = new List<double>();
            Mp4FastStart.Apply(path, new ImmediateProgress(reports.Add));
            Assert.NotEmpty(reports); Assert.Equal(1, reports[^1]);
            Assert.All(reports, value => Assert.InRange(value, 0, 1));
            Assert.Equal(reports.OrderBy(value => value), reports);
            var bytes = File.ReadAllBytes(path);
            Assert.Equal("moov", System.Text.Encoding.ASCII.GetString(bytes, prefix.Length + 4, 4));
            var offsetPosition = prefix.Length + 5 * 8 + 8 + 8;
            var offset = wide ? BinaryPrimitives.ReadUInt64BigEndian(bytes.AsSpan(offsetPosition)) : BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(offsetPosition));
            Assert.Equal((ulong)(prefix.Length + index.Length + 8), offset);
            Assert.Equal(sample, bytes.AsSpan((int)offset, sample.Length).ToArray());
            var original = bytes.ToArray(); Mp4FastStart.Apply(path);
            Assert.Equal(original, File.ReadAllBytes(path));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void InvalidChunkTableLeavesOriginalUntouched()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".mp4");
        var table = new byte[12]; BinaryPrimitives.WriteUInt32BigEndian(table.AsSpan(4), 99);
        byte[] original = [.. Box("ftyp", []), .. Box("mdat", [1]), .. Box("moov", Box("trak", Box("mdia", Box("minf", Box("stbl", Box("stco", table))))))];
        try
        {
            File.WriteAllBytes(path, original);
            Assert.Throws<InvalidDataException>(() => Mp4FastStart.Apply(path));
            Assert.Equal(original, File.ReadAllBytes(path));
        }
        finally { File.Delete(path); }
    }

    private sealed class ImmediateProgress(Action<double> report) : IProgress<double>
    {
        public void Report(double value) => report(value);
    }

    private static byte[] Box(string type, byte[] payload)
    {
        var bytes = new byte[payload.Length + 8];
        BinaryPrimitives.WriteUInt32BigEndian(bytes, (uint)bytes.Length);
        System.Text.Encoding.ASCII.GetBytes(type).CopyTo(bytes, 4); payload.CopyTo(bytes, 8);
        return bytes;
    }
}
