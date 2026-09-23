# Issue 20 information policy

The user selected the strict historical-information approach. This records that
choice; it does not register the protocol or certify any source as available.

At each first-of-month planting origin, all price, cost, yield and calendar inputs
must have a documented release strictly before that origin. Retain observation
period, release date, version and original source hash separately. A retrieval date
or a workbook's creation/modified timestamp is not a historical release date.
Use only revisions released before the origin; later revisions cannot overwrite
the historical feature record. Unknown release dates block use. Do not invent a
fixed release lag until publisher evidence supports it.

The rule is source-specific:

- A market observation is eligible only when the publisher's documented release
  date is strictly before the planting origin. A month label does not establish
  availability. Later corrected workbooks do not replace the selected vintage.
- A cost or calendar row must select the latest version whose effective date is
  on or before the origin and whose documented release is strictly before it.
  Later revisions remain excluded even when they describe an earlier season.
- A CPI observation used in ranking follows the same strict release cutoff. The
  current-vintage series may convert frozen outcomes for reporting only.
- The realized harvest price may be read after the target month solely to score
  an already frozen recommendation. It cannot affect feature construction,
  method selection, eligibility or the recommendation itself.

`farmable_ml.vintage.select_as_of` implements the deterministic cost/calendar
selection rule and rejects missing, cutoff-day, future and conflicting versions.

Forecasts and costs must share an explicit monetary basis established solely with
information available at the origin. If CPI is used in that transformation, its
release vintage must meet the same cutoff. The current committed Stats SA series
is reporting-only: its future base and revised history cannot enter prediction,
method selection, crop eligibility or recommendation ranking. Freeze the choice
before reading outcomes or applying retrospective reporting conversion to 2025
rand. The exact historical monetary transformation remains a protocol dependency
until dated price and cost sources establish a compatible basis.

The prohibited shortcut has a reproducible counterexample. With revenues 100 and
70, modern costs 120 and 40, and known CPI 100, deflating those costs using future
CPI 200 gives margins 40 and 50. Changing only future CPI to 400 gives margins 70
and 60 and reverses the winner. `test_future_cpi_deflation_of_modern_costs_can_reverse_the_winner`
checks this arithmetic. The decision tests also reject future-dated costs and
vary reporting multipliers after freezing a recommendation. The vintage mutation
tests prove that adding a future value or revision cannot change the selected
inputs. These component tests do not certify a real historical run.

Missing historical budgets/calendars remain blockers. The 2025 budgets may inform
source review but cannot be substituted into 2012 decisions. Processing-tomato
costs remain a separate fresh-market compatibility caveat. The literal planting-time
claim is retained as a requirement, not claimed as achieved. `build_report`
therefore requires an explicit verified-cutoff attestation for historical data,
stores it in the report, and refuses to render a historical headline if it is
missing or changed. Synthetic fixtures cannot set that attestation.

## Report coverage contract

Historical report schema 2 requires an audit row for each of the 156 planting months
from January 2012 through December 2024 and each of the eight default crops: 1,248
unique keys. Omitted, duplicate and out-of-period keys fail before metrics run.
Unscorable comparisons must remain explicit skipped rows with a reason and no
partial margins; coverage does not require 1,248 scored decisions. Seasonal
ineligibility must be recorded from the verified calendar, never filled with an
invented outcome. The existing `eligible` metric counts ledger rows, including
skips; `decisions` counts scored comparisons. Calendar eligibility will need its
own denominator in the runner once calendars are verified.

Dates displayed in both outputs come from validated coverage. Sparse synthetic
fixtures keep their actual bounds and synthetic label. Legacy summaries without
coverage metadata cannot generate a headline. Complete keys alone do not prove
source availability, adequate scored evidence, or satisfy the protocol history
gate. The development artifact writer still accepts synthetic reports only.
