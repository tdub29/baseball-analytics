# Game 6536340 (USD vs Charlotte 49ers) – Where real5_pbp_baseballr_style.csv Goes Wrong

## Summary

**1. Location column is wrong for every row.**  
For game 6536340, the **location** column (2nd column) is filled with the same play description on every row instead of the actual venue:

**2. Non-action lines counted as first PA of half-inning.**  
Lines 177–178 (top 6) are substitutions (“Hudson, T. to dh.”, “Baker, A. to p for Sloop, H..”), not plate appearances. Line 179 (“Howard hit by pitch”) is the first **action** of top 6. Previously, line 177 was marked `is_pa=1`, so the “first PA” of the half-inning was wrong. Substitution-only lines are now treated as non-PA so leadoff and PA counts are correct.

---

## 1. Location column

**Location column is wrong for every row.**  
For game 6536340, the **location** column (2nd column) is filled with the same play description on every row instead of the actual venue:

- **Wrong value (repeated on all 53 rows):**  
  `"Gunderson, C homered to center field, RBI (2-1 BBS)."`
- **Expected:** A venue string like `"Some Stadium (City, ST)"` (or empty if not on the page).

So the CSV is mis-assigning one play’s text into the **location** field for the entire game.

## USD roster check

Using `usd_roster_names.txt`, every USD batter name in the **description** column for game 6536340 matches the roster:

- Moran, Beltre, Springer, Gauna, Howard, Lobliner, Kern, Mestas, Venverloh ✓  

No wrong or missing USD names in the play descriptions.

## Root cause (in `ncaa_pbp_playwright.py`)

Location is set by the first cell that matches:

```python
if not location and 10 < len(c) < 80 and "field" in c.lower() and "(" in c:
    location = c
```

The play text `"Gunderson, C homered to center field, RBI (2-1 BBS)."` matches because:

- It has **"field"** (in “center field”).
- It has **"("** (in the count “(2-1 BBS)”).
- Length is in the 10–80 range.

So the scraper treats this play as the game location. For game 6536340, that cell apparently appears before (or instead of) the real venue cell, so every row gets this wrong location.

## Fix

Tighten the location heuristic so it does not accept play descriptions, e.g.:

- Require venue-like patterns (e.g. ends with `")"`, or contains `", ST)"` / `", CA)"`, or “Stadium” / “Field” as a venue name), and/or  
- Exclude cells that look like plays (e.g. contain “RBI”, “homered”, “singled”, “walked”, “struck out”, “flied out”, etc.).

Then re-scrape or re-build the CSV for game 6536340 so the location column gets the real venue (or stays empty) instead of the Gunderson home run text.

---

## 2. Non-action lines (substitutions) as first “PA” of half-inning

**Fix (in `baseballr_description_mappings.py`):**  
- Added NON_PA phrases: `" to dh."` and `" to p."` so lines like “Hudson, T. to dh.” and “Baker, A. to p.” are excluded from PAs.  
- Added regex `_SUB_TO_POS_RE` for “Last, F. to &lt;pos&gt;.” (e.g. “Gonzalez, D. to ss.”).  
- `is_non_pa()` now returns True for these substitution lines, so they get `is_pa=0` and are not treated as the first PA of the half-inning. After re-running the validation step that builds `real5_pbp_baseballr_style.csv`, line 179 (“Howard hit by pitch”) is the first PA of top 6.
