# RLN state-selection correction

`logos-rln-0.12.0-state-candidates.patch` targets
[logos-rln-modules d9f8b3d5ff93f6fd6fb363f5689098c07e81ac47](https://github.com/logos-co/logos-rln-modules/tree/d9f8b3d5ff93f6fd6fb363f5689098c07e81ac47).

The startup membership-state query counts erased legacy records alongside a
usable replacement and returns `ambiguous_selection`. The patch prefers usable
candidates after existing scope/quarantine filtering, matching proof selection.
It retains ambiguity for multiple usable credentials and retains diagnostics
when none are usable. The chosen record still undergoes the existing live
registry read. No keys, allocation ledgers, or credential files are modified.

Apply in that dependency checkout with `git apply` and rebuild/package using
its documented toolchain. This patch is **not installed in the shared Basecamp
RLN binary**. Agora's publishing-readiness guard is independent of it and safely
pauses its outbox on an ambiguous or otherwise unusable credential.

The four pure selection regressions can run without the host SDK:

```sh
rustc --test logos-rln-module/rust-lib/src/state_candidates.rs -o /tmp/rln-selection-tests
/tmp/rln-selection-tests
```

These passed locally; they do not replace the dependency's full build,
registry integration tests, or release validation. The full module build needs
the upstream generated provider, SDK, module builder, and protocol libraries.
