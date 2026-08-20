# Rough price table - API list; OpenAI rows verified 2026-08-20

For receipt estimates only. Job logs report the worker's uncached input + output
combined, with no in/out split, so receipts price tokens at the 50/50 blend
column unless a real split is known. Every dollar figure derived from this table
carries a `~`. Update the numbers and the vendor-specific verification date together
when list prices move - the as-of date is part of the receipt's honesty. Receipts
already written carry whatever figures were current when they were written; correcting
this table does not retroactively correct them.

| Model | In $/MTok | Out $/MTok | 50/50 blend $/MTok | Source |
|---|---|---|---|---|
| gpt-5.6-sol | 5.00 | 30.00 | 17.50 | https://developers.openai.com/api/docs/models; alias mapping: https://developers.openai.com/api/docs/pricing |
| gpt-daybreak-blue-latest | 5.00 | 30.00 | 17.50 | https://developers.openai.com/api/docs/pricing - alias of gpt-5.6-sol as of 2026-08-20 |
| gpt-5.6-cyber | 12.50 | 75.00 | 43.75 | https://developers.openai.com/api/docs/pricing |
| gpt-daybreak-red-latest | 12.50 | 75.00 | 43.75 | https://developers.openai.com/api/docs/pricing - alias of gpt-5.6-cyber as of 2026-08-20 |
| gpt-5.6-terra | 2.00 | 12.00 | 7.00 | https://developers.openai.com/api/docs/models |
| gpt-5.6-luna | 0.20 | 1.20 | 0.70 | https://developers.openai.com/api/docs/models |
| claude-fable-5 | 10.00 | 50.00 | 30.00 | https://platform.claude.com/docs/en/about-claude/pricing |
| claude-sonnet-5 | 3.00 | 15.00 | 9.00 | https://platform.claude.com/docs/en/about-claude/pricing - intro 2.00/10.00 through 2026-08-31 |
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
