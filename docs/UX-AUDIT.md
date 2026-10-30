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

## 28 October — discussion screen and reply flow

The later screen review found a different problem: a wide layout split the reading
column from its actions, while Reply and Quote competed as similar-looking entry
points. Moving the Reply button alone did not correct that hierarchy.

| Before | After |
| --- | --- |
| Thread text occupied one side of a wide canvas while Save, time and Quote sat far away. | The discussion is centered in an 880 px reading column; title, post text and composer share an edge. Save and Quote sit beneath their post. The global header and corner Logos mark retain their page-level positions. |
| Dense author/OP/hash metadata dominated the beginning of each post. | A quiet author initial, readable name and adjacent time identify the post. Fingerprint, post ID and transport status remain in the author tooltip and accessibility description. |
| Body text was 15 px, beneath a bold heading. | A regular serif heading and 16 px body create the reading hierarchy. Secondary actions and metadata use muted monochrome tones. |
| Positive transport status repeated below every post. | Sent/received details move to the author tooltip; queued, failed, sending and local-only states remain visible. Transport semantics are unchanged. |
| A separate Reply/Continue draft action hid the editor. | The reply field is directly editable and shows saved text. Focusing it reveals attachments, identity and submission. Quote inserts a quotation into that same editor. |
| Quote, Save and reply actions competed visually. | Quote, Save, attachment and identity controls are secondary; Post reply is the only filled primary action in the thread. Keyboard focus remains visible. |
| A growing draft could exceed its editing area. | The text editor scrolls independently within a bounded height. Minimize/Escape saves text, and returning to the discussion displays the draft. |

Verification: **24 backend and 34 QML tests pass on Qt 6.9.2**. The new regression
checks shared column alignment, a visible inline composer, draft continuity and
submit-button reachability at 400×540. Existing tests cover quote insertion,
selection surviving snapshots, attachment/media behavior, and a new reply on a
later page of a 55-reply discussion. Dark/light desktop and narrow screenshots
were inspected using isolated preview data; no real community content was seeded.
This is an implemented design iteration, not a claim of user-study validation.

## 28 October — approved compact dock and expanded composer

This supersedes the inline-composer iteration above. The implementation follows
the approved C PNGs in design/proposals/thread-reply-2026-10-28/.

| Before | After |
| --- | --- |
| Save and Quote remained under posts alongside an always-visible editor. | Both post actions are removed. A centered, 400 px maximum reply dock is the single thread reply entry point. |
| Draft entry competed with the post body. | Reply opens a rounded, bounded composer at the bottom, with the reading viewport reserved above it. It focuses a plain reply; it never inserts a quotation automatically. |
| Minimize was a text action and saved text remained on display. | A minus icon and Escape collapse the editor, preserving text and attachments. The dock offers Continue reply, and keyboard focus returns to that control. |
| Identity, attachment hints and status text competed in one row. | Replying as appears at the top; Attach and the draft indicator sit below the editor, with Post reply as the sole primary action. Selected files have removable chips; local-only and length-limit information appears when relevant. |
| Draft persistence had no visible acknowledgement. | Draft saved appears only after both text and attachment draft writes succeed. A failed write keeps the draft and reports the failure. |
| The fixed heading consumed reading space on small windows. | The heading scrolls with the posts; responsive editor height keeps attachment and submission actions reachable. The desktop serif heading is 38 px and body text is 18 px, with smaller narrow-screen sizes. |
| Controls used the generic button treatment. | Rounded dock/composer surfaces, dedicated attach/minus icons, 40–44 px hit areas, hand cursors, keyboard focus and a brief composer fade follow the selected preview. |

Verification uses isolated test databases: 24 backend and 36 QML checks on
Qt 6.9.2, including opening/focusing/minimizing the dock, keyboard reopening,
plain reply insertion, draft failure/recovery, attachment removal, identity access,
successful local submission, and 400×540 action bounds. Desktop dark/light and
narrow previews were visually inspected. These changes do not alter Delivery
acknowledgement semantics or imply network receipt.

## 28 October — reply shortcut and publication status

| Before | After |
| --- | --- |
| Reply submission required clicking Post reply. | Ctrl+Enter in the editor uses the same validated submission path, including numpad Enter. Ordinary Enter inserts a line break. Empty, oversized, busy, unfocused and repeated key events do not submit. |
| Pending publication appeared as metadata text or a line below the post; confirmation had no persistent visual marker. | Small monochrome icons sit beside timestamps in threads, the feed and reply previews: clock for queued, animated arc for sending, one check for Delivery-confirmed sends, warning for retry pending, and device for local-only posts. Hover text and accessible names explain each state. Incoming posts do not show an outgoing-send marker. |

The check follows the existing persisted sent state, which requires a matching
Delivery messageSent event. It is a transport acknowledgement, not an all-peer
receipt or read receipt. Backend protocol and retry behavior are unchanged.
Qt 6.9.2 checks include invalid/unfocused shortcut handling, ordinary newlines,
numpad submission, queued-to-sending-to-confirmed UI transitions, rejection of an
unrelated acknowledgement, and failure/local-only indicators. Preview content
was confined to an isolated temporary database.
