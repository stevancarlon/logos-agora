# RLN selection repair — 29 October 2026

The installed RLN module 0.12.0 rejected Delivery's startup membership check:
`Permanent: multiple memberships back this scope; use get_memberships / select_membership (kind: ambiguous_selection)`.

Read-only `liblogos_lez_rln_module.get_membership` calls through the running
Basecamp bridge confirmed two different records for the same registry:

- Old membership `69a0fd7f…`: `registered: false`; local cache state `erased`.
- Replacement `833a0e8b…`: `registered: true`, state `active`, leaf 16,
  rate limit 100.

The upstream implementation's `get_membership_state_impl` counts both records
before checking their on-chain state. `select_membership` returns a public view;
it does not persist a selection that fixes this startup check. Source inspected:
[logos-rln-modules at d9f8b3d](https://github.com/logos-co/logos-rln-modules/blob/d9f8b3d5ff93f6fd6fb363f5689098c07e81ac47/logos-rln-module/rust-lib/src/lib.rs).

## Local repair

Stopped Basecamp and acquired the RLN keystore lock. Backed up every keystore
file into a private directory outside the project, then archived the erased
credential out of the active sealed store. The full encrypted original remains
in the backup. The active encrypted entry and the authenticated allocation ledger
were preserved unchanged; no secrets were decrypted, no new membership was
registered, and no transaction was submitted by the repair.

Backup: `~/.local/share/Logos/agora-repair-backups/20261029-rln/` (private).
Do not restore an old allocation ledger over newer allocations; it tracks proof
usage. Any restoration must preserve the current ledger.

After restart, Delivery logged `RLN membership verified ... status=Active`.
This is a local workaround for the installed dependency, not an upstream fix.
If a future renewal or network reset leaves another erased record, the upstream
selection defect may recur. Never archive records based only on an ambiguous
selection error; first verify the live registration state and preserve backups.

## Additional checks

The Qt 6.9.2 build passes 24 backend and 43 QML checks. A short-page footer test
was made independent of posts created by other tests by filtering its own
fixture. Backend validation, delivery acknowledgement matching, retry timeout,
draft preservation, reply transitions, attachment operations and footer layout
checks pass. Tests use temporary databases, not the user's forum database.

## Recurrence guard

Agora now gates outbox claims on the shared node's actual RLN scope and a usable
membership-state response. Failed readiness checks do not consume send attempts;
checks recover automatically and ignore callbacks from an old connection.
No credential mutation or automatic paid registration is performed.

Validation: 24 backend + 47 QML checks passed in
`/tmp/agora-prevention-final-tests.log`. Four isolated Rust candidate-selection
regressions passed. The upstream correction is retained in
`patches/logos-rln-0.12.0-state-candidates.patch`; it is not a rebuilt/installed
RLN dependency. See `patches/README.md` for the validation boundary.

The existing `Thread title test` subsequently hit `Unable to send within retry
time window` despite active membership. Credential recovery alone therefore
does not prove transport delivery; this separate failure remains unresolved.
