# Rough price table - API list; every row verified 2026-09-04

For receipt estimates only. Job logs report the worker's uncached input + output
combined, with no in/out split, so receipts price tokens at the 50/50 blend
column unless a real split is known. Every dollar figure derived from this table
carries a `~`. Update the numbers and the vendor-specific verification date together
when list prices move - the as-of date is part of the receipt's honesty. Receipts
already written carry whatever figures were current when they were written; correcting
this table does not retroactively correct them.

Every OpenAI figure here is the **short-context** rate. The vendor's table also carries
long-context columns - verbatim, `gpt-5.6-sol | $4.00 | ... | $8.00 | ... | $30.00` - so a
run billed at long context costs roughly twice what this table computes, and the page
defines no token threshold at which it starts. Two consequences worth stating plainly.
A receipt cannot tell which rate a run was billed at: the ledger stores a total token
count, and the job log's banner does not say. And unlike every other error this table has
had, this one runs in expo's favour - an understated worker cost overstates the
equal-volume delta - so it is named here rather than left to be discovered.

| Model | In $/MTok | Out $/MTok | 50/50 blend $/MTok | Source |
|---|---|---|---|---|
| gpt-5.6-sol | 4.00 | 20.00 | 12.00 | https://developers.openai.com/api/docs/models; alias mapping: https://developers.openai.com/api/docs/pricing |
| gpt-daybreak-blue-latest | 4.00 | 20.00 | 12.00 | https://developers.openai.com/api/docs/pricing - alias of gpt-5.6-sol as of 2026-08-20 |
| gpt-6-astra | 10.00 | 50.00 | 30.00 | https://developers.openai.com/api/docs/pricing - short-context rates; rolling out to Trusted Access enterprises, not yet in the Codex model list |
| gpt-5.6-cyber | 12.50 | 75.00 | 43.75 | https://developers.openai.com/api/docs/pricing |
| gpt-daybreak-red-latest | 12.50 | 75.00 | 43.75 | https://developers.openai.com/api/docs/pricing - alias of gpt-5.6-cyber as of 2026-08-20 |
| gpt-5.6-terra | 2.00 | 12.00 | 7.00 | https://developers.openai.com/api/docs/models |
| gpt-5.6-luna | 0.20 | 1.20 | 0.70 | https://developers.openai.com/api/docs/models |
| claude-fable-5 | 10.00 | 50.00 | 30.00 | https://platform.claude.com/docs/en/about-claude/pricing |
| claude-fable-5-1 | 10.00 | 50.00 | 30.00 | https://platform.claude.com/docs/en/about-claude/pricing - same blend as Fable 5; its cheaper cache-read multiplier does not affect a 50/50 in/out blend |
| claude-sonnet-5 | 2.00 | 10.00 | 6.00 | https://platform.claude.com/docs/en/about-claude/pricing - the launch introductory 2.00/10.00 became the standard price; the scheduled 3.00/15.00 increase was cancelled |
| claude-opus-5 | 5.00 | 25.00 | 15.00 | https://platform.claude.com/docs/en/about-claude/pricing |

Only models the kitchen actually runs, plus known banner aliases whose logged names
need receipt pricing, belong in this table (GPT-5.6 tiers as workers, Sonnet 5 and
Opus 5 as Claude subscription workers, Fable 5 for pricing orchestration tokens) - a
retired generation is a stale row waiting to misprice something. An alias row's Source
is a dated mapping, not a claim that the alias is a fixed model: it can be repointed.
Subscription workers (ChatGPT plan, Claude plan) have $0 marginal cost - receipts
therefore always say "API-list terms", never "you paid". The only derived figure
a receipt may carry is the measured equal-volume delta, labeled "(floor)", dollars
only, computed purely from measured tokens and this table's blends - never a
cross-model multiple or a claim presented as a bound.
