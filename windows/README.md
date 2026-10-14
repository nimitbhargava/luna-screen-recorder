# Luna for Windows

Windows preview for [issue #1](https://github.com/nimitbhargava/luna-screen-recorder/issues/1). The macOS application is unchanged.

## Build and test

Install the .NET 10 SDK. From the repository root:

```sh
dotnet test windows/tests/Luna.Core.Tests
dotnet build windows/src/Luna.App -c Release
# Windows only: WPF, file-release and recording-recovery regression tests
dotnet test windows/tests/Luna.App.Tests -c Release
```

The Core project contains no Windows APIs and its tests run on Linux and macOS. The WPF app targets x64 Windows 10 build 19041 or later. Native preview evidence below is from Windows 11; Windows 10 remains unverified.

The exe icon is generated from `assets/luna_mascot.png`. Regenerate it on Windows with `powershell -File windows/generate-icon.ps1`; do not edit the ICO by hand.

## Package

On Windows with Visual Studio C++ build tools available:

```powershell
./windows/package.ps1
```

The script publishes a self-contained x64 application, copies the app-local Visual C++ runtime DLLs required by ScreenRecorderLib, and creates `Luna-Windows-x64.zip`. Do not distribute a publish folder without these DLLs. The Actions workflow runs portable tests on all three platforms and uploads the Windows zip.

The executable is unsigned. Windows SmartScreen may show a warning: inspect the source and artifact, then choose **More info**, **Run anyway** if you trust the build. Windows N editions require the Media Feature Pack.

## Quick Windows MVP

Unzip the complete `Luna-Windows-x64.zip` into a writable folder and run `Luna.exe`. No .NET installation or administrator rights are required. Keep all bundled DLLs beside the executable. Luna opens a first-run guide, then lives in the tray and floating bar. Recordings and context files are saved under the Videos known folder in `ScreenRecordings`; settings are in `%APPDATA%\Luna\settings.json`.

- Ctrl+Alt+1: drag an area; click records that monitor; Esc cancels.
- Ctrl+Alt+2: select a window or screen, then Record. Windows have a live preview.
- Ctrl+Alt+3: record the monitor under the cursor.
- Ctrl+Alt+P: pause/resume; Ctrl+Alt+S: stop and save.
- Ctrl+Alt+F: toggle the floating bar; Ctrl+Alt+R: Library.

The floating bar and tray expose system audio and microphone choices. With neither audio source enabled, the MP4 still contains a silent AAC track. Stop writes the MP4, `.prompt.md`, and original `.environment.json` context. Auto-copy puts the prompt text on the clipboard; disabling it leaves the clipboard unchanged. The Library supports paused playback, scrubbing/volume, batch copy, Explorer and manual deletion to the Recycle Bin. Automatic retention is enabled by default and permanently deletes owned recordings and sidecars older than 15 days; choose 7, 15, 30 or 60 days or disable it in Settings. Existing prompts can be copied for legacy clips. If a prompt is missing, regeneration requires valid original environment metadata; otherwise Library shows `Could not copy` and leaves the clipboard unchanged. Recording context is never invented.

This quick version uses pinned ScreenRecorderLib 7.0.1 with H.264 High with a requested 30 fps, faststart, and unconstrained VBR. The native encoder is asked for faststart. If the index is left at the end, a background relocation pass moves it without re-encoding or requiring ffmpeg. Saving progress appears in the bar, tray and Library. Long recordings and slow storage can take more than two seconds; the upstream two-second stop criterion is not fully satisfied. An optimization failure preserves the original MP4 and still attempts context and clipboard delivery, with a warning that faststart is not guaranteed. The issue's bitrate formula configures average bitrate, not a strict cap. Keyframes use the encoder default; a one-second interval is not guaranteed. The user accepted lower recording quality to get a working Windows version now. These deviations remain visible for later issue acceptance; no upstream extension is required to run this build.

Stopping before the encoder has produced a frame cancels the take, removes the empty file, and shows a recording failure notice. Area selection tolerates horizontal and vertical movement before the drag has both dimensions.

Area and screen sources explicitly use Windows Graphics Capture, as window sources already do. Desktop Duplication failed to initialize on a tested hybrid AMD/NVIDIA system when the executable was named `Luna.exe`; switching only the display capture API resolved that failure. Keep the executable name and the bundled dependencies intact.

The preview uses software H.264 encoding. Hardware encoding intermittently stalled in native finalization and also produced `0xc00d36b5` encoder failures in the accepted baseline on the tested hybrid-GPU machine. Changing only the supported hardware-encoding option to Off completed controlled Area, Window and repeated Screen captures. Software encoding can use more CPU and the measured average frame rate remains below 30 fps. This improves the observed native behavior on this machine; it is not evidence of universal encoder or timing guarantees.

The Library currently shows file/date/size rows rather than per-clip thumbnail and duration badges; its Fullscreen button opens the player across the monitor with playback controls and an Exit fullscreen button; Esc returns to inline playback. Click highlighting is enabled for Area and Screen capture, but disabled for Window capture. Mixed-DPI geometry, all audio combinations/privacy settings, Windows N, Gemini upload and clean Windows Sandbox need the manual checks below. Local synthetic own-window capture is evidence for actual video/stop/clipboard behavior, not proof of every real-monitor acceptance item. The app makes no network calls.

## Tested preview and remaining acceptance

The accepted source baseline `f5a29dc` was tested with real application components in an isolated driver named `Luna.exe`, using synthetic content and audio off. This bypassed normal App startup to preserve the user's existing instance and settings. Area, picked window and cursor-monitor capture produced playable H.264 MP4, one silent AAC 48 kHz stereo track, moov before mdat, context files and identical plain-text clipboard content. The actual bar's Pause, Resume and Stop controls were exercised. This evidence does not establish normal packaged startup or the original system-audio/microphone configuration.

Test machine: Windows 11 build 26200, x64; one 1920×1080 monitor at 125% (120 DPI); AMD Radeon(TM) Graphics driver 31.0.12044.3 and NVIDIA RTX 3050 Ti Laptop GPU driver 32.0.15.9282; native .NET runtime 10.0.12.

Strict frame-rate acceptance remains open: the accepted pause/resume clips had nominal rates 30/1 (area/window) and 120/1 (screen), with average rates 27.53, 27.26 and 26.70 fps respectively. Do not mark the 30 fps criterion passed. Normal startup/single instance/global hotkeys, live audio combinations, microphone privacy, 150% and mixed-DPI geometry, moving/closing a window, display removal, Windows N, Gemini upload, and a clean Windows Sandbox remain unverified. Thumbnails and duration badges, a strict bitrate cap and a one-second GOP are still missing. Native HWND regression tests cover popup exclusion, but full exclusion acceptance across all capture modes needs further testing.

## Before opening a pull request

Use one feature branch and one PR referencing issue #1. This preview leaves unverified and unmet acceptance criteria open, so do not claim that it closes the full issue. Keep scaffold/CI, recording/stop flow and Library/settings changes in separate tested milestone commits. Stage only the allowed Windows paths; do not normalize unrelated macOS line endings. Fork and push only after reviewing the complete diff and local validation. The PR must include real-machine details, the acceptance checklist with honest missing items, screenshots, a demo recorded by Luna for Windows itself under 10 MB, and ffprobe evidence per capture mode. Record the AI agent/model used as the issue requests, without adding an AI commit coauthor.

## Native acceptance checklist

- Unzip the actual self-contained CI artifact in Windows Sandbox with no .NET or VC++ redistributable installed; confirm normal startup without elevation or missing DLLs.
- Check first-run Welcome, dismissed Welcome returning next launch, single-instance Library activation, hotkey conflicts, persistent/corrupt settings recovery and dynamic retention labels.
- Test area, picked-window and cursor-monitor capture at 150% and mixed-monitor scales, including negative monitor coordinates. Confirm all Luna UI is excluded, clicks are highlighted, and window closure/display removal saves existing video.
- Verify pause removes five seconds and timer pauses. Check responsive saving, progress, MP4 preservation, plain-text clipboard and toast delivery, including long takes and slow storage. The original universal two-second finalization criterion remains unmet for this preview. Test auto-copy disabled with clipboard unchanged.
- For all four audio combinations, verify exactly one AAC 48 kHz stereo track; both sources must be audible and no-sources must be silent. Check microphone privacy denial and device fallback.
- Inspect H.264 High, 30 fps, even logical dimensions, keyframe interval, constrained bitrate/file size and moov-before-mdat with ffprobe/atom inspection. Upload to Gemini in Chrome without a format error.
- Exercise Library player/scrubber, batch text/file copy, Explorer, empty state and deletion immediately after playback. Confirm media and sidecars go to the Recycle Bin.
- Backdate an owned take by eight days with retention seven; confirm it and sidecars are removed on next launch while an unrelated `notes.mp4` and open/in-progress takes remain.
- Capture final UI screenshots and a synthetic-content demo. Record Windows build, CPU architecture, monitors and scale percentages. Do not mark an unexecuted check as passed.
