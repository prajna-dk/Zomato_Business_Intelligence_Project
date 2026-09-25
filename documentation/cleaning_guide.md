# Cleaning Layer — Reference Guide

Plain-language notes on `src/clean.py` — what it does, why, and what to check if a
number looks off after running it. For the analytical-dataset step (the one after
this), see `analytical_layer_guide.md` instead.

---

## 1. Where this fits

```
data/raw/*.csv        (untouched originals — mixed date formats, negative
                        numbers, casing issues, typos, duplicates)
        │
        ▼
   src/ingest.py  ->  load_raw()
        │
        ▼
   src/clean.py   ->  clean_all()      one function per dataset, applying
                                        the exact decisions from your original
                                        data_cleaning.ipynb
        │
        ▼
data/cleaned/*.csv    (what src/features.py builds the analytical tables from)
```

`documentation/cleaning_decisions_Profiling.csv` is the actual decision log you
exported from the notebook — every function in `clean.py` has a docstring pointing
back to a row in that file, so you can always trace "why does this code do that?"
back to the original evidence.

**Important:** `clean.py` is written to run against your **real raw CSVs**
(`data/raw/`). Those weren't uploaded in this project — only the already-cleaned
ones were — so this code hasn't been run against the real full dataset yet, only
tested against small made-up messy rows to prove the logic works. Run
`clean_all()` against your actual raw files once you have them in `data/raw/`, and
compare the row counts it prints against `cleaning_decisions_Profiling.csv` (they
should match, since that's exactly where every number in the code came from).

---

## 2. The rule this whole file follows

**Fix what's clearly wrong. Never guess what's missing.**

- A negative age, an out-of-range rating, an unreadable date → clearly wrong →
  fixed or set to blank.
- A blank Email, a missing Cuisine, a customer with no Gender listed → genuinely
  unknown → left blank. No code in this file invents a value to fill a gap.

If you ever wonder "why didn't it just fill that in?", this is why.

---

## 3. "How did you clean X?" — quick answers

**Q: Why do some columns have a `_raw` twin (e.g. `Phone_raw`, `OrderDate_raw`)?**
Whenever we change a column's actual values, we keep the original untouched
version alongside it under `_raw`. That way, if a cleaning rule ever looks wrong,
you can go back and see exactly what the original value was — nothing is lost.

**Q: How does date cleaning decide what's "ambiguous"?**
A date like `03/04/2023` could mean 3rd April or 4th March — there's no way to
tell which. Rather than guess, we only keep a date when the format makes it
unambiguous:
- Year written first (`2023-04-03`) — no ambiguity, year is always 4 digits.
- Month written as a name (`03-Apr-2023`) — no ambiguity either.
- One of the two numbers is over 12 (`25/04/2023`) — must be day, since no
  month goes past 12.

Anything else becomes blank (`NaT`) rather than a guess.

**Q: `orders.OrderDate` still has some blanks even after cleaning — why?**
Some order dates were ambiguous or missing entirely. Before giving up, we check
if that order has a matching payment record (`payments.PaymentDate`, same
`OrderID`) and borrow that date instead — payments tend to happen right around
the order. About 1,737 dates were recovered this way; 1,176 genuinely couldn't be
recovered from anywhere and stay blank.

**Q: Why does `FoodCost` sometimes stay negative even after cleaning?**
Most negative `FoodCost` values get flipped positive — but only when we can
cross-check against `FinalAmount` to confirm that's the right number. A handful
of rows had no `FinalAmount` to check against, so we couldn't safely "fix" them —
those stay negative, and their `FinalAmount` is left blank too rather than being
calculated from a number we already know is wrong.

**Q: Why did some `customer_feedback` rows disappear completely?**
A small number of orders had two feedback rows with genuinely different ratings
(e.g. one review rated the delivery 5 stars, another rated the same order 2
stars) — with no timestamp, there's no way to know which one is "correct" or
more recent. Rather than arbitrarily pick one, both rows are dropped.

**Q: Why does `menu.Price` sometimes become blank instead of just flipped positive?**
For most negative prices, `order_items` confirms the same food item really does
sell around that price elsewhere, so we just flip the sign. One item's price
couldn't be confirmed that way, so it was left blank instead of guessed.

**Q: My raw data has a different city spelling and it's not getting mapped — what do I do?**
Open `CITY_MAPPING` near the top of `clean.py` and add the old-name → canonical-name
pair. It's a plain dictionary, easy to extend.

---

## 4. If a number looks wrong after running `clean_all()`

| Symptom | Likely cause | What to check |
|---|---|---|
| Row count for a dataset doesn't match the log | Your raw CSV differs from what the log describes (edited since, or a different export) | Compare against `cleaning_decisions_Profiling.csv`'s `before_count` for that dataset |
| A date column is mostly blank | Most of that column's dates were genuinely ambiguous (see the date rule above) | Check the `_raw` column to see the original text |
| `FinalAmount` blank for a row with all four inputs present | `FoodCost` on that row was one of the unresolved negative cases | Check `FoodCost` on that row — if it's still negative, that's why |
| A whole customer/order looks "missing" after cleaning | It was an exact duplicate row and got dropped, keeping the first copy | Search the raw CSV for that ID — you should find 2+ identical rows |
| `menu.Price` is blank for an item that used to have a (negative) price | That item's price couldn't be cross-checked against `order_items` | Check whether that `FoodItemID` appears in `order_items` at all |

---

## 5. Where to look next

- The exact numbers behind every rule → `documentation/cleaning_decisions_Profiling.csv`
- The code itself, one function per dataset → `src/clean.py`
- What happens after cleaning (the analytical tables) → `documentation/analytical_layer_guide.md`
