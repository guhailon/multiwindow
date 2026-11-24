# MultiWindow
Reference usage of FrontBoard &amp; UIKit private API to display external app scene.

This app implements multitasking.

## 1.0.2 (2026-11-24)
Diagnostic logging only, no behavior change. 1.0.1 still showed Settings
squeezed into the left ~55% on device, so this build logs every frame the
scene is created at, every frame the presenter view ends up with, and every
re-sync (app path) plus the tweak window geometry (tweak path) to NSLog
(tag MWLOG) and /var/mobile/Library/Logs/MultiWindow.log.

## 1.0.1 fix (2026-11-23)
Floating windows showed the hosted app as a clipped strip (Settings) or
fully blank (QQ): the scene was created at the transient contentView size
captured mid-open-animation, the presenter view was never resized, and
nothing re-synced the scene on resize/drag. Fixed by creating the scene at
the intended final content size, pinning the presenter view to the content
frame with autoresizing, and re-syncing scene + presenter view whenever the
content size changes (layout + drag-resize). QQ may still be blank if it is
the single-scene limit (see Known issues) — that needs hosting the existing
scene instead of creating a new one, and is not part of this fix.

## Supported iOS versions
Requires TrollStore.

iOS 15.0+ are supported.

iOS 14.x is not yet supported. There is an issue in FrontBoard.

## Known issues
- Apps stay running even after closing
- In-app keyboard offset may be off
- Keyboard doesn't work when windowed on top of SpringBoard yet
- Re-opening an app after closing may crash
- Single-scene apps may not work yet. You may see empty window in such cases.

## Version notes (GuHaiLong fixes)
- 1.0.1: hosted scene frame tracking fix (blank/clipped floating windows).
- 1.0.2: diagnostic logging only (MWLOG to /var/mobile/Library/Logs/MultiWindow.log).
- 1.0.3: in-app log viewer (查看日志 in the 设置 menu: 刷新/分享/清空).
