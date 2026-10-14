using System;
using System.IO;
using System.Threading.Tasks;
using Luna.Core;
using Xunit;

namespace Luna.App.Tests;

public class RecordingCompletionTests
{
    [Fact]
    public async Task DiscardUnrecordedWaitsForEncoderToReleaseEmptyFile()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        var take = Path.Combine(directory, "Recording_startup.mp4");
        try
        {
            var writer = new FileStream(take, FileMode.Create, FileAccess.Write, FileShare.Read);
            var removal = RecordingFiles.DiscardUnrecordedAsync(take);
            Assert.True(File.Exists(take)); Assert.False(removal.IsCompleted);
            writer.Dispose();
            await removal;
            Assert.False(File.Exists(take));
        }
        finally { Directory.Delete(directory, true); }
    }
    [Fact]
    public async Task DiscardUnrecordedReportsPersistentLockWithoutClaimingSave()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString()); Directory.CreateDirectory(directory);
        var take = Path.Combine(directory, "Recording_locked.mp4");
        try
        {
            using var writer = new FileStream(take, FileMode.Create, FileAccess.Write, FileShare.Read);
            await Assert.ThrowsAsync<IOException>(() => RecordingFiles.DiscardUnrecordedAsync(take));
            Assert.True(File.Exists(take));
        }
        finally { Directory.Delete(directory, true); }
    }

}
