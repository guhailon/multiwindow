# MultiWindow
Reference usage of FrontBoard &amp; UIKit private API to display external app scene.

This app implements multitasking.

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
