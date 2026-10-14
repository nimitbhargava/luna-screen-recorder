using System.Buffers.Binary;
using System.Text;

namespace Luna.Core;

// Relocates the index of SRL's nonfragmented MP4 without re-encoding or external tools.
public static class Mp4FastStart
{
    private readonly record struct Box(long Offset, long Size, int Header, string Type);

    public static void Apply(string path, IProgress<double>? progress = null)
    {
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                var boxes = ReadBoxes(input, 0, input.Length).ToArray();
                var indices = boxes.Where(b => b.Type == "moov").ToArray();
                var media = boxes.Where(b => b.Type == "mdat").ToArray();
                if (indices.Length != 1 || media.Length == 0 || boxes.Any(b => b.Type == "moof")) throw new InvalidDataException("Expected a nonfragmented MP4 with one index.");
                var index = indices[0];
                if (index.Offset < media[0].Offset) { progress?.Report(1); return; }
                if (index.Size > 64 * 1024 * 1024) throw new InvalidDataException("MP4 index is too large.");
                var bytes = new byte[(int)index.Size]; input.Position = index.Offset; input.ReadExactly(bytes);
                Patch(bytes, index.Header, bytes.Length, index, media);
                using var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                foreach (var box in boxes)
                {
                    if (box == media[0]) output.Write(bytes);
                    if (box == index) continue;
                    input.Position = box.Offset; Copy(input, output, box.Size, input.Length, progress);
                }
                output.Flush(true);
            }
            File.Move(temporary, path, true);
            progress?.Report(1);
        }
        finally
        {
            // Preserve the original error if temporary-file cleanup also fails.
            try { if (File.Exists(temporary)) File.Delete(temporary); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }
    }

    private static IEnumerable<Box> ReadBoxes(Stream input, long start, long end)
    {
        var header = new byte[16];
        for (var offset = start; offset < end;)
        {
            if (end - offset < 8) throw new InvalidDataException("Incomplete MP4 box header.");
            input.Position = offset; input.ReadExactly(header.AsSpan(0, 8));
            long size = BinaryPrimitives.ReadUInt32BigEndian(header); var headerSize = 8;
            if (size == 1)
            {
                if (end - offset < 16) throw new InvalidDataException("Incomplete extended MP4 box header.");
                input.ReadExactly(header.AsSpan(8, 8));
                var extended = BinaryPrimitives.ReadUInt64BigEndian(header.AsSpan(8));
                if (extended > long.MaxValue) throw new InvalidDataException("MP4 box is too large.");
                size = (long)extended; headerSize = 16;
            }
            if (size == 0) size = end - offset;
            if (size < headerSize || size > end - offset) throw new InvalidDataException("Invalid MP4 box size.");
            yield return new Box(offset, size, headerSize, System.Text.Encoding.ASCII.GetString(header, 4, 4));
            offset += size;
        }
    }

    private static void Patch(byte[] bytes, int start, int end, Box index, Box[] media)
    {
        using var stream = new MemoryStream(bytes, false);
        foreach (var box in ReadBoxes(stream, start, end))
        {
            var body = (int)box.Offset + box.Header; var limit = (int)(box.Offset + box.Size);
            if (box.Type is "trak" or "mdia" or "minf" or "stbl") Patch(bytes, body, limit, index, media);
            else if (box.Type is "stco" or "co64")
            {
                var width = box.Type == "co64" ? 8 : 4;
                if (limit - body < 8) throw new InvalidDataException("Incomplete MP4 chunk table.");
                var count = BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(body + 4));
                if (count > (limit - body - 8) / width) throw new InvalidDataException("Incomplete MP4 chunk offsets.");
                for (var entry = body + 8; count > 0; count--, entry += width)
                {
                    ulong offset = width == 8 ? BinaryPrimitives.ReadUInt64BigEndian(bytes.AsSpan(entry)) : BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(entry));
                    if (!media.Any(m => offset >= (ulong)(m.Offset + m.Header) && offset < (ulong)(m.Offset + m.Size))) throw new InvalidDataException("MP4 chunk lies outside its media data.");
                    var shifted = offset >= (ulong)media[0].Offset && offset < (ulong)index.Offset ? checked(offset + (ulong)index.Size) : offset;
                    if (width == 8) BinaryPrimitives.WriteUInt64BigEndian(bytes.AsSpan(entry), shifted);
                    else if (shifted <= uint.MaxValue) BinaryPrimitives.WriteUInt32BigEndian(bytes.AsSpan(entry), (uint)shifted);
                    else throw new InvalidDataException("MP4 chunk offset requires a 64-bit table.");
                }
            }
        }
    }

    private static void Copy(Stream input, Stream output, long remaining, long total, IProgress<double>? progress)
    {
        var buffer = new byte[81920];
        var lastPercent = (int)(output.Position * 100.0 / total);
        while (remaining > 0)
        {
            var count = input.Read(buffer, 0, (int)Math.Min(buffer.Length, remaining));
            if (count == 0) throw new EndOfStreamException("MP4 changed during index relocation.");
            output.Write(buffer, 0, count); remaining -= count;
            var percent = (int)(output.Position * 100.0 / total);
            if (percent > lastPercent) { progress?.Report(Math.Min(0.99, percent / 100.0)); lastPercent = percent; }
        }
    }
}
