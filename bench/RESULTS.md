# expo benchmark report

Pricing is in API-list terms, using the 50/50 blend in `skills/receipts/references/prices.md`.

| task | arm | worker model | orchestrator | worker tokens | orchestration tokens | ~cost | verified | wallclock |
| --- | --- | --- | --- | ---: | ---: | ---: | --- | ---: |
| 01-cents-precision | delegated | gpt-5.6-terra | claude-opus-5 | 29,233 | 3,490 | ~$0.31 | yes | 91s |
| 01-cents-precision | direct | claude-opus-5 | claude-opus-5 | 0 | 26,984 | ~$0.40 | yes | 84s |
| 02-reject-nonfinite | delegated | gpt-5.6-terra | claude-opus-5 | 26,809 | 1,961 | ~$0.26 | yes | 67s |
| 02-reject-nonfinite | direct | claude-opus-5 | claude-opus-5 | 0 | 17,089 | ~$0.26 | yes | 35s |
| 03-rename-label | delegated | gpt-5.6-luna | claude-opus-5 | 24,217 | 2,155 | ~$0.12 | yes | 67s |
| 03-rename-label | direct | claude-opus-5 | claude-opus-5 | 0 | 22,984 | ~$0.34 | yes | 56s |

## Measured deltas

- 01-cents-precision: direct − delegated = ~$0.09 (delegated lower; observed difference on this measured task set).
- 02-reject-nonfinite: direct − delegated = ~$0.00 (equal; observed difference on this measured task set).
- 03-rename-label: direct − delegated = ~$0.22 (delegated lower; observed difference on this measured task set).

**Aggregate:** 3 tasks compared; delegated total ~$0.69; direct total ~$1.00; total observed delta (direct − delegated) ~$0.31 (delegated lower; observed difference on this measured task set).
