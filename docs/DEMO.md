# Agora narrated walkthrough

Record the actual application and terminal output. Use a separate demo profile
for staged examples and label it clearly. Do not present staged discussions as
organic use. Keep private keys, wallet files and personal paths out of the video.

Target length: 3–5 minutes. Confirm the final release before recording installation.

| Time | Show | Suggested narration |
| --- | --- | --- |
| 0:00 | Agora inside Basecamp | “Agora is a native, local-first public forum for Logos Basecamp. Its C++ backend stores drafts, identities and discussions in SQLite.” |
| 0:20 | Release download, checksum verification, companion installer and catalog | “Install the matching desktop kit and media runtime, then add the community catalog in Basecamp. The alpha package is unsigned; the installation guide lists platform requirements.” |
| 0:55 | Feed, board navigation, search, thread and quote | “Boards organize discussions. We can create a topic, reply, quote another post, search the local archive and save a thread.” |
| 1:35 | Profile and identity choices | “Posts can show an alias or UID, or omit a stable identity. Identity rotation is available. These display choices are not a network-anonymity guarantee.” |
| 2:00 | Offline post, restart, reconnect and sent state | “A failed send keeps the text and message ID locally. Retry reuses that ID. Sent means Delivery acknowledged the transport; receipt is checked separately.” |
| 2:40 | Independent receiver and Store recovery evidence | “This public welcome thread arrived in an independent Basecamp profile with the same envelope hash. This check used one computer. Private relay tests also verify restart retry and missed-message recovery through Store.” |
| 3:10 | Image, inline video, PDF and Storage configuration | “Attachments use Logos Storage. Readers fetch explicitly, and Agora checks the signed file size, hash and type. Without a configured node, attachments remain local.” |
| 3:45 | CI, FURPS, genuine discussion evidence and limitations | “The repository includes build instructions, CI, protocol documentation and a FURPS assessment. Here are the verified results and the remaining alpha limitations.” |

Show real pending/failure behavior if the testnet is unavailable. Do not replace
it with a simulated success state. Include authentic discussion evidence only
once participants have actually used the forum and consented to identifiable
material appearing in the submission.
