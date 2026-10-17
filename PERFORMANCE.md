# Local performance evidence — 2026-10-16

Bounded investigation from 1f3b7f3 (network source 7bc8811). Measurements use an
isolated Debug app on an arm64 Mac/iPhone 17 Simulator, iOS 26.4/Xcode 26.4. Fixtures,
traces, query plans and images remain private. These are small local samples,
not production latency, throughput, physical-device memory or reliable p99.
First observed is separate from warm; no OS disk-cache purge was performed.

## Workload and load boundary

TEST ONLY season: 30 games,15 players / two historical labels each, four independent
datasets per game, three versions per dataset,60 possessions/team/version and 240 retained
correction requests. This crosses100-row pagination while preserving missing and
explicit-zero inputs. Native loading serves one game's12 versions/eight requests.
Actual PostgreSQL adds this season to a retained synthetic recovery baseline:
31 games, 16 players, 31 labels, 121 datasets, 362 versions, 240 requests, 121 outbox rows.
These are diagnostic sizes, never actual team statistics.

Owner load sequence: game → current team authority → roster → historical labels →
versions → dataset pointers → correction requests → preferences → owner outbox.
Page reads depend on their prior page; outbox requires confirmed owner authority.
This is a fixed sequence, not a demonstrated per-row N+1 pattern. Snapshot validation
and publication remain all-or-nothing; no cache, concurrency rewrite or automatic
mutation retry was added.

## Repairs and comparison

- **Game-scoped corrections:** the old read downloaded all 240 team requests and
  discarded 232 locally. The new named source-version relationship filters by game
  under the same RLS/team predicate. Pagination and final loaded-version filtering
  remain. Actual isolated PostgREST 16.4 returned the same eight relevant records;
  anonymous reads were denied. Exact correction-response bytes fell 99,114→3,790;
  correction requests fell 3→1, whole snapshot 11→9. No new index/migration.
- **Concurrent file iteration:** approachable concurrency let asynchronous byte
  iteration inherit the UI executor. An executor-only experiment isolated the
  slowdown. `@concurrent` moves that loop to the concurrent executor; stream/body
  limits, cancellation, hash checks and single-send delivery remain unchanged.
  Comparable 2 ms RSS-sampled 1 MiB baseline:3 completed samples, first 17.982s,
  two-warm median 17.818s. Same instrumentation after:4 samples, first 0.575s,
  three-warm median 0.330s. Uninstrumented repaired 1 MiB first 0.116s/warm 0.102s;
  10 MiB first 1.140s/warm 1.197s (four each). Synthetic HTTP byte pipeline, not
  valid-video decoding or hosted transport. An earlier interrupted baseline is
  retained separately and is not a passing suite.

Interleaved original/current loaders in one process, six samples per variant and
condition (first plus five warm):

| Native synthetic body/read condition | Before | After |
| --- | --- | --- |
| Whole-snapshot requests/body bytes |11 /174,985B |9 /100,279B |
| Immediate responses, first / warm median |479.5 /109.7ms |418.7 /98.5ms |
| Simulated 40 ms delay per response, first / warm median |546.2 /559.0ms |479.1 /433.5ms |

Delay is a deterministic test response delay, not measured internet RTT or packet
loss. Other batches varied substantially (initial immediate warm 33 ms; later 160 ms).
The robust improvement is less data/two fewer requests, not a guaranteed latency
percentage. Exact actual API body sizes above are separate from these test replies.

## Query and device observations

Actual PostgreSQL 17.11: ten query shapes×six EXPLAIN ANALYZE/BUFFERS samples under
authenticated-owner RLS using synthetic Auth stand-ins. Existing team/game index
serves versions; primary/unique indexes cover identities/dataset pairs. Small roster
and request tables can use sequential scans. Warm medians: game0.085ms, roster1.161ms,
history2.227ms, versions1.413ms, datasets0.301ms, outbox0.597ms; correction pages
49.2–49.7ms each. Game filtering still scans requests under RLS; it removes repeated
pages/wire data, not all policy work. Actual Data API interleaved six-run totals:
old three-page first581ms/warm median429ms; new first 1,120ms/warm median228ms.
The first new read was slower; host variability precludes a universal latency claim.
Actual API plans and SQL-only plans are separate; SQL JSON sizes are not wire bytes.
No speculative index or authorization shortcut was justified.

Local saved stores:30 games / 450 box scores / 3,600 possessions / 450 player totals,
about 652 KB combined. Six reads: first 18.24ms/warm median18.16ms; box-score atomic
save/update first 2.15ms/warm median1.98ms.1,500 count validations: first 1.01ms/warm
median 0.76ms. A later batch measured40–46ms loads and4–8ms saves: local variability,
not a measured storage regression or rendered keystroke latency. No storage rewrite.

Actual process-launch metric: five measured launches, seeded games visible each
run, first-responsive-frame values3.781/2.573/18.019/17.654/9.190s (mean10.243s,
relative standard deviation64.3%). XCTest passed without a performance baseline.
This is a highly variable Debug Simulator observation, not a stable startup SLO,
disk-cold result or proof of an app-side cause. Saved-data reads above are separate;
no speculative startup repair was made.

Photo: actual Vision on a synthetic 6M-pixel printed sheet,144,509-byte JPEG.
Four samples: first 2.065s/three-warm median 0.672s; a later batch1.566–1.892s.
Recognition already runs in a detached worker.10ms main-queue heartbeat maximum
116ms first/11ms warm in the initial batch; these are gaps, not rendered-frame
measurements. Sampled process RSS306→447MiB first and warm peaks453–455MiB includes
frameworks/caches/fixture image; it is not isolated allocation or physical-device
peak. No leak or OCR-memory repair was established.

Separate 2 ms RSS sampling changes timing: repaired 1 MiB four runs0.323–0.575s,
10 MiB four runs2.246–2.427s. Corresponding before→sampled peak RSS differences
were1.4–7.8MiB and5.8–22.7MiB. No exact allocation/peak guarantee follows.
Synchronous10 MiB retention store/read initially14.5/5.3ms, five-warm medians6.5/6.4ms;
a later batch store17–28ms/read13–16ms. Those observations did not justify changing
retention architecture. Short operations missed by sampling are unavailable, not
zero memory; cumulative RSS without autorelease draining is not a leak diagnosis.

## Regression and remaining limits

34 affected native regressions passed: 24 statistics / 10 private-file. New cases cover
game-filtered corrections,101 relevant requests across pages, exact1/10 MiB bytes
and retained reuse without duplicate delivery. Private measurement checks remain
separate from these committed regressions. Independent Standards/Spec reviews found
no actionable source findings. Existing no-deploy CI execution is recorded in TESTING.md.

Hosted timings/Query plans, real forms, release-build/physical-device performance,
iOS 26.0 and realistic lossy networks remain unverified. No provider activation,
original upload, Auth configuration change, migration 14 activation or delivery enablement.
Auth's failed immediate lockout and passed additional-grace rejection remain distinct
in NETWORK.md. Actual landscape, iPad Reduce Motion traversal and actual VoiceOver
stay open; this pass did not retry them. Broader monitoring/export scheduling and
release work remain separate.
