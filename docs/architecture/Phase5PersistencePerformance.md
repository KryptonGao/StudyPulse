# Phase 5 persistence performance

## Scope and baseline

The audit found that the high-frequency grade, mistake, exam, and task
repositories were the material hotspots:

- Each repository owned a MainActor `ModelContext` and performed ID fetch,
  mutation, and `save()` from MainActor.
- Startup created independent detached tasks and contexts, then awaited every
  repository serially.
- Deletes materialized every record before deleting it.
- Every phase switch scanned each complete snapshot array, and phase activation
  could trigger the same recomputation twice.

Lower-frequency profile, subject, routine, diary, coach, and simulation stores
were intentionally left unchanged in this phase. The benchmark did not justify
expanding the migration into unrelated storage or UI work.

Measurements below were captured on 2026-07-24 with the iPhone 17 / iOS 26.5
simulator in Debug. The test uses an in-memory SwiftData store containing 5,000
grades and 5,000 mistakes. The legacy harness uses the former full
`fetch → toSnapshot → Array.filter` path on MainActor. The new harness uses the
shared `@ModelActor`, 500-record pages, immutable Sendable snapshots, and phase
indexes. Resident memory is sampled with `mach_task_basic_info`.

- Legacy startup materialization: 245.4 ms; resident delta 13,041,664 bytes.
- ModelActor startup materialization: 243.1 ms; resident delta 10,043,392 bytes.
- Legacy 200 phase switches: 387.7 ms.
- Indexed 200 phase switches, including index construction: 7.9 ms.

Startup wall time is effectively unchanged (0.9% faster), while observed
resident growth is 23.0% lower. Phase switching is 49.2× faster. This is why the
implementation keeps paged actor reads and phase indexes, but does not add more
storage restructuring.

## Instruments signposts

The `Persistence` signpost category contains:

- `RepositoryContainer.asyncInit`
- `loadHighFrequencySnapshots`
- `insertGrades`, `insertMistakes`, `insertExams`, and `insertTasks`
- `deleteAllGrades`, `deleteAllMistakes`, `deleteAllExams`, and `deleteAllTasks`

The `PhaseFiltering` category contains `recomputeAll`.

These intervals can be inspected with Instruments Points of Interest alongside
Time Profiler and Allocations. They delimit actor work from MainActor snapshot
publication and make regressions visible without enabling verbose application
logging.

## Regression coverage

`PersistenceExecutorTests` covers:

- ten concurrent writers plus concurrent paged readers;
- cancellation without partial repository publication;
- 2,000-record batch import and bulk deletion;
- 5,000 grades plus 5,000 mistakes startup, memory, and filtering.

The performance test prints `PHASE5_BASELINE`, `PHASE5_METRIC`, and
`PHASE5_BATCH` records so CI results retain the raw measurements.
