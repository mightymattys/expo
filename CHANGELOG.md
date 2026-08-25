# Changelog

expo is a fork of [sous-chef](https://github.com/tomascupr/sous-chef) by Tomas Cupr
(MIT). Versions before 0.6.0 are sous-chef history; the fork begins at 0.6.0.

## 0.14.1 - 2026-08-25

- The `ultra` prohibition gets an invariant. Generalising the rule in 0.14.0 left it
  unguarded: a mutation test deleted the sentence outright and CI stayed green, while
  the comparable backgrounding rule has been asserted since it was written. Two teeth
  now - fire must keep the prohibition, and no skill may wire
  `model_reasoning_effort=ultra` into an actual invocation. Both were mutation-tested
  before shipping, which is how the gap was found in the first place.

## 0.14.0 - 2026-08-20

- The price table had been wrong for two rows, and chasing a new model surfaced it.
  gpt-5.6-terra was listed at a 8.75 blend against an actual 7.00, and gpt-5.6-luna at
  3.50 against an actual 0.70 - overstated five-fold. Verified against
  https://developers.openai.com/api/docs/models. Every receipt that priced a terra or
  luna run carried an inflated worker cost. The error ran against expo's own claim, since
  an overstated worker cost understates the equal-volume delta, so the floor stayed a
  floor - but the figures were wrong, and a table-wide "checked" date had just certified
  them. The header now states which vendor's rows were verified and when, and the file
  says plainly that correcting the table does not retroactively correct receipts already
  written.
- "Daybreak Blue" is an alias, not a new worker. Per
  https://developers.openai.com/api/docs/pricing, `daybreak-blue-latest` and
  `daybreak-red-latest` currently point at `gpt-5.6-sol` and `gpt-5.6-cyber`, so no route
  and no tier row was added - a strength tier and a domain specialisation are different
  axes. What was added is pricing, because a run pinned to an alias records the alias in
  its banner (verified with a real `codex exec` run), and that string reaches the ledger
  and the receipt.
- Alias rows are keyed by the bare slug. The first cut put the dated mapping inside the
  Model cell, which `bench.sh` keys on verbatim - so the row meant to make the banner
  slug priceable rendered it `UNPRICED (excluded from totals)`. The mapping now lives in
  the Source cell, a fixture pins that a bare alias prices, and CI checks that an alias
  row names a target that exists as its own priced row with matching figures.
- A receipt stops diagnosing by guess. It used to read any unpriceable model as evidence
  that the installed plugin was older than the price table. But a receipt holds only the
  banner's model string, so a brand-new alias absent from the table and a user-configured
  model absent from it are the same input. Three states are decidable where two were
  claimed: known alias (priced via its target, and said to be alias-derived), known model,
  and unclassified - which now says so and offers `/expo:mise` as one possible remedy
  rather than as the cause.
- `taste` gains a `--security` pass. The manual "adversarial addendum" becomes a prompt
  of its own that asks for a concrete exploit path - attacker-controlled entry point, each
  step through the actual code, the harmful outcome - and forbids categories of concern it
  cannot walk. Findings land in their own section so `/expo:refire` keeps consuming the
  file unchanged, and a limit sentence is mandatory in both the file and the report: a
  security verdict that reads as an assurance is worse than none. The reviewer stays
  pinned to sol; moving this pass to a specialised model later is one `-c model=` flag.
- The `ultra` prohibition stops naming one model. It applies to any model that offers an
  ultra reasoning level, for the reason it always had - it multiplies token spend by
  design, on a run nobody is watching - so it can no longer be sidestepped by a rename.

## 0.13.0 - 2026-08-17

- The stage prefix on a job dir becomes a rule, and a descriptive label becomes welcome:
  `fire-cenik-XXXXXX`. Measured cause: of 16 runs completed since 0.12.0 only 5 reached
  the ledger, and the 11 that did not (2,512,837 worker tokens, 73% of the volume) were
  ordinary fire runs whose sessions had named the dir after the task and left it outside
  any serve run dir. Sessions clearly want readable job dirs - they took one at the cost
  of breaking the convention - so the convention bends to them, while the prefix the
  sweep reads the stage from stays mandatory. Guessing the stage from directory contents
  was considered and rejected: it cannot separate a fire from a refire, and a guessed
  attribute is the thing this ledger exists not to contain.
- The sweep walks a session scratchpad, not just a serve run dir, descending one level
  into `serve-` dirs so an abandoned serve that never reached its receipt is still
  ledgered. fire, taste and refire now plate through that sweep instead of a single-job
  call, which makes the write self-healing: a run one of them forgot is picked up by the
  next run in the same session, and the `.ledgered` markers keep that idempotent.
- Orchestration windows stay disjoint across both levels. The first cut of this change
  avoided the question by suppressing every measurement in scratchpad mode, which would
  have traded a 73% worker-volume gap for losing all orchestration on the same path.
  Every job in a scratchpad belongs to one session and one transcript, so one
  timestamp-ordered timeline across both levels bounds each job by the next job's start.
  Verified to partition exactly: a bare job at 10:00, a nested one at 10:05 and a bare
  one at 10:15 measured 100 + 50 + 9 against a 159-token unbounded window.
- Each swept job is attributed from its own log banner's `workdir:`, not from whichever
  repo happened to be plating. The plating sweep runs from the repo being plated, so a
  completed-but-unledgered job left in the scratchpad by earlier work elsewhere would
  otherwise be filed under the wrong repo and its marker would make that permanent -
  this repo's own backfill had to derive the repo per job for exactly that reason. An
  explicit `--repo` still wins; a job whose repo cannot be determined is skipped without
  a marker rather than filed wrong.

## 0.12.0 - 2026-08-12

- The ledger write stops depending on the model remembering it. Measured: for five days
  `~/.expo/ledger.jsonl` received zero lines while 34 runs completed carrying 6,670,646
  worker tokens - receipts were written correctly throughout, so only the one remembered
  step fell out. `ledger-append.py` gains a sweep mode (`--run DIR`) that walks a run dir
  and appends a row per stage, and serve runs it immediately before writing the receipt,
  which demonstrably always happens. A `.ledgered` marker per job dir makes the sweep
  idempotent, and both modes now honour it - a repeated `--job` used to append the same
  run twice.
- The sweep survives the untidy run dirs it exists for. A recognised job dir that cannot
  be ledgered is reported and the sweep continues; only a failure to write the ledger
  itself is fatal. Before the fix a single job dir with no log aborted the whole sweep in
  lexical order, so one aborted stage cost every later stage its row.
- Swept orchestration windows cannot overlap. `claude_tokens` measures from a job's start
  to now, which is the job's own window at plating but the whole remaining run at sweep
  time - three stages would have reported the same orchestration two and three times, and
  `tab.sh` sums them. Each swept job is now bounded by the next job's start, ordered by
  the contents of the `started` stamps rather than by directory name, and a job whose
  bound cannot be established omits the field rather than measuring an unbounded window.
  Verified to partition exactly: 140 + 7 against a 147-token unbounded window.
- The sweep refuses simmer dirs and says why: laps are ledgered per lap with `--lap` and
  `--branch`, which a sweep cannot reconstruct, and a lap row without them is counted by
  the tab yet invisible to the receipt that filters on `branch`.
- `check.sh` asserts serve's sweep by behaviour rather than by substring - the complete
  invocation, and that it precedes the receipt instruction, since the placement is the
  whole point.

## 0.11.1 - 2026-08-10

- The running tab divides like by like. It summed worker tokens across every run but
  orchestration only across the runs that had it, folding the rest in as zero - so a
  real ledger reported `5.1x worker:orchestrator` where the paired lines said `2.8x`,
  with 55 of 132 rows contributing 8.87M worker tokens against no denominator. The
  ratio is now computed over rows carrying both numbers and reports
  `split_excludes_jobs` alongside it. The error ran in the plugin's own favour, which
  is the direction that gets believed, and the fixture pinning it asserted the wrong
  answer: two rows, one unpaired, had been pinned at `5x` when like-for-like is `2x`.
- `ledger-append.py` says why it omitted `claude_tokens` instead of omitting it in
  silence. Omitting an unmeasurable number is right; leaving nobody able to tell
  whether `--session` was missing, the started stamp was absent, or the window
  measured nothing is how 42% of a real ledger lost the field with the evidence
  already deleted. One line on stderr, same ledger row, same exit code.
- Simmer's lap row is covered by a test rather than by assumption - `--lap` and
  `--branch` have to survive the write in the order receipts filter on, and no simmer
  had run since the field became mandatory.

## 0.11.0 - 2026-08-06

- Ledger lines are written by a script instead of transcribed by the model. Evidence
  from one day of real runs: two taste runs wrote round invented token counts (98,000
  and 88,000) where their job logs said 203,126 and 170,850; ten lines carried
  estimated `:00`-second timestamps; eleven of twenty-seven lost `claude_tokens`
  because no real start stamp existed; two serves that reached a plated refire wrote no
  receipt at all. `scripts/ledger-append.py` now reads the model from the banner, the
  tokens from the closing summary, the time from the clock, and the orchestration
  window from the job's own `started` stamp - and writes nothing when a run cannot be
  measured. fire, taste, refire and simmer call it, and CI rejects a hand-written
  ledger line anywhere under `skills/`.
- The appender refuses numbers that are not the run's own. A job log echoes its entire
  ticket and prints the worker's final message after the closing summary, so a
  first-match model and a last-match token count can both be supplied by arbitrary
  text - `tokens used` occurs three times in this repo's own fire log. The model is
  read only inside the opening banner, the summary only from the region the final
  message does not occupy, and grouped digits must group in threes, so `1,2` is
  rejected rather than read as `12`. Three spoof fixtures pin all of it, and the
  complete-run fixture pins the real byte shape - a result file with no trailing
  newline, which a fixture that adds one had hidden while every real log went unwritten.
- serve stamps its own start, rewrites `state.md` at every stage transition, and writes
  the receipt before the final report instead of after it - the order that let two
  receipts fall off the end of a turn.
- fire's tier table now says it picks who gets the ticket, never whether to delegate,
  and the `luna` row defers to the delegation floor. A one-word label rename had been
  fired to luna for 32,680 worker tokens plus orchestration; both rules existed
  already and nothing said which one won.

## 0.10.3 - 2026-08-03

- README's inventory named one script while seven shipped, and never mentioned the
  change scan at all - the newest thing a user actually sees. It now lists every script
  and doc that ships, and the honesty section says what the scan does and what it
  refuses to do. CI compares the list against the repo in both directions, so a file
  that ships without a line, or a line without a file, fails the build.

## 0.10.2 - 2026-08-03

- Every diffscan fixture is pinned to its full expected output in a `.expected` file
  beside it, replacing greps for a few lines. The loose form was how an added empty
  file disabled the whole scanner and a corrupt fixture both survived a run; the golden
  form catches a path-parsing regression that the greps passed. CI also rejects a
  fixture with no golden and a golden with no fixture.
- A model the kitchen just ran but cannot price now points at the installed plugin
  rather than at the price table, and `/expo:mise` reports the version it is running as
  and offers `claude plugin update expo@expo`. Evidence: two receipts in a real repo,
  dated 2026-07-24 and 2026-07-27, say the GPT-5.6 tiers are absent from prices.md -
  which was only true of copies predating those rows, so those runs executed a plugin
  several versions behind while its repo was being released from. A stale install is
  silent by nature: the skills still run, they just run the old text.

## 0.10.1 - 2026-08-03

- Receipts carry a `tree:` anchor, and `/expo:receipts` marks any row whose tree has
  since moved. A verdict is only true of the tree it was reached against; without this a
  receipt read weeks later still reads "verified" over code that has changed underneath
  it. Receipts written before the field are marked "tree unknown" rather than implied to
  still hold.
- Every ticket forbids onward delegation, not just the Claude worker routes. A worker
  that inherits a routing policy can otherwise hand the work on again and spend another
  model's quota on a run nobody is watching - which is why the Claude routes already
  carried the line.

## 0.10.0 - 2026-08-03

- `scripts/diffscan.py`: turns a unified diff into counted facts so a reviewer of a big
  diff knows where to look. taste's own docs admit review goes shallow above ~1,500
  changed lines, and 3 of 10 measured serve diffs crossed it, one at 7,130 lines. fire
  runs it at plating before reading the diff line by line. Below `--min-lines` (default
  200) it prints nothing, because under that size the summary is pure overhead.
- Its one product rule: it reports what it counted, never what it means. No adjectives,
  and no nouns that assert a match IS a guard, a dependency or a test.
- Seven blockers were found before this shipped, none by the implementer's own tests:
  an added empty file (no headers, no hunks) made the whole scan exit 0 silently; git
  paths with spaces and C-quoted non-ASCII produced an authoritative `0 files changed`;
  a missing input path and a negative threshold also exited 0; renaming a marketing key
  `"catchphrase"` was reported under `Removed guard lines`; combined `diff --cc` entries
  were unrecognised; non-UTF-8 on stdin bypassed the failure path; and a file name
  containing a newline could print a forged `- 999 files changed, +999/-0` row of its own.
  Paths are now escaped before they reach any output row, operational failures exit
  non-zero with a message, and totals are suppressed rather than shown as zero when
  every entry was skipped.
- Fixtures are generated from real git rather than hand-written - the two defects that
  survived longest both came from fictional fixture text - and CI asserts `git apply
  --stat` accepts every one, with the combined-diff case as a documented exception.

## 0.9.1 - 2026-07-30

- The running tab survives a corrupt ledger line. Found in a real ledger: a token count
  pasted straight from a job log's closing summary keeps its thousands separator, so
  `"tokens":97,188` is invalid JSON - and `jq -s` aborted on it, hiding all 46 other
  runs across four repositories behind a parse error. Bad lines are now skipped and
  reported as `unreadable_lines`, never silently dropped.
- fire's ledger-line schema says the token counts are bare digits and names the
  separator as the trap, since the closing summary is where the number is copied from.

## 0.9.0 - 2026-07-27

- A fourth, deliberately larger benchmark task (three new modules, filters, three
  renderers, an argparse CLI with exit codes; ~300-380 lines across both arms). **The
  delta scales with task size:** at a constant terra tier the ratio goes from a dead
  tie on a small bugfix, to 1.3x on a small feature, to 1.9x on the multi-file one.
  Aggregate over four tasks is ~1.6x, up from ~1.4x over three.
- README now separates the two effects it can actually distinguish - task size at a
  fixed tier, and tier routing - instead of reporting one blended multiple. The
  measured tie on a small bugfix is published as the evidence for the project's own
  "surgical work stays with Claude" rule.
- Task 04 was held at terra to isolate size, though fire's table would arguably route a
  multi-file feature to sol at twice the price. Stated as a limit; not modelled, since
  that run never happened.
- `bench/project` is marked `linguist-vendored` - the fixture is evidence, not the
  product, and the language bar should describe the plugin.

## 0.8.1 - 2026-07-27

- `release.sh` publishes the GitHub release itself. The fork had shipped fifteen
  versions without a single tag because this was a manual step; it is now part of the
  release, and non-fatal, since a missing tag is not worth failing a release that
  already shipped.
- It targets the `origin` remote explicitly rather than gh's `{owner}/{repo}`
  placeholder, which on a fork resolves to the **upstream** repository - verified here,
  where it pointed at `tomascupr/sous-chef`. Aimed at someone else's project, the call
  only failed for lack of permission. CI now rejects the placeholder outright.
- `gh release create` reports a misleading "workflow scope may be required" even with
  a token that has it; the REST call works, so that is what the script uses. An earlier
  session had concluded the user needed to re-authenticate, which was wrong.

## 0.8.0 - 2026-07-27 - the first measured benchmark

- `bench/` holds the evidence: a dependency-free Python fixture both arms edit, three
  task specs written before either arm ran, the measured arms in `results.jsonl`, and
  `RESULTS.md` as a pure render. CI diffs the render against the reporter, so a
  price-table change fails the build until the table is refreshed.
- **The measured result is ~1.4x cheaper in aggregate on three small tasks** - $0.69
  delegated against $1.00 direct - not the 10-20x the upstream benchmark reported on a
  previous model generation. The win is concentrated in the mechanical task routed to
  luna (~2.8x); a small bugfix came out an exact tie. The README now leads with these
  numbers and says plainly that ours are the modest ones.
- Benchmark arms run cold and headless on both sides: `codex exec` against
  `claude -p --output-format json`. A first attempt measured the direct arm inside the
  session that had just authored the fixture and the spec - it read nothing and looked
  ~10x cheaper, measuring warm context rather than delegation. Those numbers were
  discarded and the method now says so.
- `bench.sh` prices each arm's orchestration at the model that actually ran it, via a
  new required `orchestrator` field. Pricing every arm at one reference orchestrator
  overstated a direct arm on a cheaper Claude - on the fixture it reported ~$2.40
  instead of ~$1.20 and inflated the delta from ~$0.17 to ~$1.23, always in
  delegation's favour. A fixture asserts the corrected figures.
- Descriptions in `plugin.json`, `marketplace.json` and on GitHub name the Opus worker;
  the repository carries topics so it can be found.

## 0.7.13 - 2026-07-27

- The changelog stamp moved out of `release.sh` into `scripts/stamp-changelog.py`, so
  CI fixture-tests it the way it already tests the measurement scripts: six cases
  covering a heading with a version and a title, a version alone, a bare heading, a
  title with no version, a version mismatch, and no entry at all. A refusal must leave
  the file byte-identical, which is asserted rather than assumed.
- Verified end to end in a throwaway clone against a scratch origin: a release with no
  entry refuses after the bump, restores both the version and the changelog, and makes
  no commit; a release with an entry lands the dated heading inside the release commit.

## 0.7.12 - 2026-07-27

- `scripts/release.sh` stamps the changelog inside the release commit: the
  `## Unreleased` heading becomes `## <version> - <UTC date>`, keeping any title, and
  a release with no entry - or an entry naming a different version - is refused. Both
  0.7.9 and 0.7.10 shipped still labelled "Unreleased" because this was a manual step.
  A failed stamp restores the changelog alongside the version bump.
- CI asserts every changelog heading carries a date and that at most one Unreleased
  heading exists.

## 0.7.11 - 2026-07-27 - the benchmark harness

- `scripts/bench.sh`: a reporter over a human-recorded JSONL of benchmark arms. Both
  arms are really measured - the delegated arm's worker tokens from its job log plus
  orchestration from `orch-tokens.py`, the direct arm's Claude tokens from the same
  transcript measurement - so the delta is an observed difference, never a modelled
  counterfactual. Prices are parsed from `prices.md`; an unpriced model is reported
  loudly instead of guessed; an unverified arm never counts as a win.
- `docs/benchmark.md`: the method, the JSONL schema, and what the numbers are not.
  The delta is scoped to the measured task set with its n, explicitly not a bound or
  a general multiple - the receipts' "floor" argument does not transfer to a
  comparison where both arms actually ran.
- README's savings FAQ now points at this project's own methodology; the upstream
  three-task benchmark stays cited but labelled as a previous model generation.
- Cross-review caught three defects in the first cut: per-arm totals summed a
  different row set than the delta (a mixed ledger reported delegated $3.53 against
  direct $2.40 while claiming delegation was $1.23 lower), direct arms accepted
  nonzero `worker_tokens` in a direction that flattered delegation, and
  caller-relative ledger paths resolved against the repo root. Rounding is now applied
  once per row, so no two lines of a report can disagree about the same figure.

## 0.7.10 - 2026-07-27

- Logo: a `/e` terminal monogram (the slash is how the plugin is actually invoked),
  shipped as outlined SVG in a dark and a light variant plus PNG renders; replaces
  the emoji in the README hero.

## 0.7.9 - 2026-07-27

- Added Claude Opus 5 as the premium keyless Claude subscription worker
  (`--with opus`) alongside the cheap Sonnet fallback, with route pricing checks and
  receipt honesty for the Fable-priced orchestration reference.

## 0.7.8 - 2026-07-24

- This changelog.

## 0.7.7 - 2026-07-24 - simmer hardened by its first dogfood

Findings came from a real simmer run executed while a second Claude session was
actively editing the same worktree - the exact environment the old text silently
assumed away.

- Shared-worktree safety: dirty tree recommends `git worktree` isolation for the
  loop; declining records `shared_tree: yes` and makes staging/judging discipline
  mandatory.
- Checkpoints stage only lap-authorized paths that were clean at lap start; a path
  carrying another session's hunks stops the checkpoint - never a blended commit.
- The lap judge classifies concurrent edits (fire's rule); foreign paths never
  enter verdicts or receipts. Receipt diffs count checkpoint commits only.
- Branch-scoped loop state with a collision-safe slug (slash replacement + 6-char
  hash); resume validates the recorded base is an ancestor of HEAD, so a
  recreated branch cannot inherit a stale loop.
- Worker routing for loops: `worker:` per contract (codex default,
  `--with sonnet`); a quiet errors-only Sonnet log is never read as a dead
  worker - no-result + quiet log = indeterminate, surfaced, never auto-relaunched.
- Codex lap ledger lines carry `branch` for cross-loop attribution.

## 0.7.6 - 2026-07-24 - the measurement layer becomes executable

- `scripts/orch-tokens.py`: single implementation of transcript-based
  orchestration measurement (session-id located exactly, one-match-only,
  datetime window, invalid in-window usage aborts the whole window - no partial
  totals; no output means drop the line).
- `scripts/tab.sh`: the running tab from `~/.expo/ledger.jsonl`.
- First behavior tests in CI: hermetic fixture transcripts assert exact sums,
  boundary inclusivity, fractional-second regression, usage-null and
  ambiguous-match aborts; rc checked on every invocation so a crash cannot pass
  as an empty window.

## 0.7.5 - 2026-07-24 - honest per-run savings + a release gate

- Receipts carry an equal-volume delta (floor): this run's combined token volume
  priced at Fable list minus the measured all-in - fully measured, never
  presented as a bound on actual savings (the counterfactual is not run). A CI
  invariant rejects any unqualified savings wording, all word forms,
  case-insensitive.
- `scripts/release.sh`: refuses no-op releases (same-version installer updates
  are silently ignored - hit twice before this existed), fetches and requires
  not-behind, full check before bump, byte-identical bump restore on pre-commit
  failure, resume paths for failed push and failed refresh, user-scope-aware
  verification that the installed copy matches HEAD.

## 0.7.4 - 2026-07-24 - README redesign; GPT-5.5 retired

- README rebuilt: centered hero with the flow diagram and badges, quickstart
  first, command and tier tables, collapsible FAQ.
- GPT-5.5 removed from every operative surface (prices, recommendations,
  receipts machinery); the kitchen runs GPT-5.6 tiers and Sonnet 5 only.

## 0.7.1-0.7.3 - 2026-07-23/24 - cross-review fixes on the 0.7.0 features

- taste pins `-c model=gpt-5.6-sol` - "reviews stay on sol" became a mechanism,
  not a hope about the user's config.
- Orchestration windows split per job (`$JOB/started`) vs per run (`started:`),
  eliminating a 2-3x double-count in the running tab; measurement snippet
  hardened (datetime parsing, empty-window contract).
- simmer picks its GPT-5.6 tier once per loop; mixed-tier receipts price each
  job at its own model's blend.
- Pricing freshness watchdog: a stale as-of date warns then fails CI; an expired
  "through YYYY-MM-DD" price note fails.
- Flow diagram artwork; docs sync across templates and README.

## 0.7.0 - 2026-07-23 - tier routing + measured orchestration

- Model-tier routing: fire picks gpt-5.6-sol/terra/luna by task shape
  (`--tier` overrides); serve threads the tier to refire; the tier rides the
  invocation as `-c` flags.
- Orchestration cost measured from the session transcript instead of the
  historical "~5-7k per run" estimate.

## 0.6.0 - 2026-07-23 - the fork

- Renamed sous-chef -> expo; GLM routes removed (Codex + Sonnet only); folded in
  the fixes that were pending upstream (self-check blind spots, stale claims,
  GPT-5.6 pricing); refire gained worker routing. Full attribution retained.
