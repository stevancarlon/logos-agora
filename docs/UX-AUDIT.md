# Agora UX audit — 26 October 2026

The main problem was interaction continuity. The interface had working individual controls but did not reliably preserve the reader's place, keep controls reachable, or explain actions at the point of use. Adding hover animations did not address those problems.

This audit covers the native QML application, not the historical React prototype. It combines source inspection, rendered screens, and automated interaction tests with temporary data. It is not a user study or a claim that every UX problem is resolved.

## Browsing and reading

| Before | After |
| --- | --- |
| Every snapshot replaced the JavaScript list model, including snapshots caused by drafts/settings. This could recreate text and media components even when posts were unchanged. | Feed and discussion models update only when their post data changes. A test verifies that selected text and its component survive a draft refresh; the playback test verifies the player survives and continues playing. |
| Opening a discussion replaced the feed model; going back did not restore its scroll offset. | The feed is retained while reading a thread, and Back restores the offset, query and page. The regression uses 18 temporary threads and checks the restored offset within 3 px. |
| Back unconditionally exited Saved threads. | Back from a discussion retains the Saved context. Back from the Saved feed exits that filter. |
| Empty-state copy could appear during loading; the thread title could briefly say “Thread not found” while a refresh was scheduled. | Empty states wait for the query to finish, and scheduled loading counts as loading for the thread heading. |
| Feed metadata repeated identity hashes, post IDs, timestamps and a separate “Last activity” label. Narrow layouts omitted reply counts. | Feed and latest-reply previews prioritize readable authors and time; technical IDs remain in the discussion. The activity column uses two lines, and narrow rows include reply counts. |
| Search had no dedicated clear control. | Both search fields have a clear action that resets the query and retains input focus. |
| Only mouse navigation offered a direct path back or out of the reply editor. | Standard Back/Alt+Left returns to the feed. Escape collapses the reply editor and persists the draft. Existing Ctrl+F works with all platform standard Find bindings. |

## Layout and composition

| Before | After |
| --- | --- |
| At 950 px, the desktop header clipped the profile control and shortened the New thread label. | The layout switches before the full header stops fitting. Geometry checks cover 400, 950, 1080, 1100, 1440 and 1780 px. The desktop New thread control has a stable width. |
| Font sizes scaled down with window width, even though Qt already handles display scaling. | Text and controls have stable sizes; window width determines layout rather than typography scale. |
| Profile, network and composer dialogs used unrestricted natural height. At 400×540, the profile's final controls were outside the window. | Each dialog is bounded to the available height and has a scrolling body. Its close control remains in the fixed header and has a 40 px target. |
| Composer actions competed for one horizontal row on small screens. | The identity control moves above the action row on narrow layouts. Desktop submission actions remain right-aligned. |
| Title/message prompts existed only as placeholders. | Persistent Title and Message labels remain visible while writing. The message editor height adapts to available space. |
| Submission errors could appear in the page banner behind the modal. | The composer displays errors inside the dialog, preserving the entered text and retry path. |
| “Queue thread” exposed transport terminology as the primary action; the attachment hint always claimed files stayed local. | Primary actions are Create thread/Post reply. Adjacent copy describes offline queueing or local-only attachments, and attachment guidance reflects configured upload availability. Delivery acknowledgement is described as “Sent to network”, not peer receipt. |
| Mouse clicks left keyboard-style focus rectangles on several controls; dropdown options lacked explicit pointer feedback. | Visual focus styling is reserved for keyboard focus, and dropdown options have hand cursors, hover feedback and 40 px rows. |

## Verification

- **23 backend and 31 QML checks pass on Qt 6.9.2**, matching the installed Basecamp runtime.
- The audit found that the old test binaries' stale runtime search path could fall back to system Qt 6.11.2. `scripts/build-native.py` now selects the requested Qt libraries, plugins and QML imports for the test process. The final results above come from a fresh run with Qt 6.9.2 reported by the test runner.
- Added checks cover reading-position restoration, stable text selection during draft refresh, small-dialog scrolling/action reachability, inline errors, search clearing, Escape draft retention, and header geometry. The existing video test now also checks playback through a draft refresh and stopping on navigation.
- Screens were inspected at 1780×800, 1200×800, 950×650 and 400×540, including dark/light feeds and compose/profile dialogs. The small dialog's bottom actions are verified after scrolling, not assumed visible in the initial screenshot.
- Before/after screenshots and test logs are in `artifacts/ux-audit/`. Synthetic content was confined to temporary preview/test databases.
- No benchmark of actual frame time or remote-network latency was performed. This pass does not claim 60 fps or faster transport.

## Remaining UX debt

These are real limitations, not completed features:

1. Quote references are still plain text. Following a quote across pages should become an explicit jump with a return path; that needs a reliable backend lookup rather than guessing from a short hash.
2. Search can match a reply without showing that specific matching passage in the feed. Result excerpts should explain why a discussion matched.
3. The profile still combines basic identity choices with advanced privacy details. It is reachable on small screens now, but information grouping deserves a separate simplification pass.
4. Live changes that actually alter posts still replace the relevant list model. Unchanged snapshots no longer do so. Incremental keyed updates would better preserve selection during genuine incoming activity.
5. These changes have been exercised locally on Linux. Earlier macOS acceptance does not validate this new interaction pass, and screen-reader behavior has not been audited.

The existing monochrome design, discussion layout, SQLite storage, identity keys and delivery semantics are retained. This is a correction to the interaction model and responsive behavior, not a framework migration.
