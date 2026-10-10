# Agora interface — approved modern imageboard

The authoritative reference is `design/agora/concepts/c-imageboard.png`, explicitly selected by the user’s screenshot. The earlier sidebar implementation was a mistaken interpretation and is superseded.

The native layout has no sidebar: serif Agora wordmark, inline /all/ and board links, compact search/theme/profile controls, followed by a right-aligned sort selector and New thread; a board selector appears only on narrow windows where the header links are hidden. The feed uses warm ivory Liberation Serif titles, plain-text opening excerpts, muted identity/post references and a real latest-reply preview with a thin vertical rule. Reply counts and activity appear on the right alongside a functional Reply button. Reply opens the matching thread and focuses its composer.

Adwaita Sans and Liberation Serif are bundled with their upstream licenses. Dark remains the default; a light palette and compact navigation are supported. Saved and network controls remain in the footer. Pending/error states and signing-key fingerprints remain truthful. Protocol v1 supports text, so sample photos in the generated image are not copied into real posts. No illustrative community content or Connected state is inserted into the user database.

Verification covers actual header links, filters, Saved, sorting, direct feed replies and composer focus, search, narrow bounds, avatars, drafts and delivery callbacks. Desktop and compact native renders use isolated Example content. Build with Qt 6.9.2 and verify the package with official lgx before installing in Basecamp.
