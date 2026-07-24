# Receipt template - what serve and simmer write

At the end of every serve and simmer - any terminal outcome, verified or halted
or budget spent - write one file to `.expo/receipts/` in the repo root:

- Filename - `$(date -u +%Y%m%dT%H%M%SZ).md`. `mkdir -p .expo/receipts`
  first, and add `.expo/` to `$(git rev-parse --git-path info/exclude)` if
  it isn't there.
- Every number is measured or carries its method. Worker tokens come from each
  job.log closing "tokens used" summary (uncached input + output, no split) -
  sum across the run's jobs, failed runs included; a log with no token summary
  contributes nothing. Orchestration (Claude-side) tokens are measured from the
  session transcript per [orchestration-tokens.md](orchestration-tokens.md) - not
  the old 5-7k estimate. Dollar figures come from the [prices.md](prices.md)
  blends and get a `~`. A number you don't have is a line you drop - never a
  guess.

```markdown
# serve: <task one-liner>

- when: <UTC ISO-8601> · wallclock <Xm> (now minus state.md's `started:`)
- worker: <model(s) from the log banners>, <N> runs, <total>k tokens
  (a run that mixed tiers/models - e.g. a terra fire and a sol taste - prices each
  job at its own banner model's blend before summing, and lists per-model subtotals:
  `terra <a>k ~$<b> · sol <c>k ~$<d>` - one blend applied to combined tokens would
  misprice both)
- cost: ~$<X> API-list terms (per-model blends per prices.md; subscription quota =
  $0 marginal; a banner model missing from prices.md prices as unknown - warn
  loudly and drop its dollar figure rather than guessing a blend)
- orchestration: <M>k Claude tokens, ~$<O> API-list (measured from the session
  transcript since the RUN's `started:` per orchestration-tokens.md - the run-level
  window, not a sum of the per-job ledger windows; drop this line if the snippet
  printed nothing)
- this run's split: ~$<X> worker + ~$<O> orchestration = ~$<X+O> API-list, all
  measured (no counterfactual)
- same tokens at Claude Fable 5 list: ~$<Y> (what the run's combined token volume
  would cost at the orchestrator's blend - a price comparison at equal volume, not
  a claim about what a Claude-only run would have spent)
- diff: <files> files, +<ins>/-<del> (vs the run's baseline)
- verdict: verified | findings unresolved - <which> | halted - <why>

> expo shipped <task> for ~$<X+O> all-in (API-list terms, measured both sides:
> worker + orchestration). github.com/mightymattys/expo
```

The quoted block is the shareable summary, and only a verified run gets one - a
halted or budget-spent receipt keeps its numbers and skips the brag. Keep it
under 280 characters and paste-ready. Every figure in it is this run's own
measurement - never compute or quote a cross-model savings multiple (the measured
counterfactual isn't run, and a same-token comparison is a price ratio, not a
savings claim). The task line
ships verbatim inside it - client names and private context go with it - so
surface the post for the user to paste; never post anything yourself.

For a simmer, swap the header (`# simmer:`), count laps as runs, and let the
verdict carry the loop outcome (passed lap N of M | budget spent | no progress).
Simmer's lap verdict lines drop job paths, so take worker tokens from this run's
per-lap ledger lines (`~/.expo/ledger.jsonl`, the `"skill":"simmer"`
entries for this repo's laps), the diff from `git diff <loop.md base>..HEAD`
plus the working tree, and wallclock from loop.md's `started:`.
