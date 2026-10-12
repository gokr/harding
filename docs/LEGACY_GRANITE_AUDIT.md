# Legacy Granite branch salvage audit

Reviewed branch `feature/granite-full-compilation`, tip
`ca089cb9d9bfea4b071231ae964a42952bbfd235`. Its four commits are not ancestors of
main or granite-completeness. They must not be described as history-merged.

## Disposition

- `ca089cb`: salvage `Log`, its example and regression tests, and FileStream
  `print:`/`println:` aliases. Adapt logging to a shared implementation: application
  debug/warn remain available in release builds, host logging filters/handlers are
  respected, no duplicate default handler is installed, and fatal only logs.
  Compiled logging uses ordinary runtime dispatch so aliases and registered
  class-side overrides work; do not copy receiver-name-only logging inlining.
- Printable's change from Transcript to stdout is **not applied**. It changes IDE
  output routing and is not necessary for logging. Preserve the original patch
  for a separate decision with Bona work.
- `9126d18`: do not restore obsolete exception/resumption lowering or its examples.
  It contradicts `docs/EXCEPTION_MODEL.md` and the current cleanup/return model.
- `e13e3a6`, `f0a0ef1`: do not wholesale merge. Collection (`reject:`,
  `inject:into:`, `to:do:`), reflection/perform, and remaining-node implementations
  are useful design material for still-open parity work. Their old bodies omit
  scope/capture details corrected on granite-completeness. Direct self calls and
  slot casts need exact receiver/layout guards; do not assume a declaring class
  is the actual runtime receiver class. Claims of complete phases are not
  execution evidence. Build-task/documentation changes are not required for the
  currently documented direct Granite build entry.

## Preservation and cleanup

Before deleting the branch, a verified Git bundle and the four original patches
were saved under `build/legacy-granite-audit/`. The bundle preserves the branch tip
and history; `git bundle verify` passed. Exported files include Log, the old tests,
example, Printable/FileStream sources and codegen. These are disposable local
artifacts, not a tracked release dependency. The archival tag
`archive/granite-full-compilation-ca089cb` retains the complete original source
history in Git, so deleting the branch does not rely on disposable build files.

The obsolete external worktree was already absent from `git worktree list` during
this audit. The branch is deleted only after tested salvage is committed; the
archive tag remains for the deferred collection/reflection and Printable review.

## Stashes (retained, not applied or dropped)

- `4235ef5` (`stash@{0}` at audit time): performance/autostash changes to core types,
  VM activations/frame pools/parser, including deletion of a frame_pool backup.
  Substantial historical runtime work; do not apply blindly to rewritten VM code.
- `051ebdb` (`stash@{1}`): old GTK context-menu/Inspector/Browser work, under the
  historical `lib/harding/gui` layout, plus bridge/gesture/popover changes.
- `fe2a674` (`stash@{2}`): historical Browser/Inspector/Launcher/GTK bridge changes.

Each stash was exported with untracked content to an individual patch in the
same build directory; tree snapshots and an object-ID manifest were also saved.
Preserve the actual stash refs: these involve unrelated Bona/performance work and
require their own content comparison before disposal.
