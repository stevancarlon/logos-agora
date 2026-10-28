# Agora — LP-0026 submission preparation

**Status: not ready to submit.** Authentic community conversations and the narrated
end-to-end walkthrough are required by the prize. They must be linked below before
submission; synthetic examples and automated tests do not satisfy adoption.

## Project

Agora is a native, local-first public forum for Logos Basecamp, built with C++17,
Qt/QML and SQLite. It supports discussion boards, threads, replies, quotes,
alias/UID/anonymous display, multiple identities and optional identity rotation.
Delivery carries signed messages and Store history; Logos Storage carries shared
images, videos and PDFs. There is no centralized application backend.

- Repository: https://github.com/stevancarlon/logos-agora
- Installation: [INSTALL.md](../INSTALL.md)
- Community catalog: https://raw.githubusercontent.com/stevancarlon/logos-agora/main/logos-repo.json
- FURPS assessment: [FURPS.md](FURPS.md)
- Current network setup: [NETWORK.md](NETWORK.md)
- License: MIT OR Apache-2.0 for original code; bundled assets retain their notices.

## Required evidence

| Requirement | Current evidence / remaining action |
| --- | --- |
| Native Basecamp GUI and local build | Source in `native/`; [build instructions](GUIDE.md#build-and-test) |
| Prebuilt catalog package | Published desktop alpha and community catalog; final candidate update in progress |
| Accounts, threads/replies and identity choices | Native backend and QML workflow tests; show each in the recording |
| Logos integration | [Public Delivery receipt](evidence/public-delivery-20261028.json); [Storage scope](STORAGE.md) |
| Failed sends persist; missed messages recover | Private relay/restart/Store acceptance checks; [reproduction](ACCEPTANCE.md) |
| Bounded network traffic | One in-flight send, paced retries, bounded history queries; [protocol](PROTOCOL.md) |
| Green default-branch CI | Link the passing runs for the final source revision |
| End-to-end instructions | [Installation](../INSTALL.md), [usage](GUIDE.md), [network](NETWORK.md) |
| Narrated demonstration | **Pending recording and upload**; [recording outline](DEMO.md) |
| Realistic topics and organic conversations | **Pending genuine participation**; no fabricated accounts or usage counts |

## Community invitation

> I'm building Agora, a native, local-first forum for Logos Basecamp. I'd love a
> few people to try it and have a real conversation about what they're building,
> privacy tools, or improving the forum. It's an early alpha; installation and
> network setup are documented in the repo. Feedback and bug reports are welcome.
>
> https://github.com/stevancarlon/logos-agora

Before submitting, add the demo URL, the final release and CI URLs, and links or
consented captures of genuine discussions. Use the prize's current solution
submission template and retain the stated verification limits.
