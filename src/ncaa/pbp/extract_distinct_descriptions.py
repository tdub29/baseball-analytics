"""
Extract distinct description patterns from baseballr-style PBP CSV.
Output: unique descriptions and optional canonical patterns for mapping review.
Run: python extract_distinct_descriptions.py
"""

from __future__ import annotations

import re
from pathlib import Path

import pandas as pd

CSV_PATH = Path(__file__).resolve().parent / "real5_pbp_baseballr_style.csv"
OUT_UNIQUE = Path(__file__).resolve().parent / "real5_descriptions_distinct.csv"
OUT_PATTERNS = Path(__file__).resolve().parent / "real5_descriptions_canonical_patterns.txt"


def normalize(s: str) -> str:
    if pd.isna(s) or not isinstance(s, str):
        return ""
    return s.strip().lower()


def to_canonical_pattern(desc: str) -> str:
    """Replace likely player/name tokens with placeholder for grouping."""
    if not desc or not isinstance(desc, str):
        return ""
    s = desc.strip()
    # Replace "NAME, X" or "NAME" at start (common NCAA format) with placeholder
    s = re.sub(r"^[A-Z][A-Za-z\'\-]+,?\s*[A-Z]?\s*", "X ", s, count=1, flags=re.IGNORECASE)
    # Normalize count in parens to (count)
    s = re.sub(r"\(\s*[0-9\-]+\s+[A-Z0-9]+\s*\)", "(count)", s)
    s = re.sub(r"\([0-9\-]+[A-Z0-9\s]*\)", "(count)", s)
    return s.strip().lower()


def main() -> None:
    df = pd.read_csv(CSV_PATH)
    if "description" not in df.columns:
        raise ValueError("CSV must have 'description' column")
    descriptions = df["description"].astype(str).str.strip()
    descriptions = descriptions[descriptions.str.len() > 0]

    # Unique descriptions (sorted for review)
    unique = descriptions.drop_duplicates().sort_values().reset_index(drop=True)
    unique_df = pd.DataFrame({"description": unique})
    unique_df.to_csv(OUT_UNIQUE, index=False)
    print(f"Wrote {len(unique_df)} unique descriptions to {OUT_UNIQUE}")

    # Canonical patterns: group by pattern, show count
    normalized = descriptions.apply(normalize)
    patterns = normalized.apply(to_canonical_pattern)
    pattern_counts = patterns.value_counts().sort_index()
    with open(OUT_PATTERNS, "w", encoding="utf-8") as f:
        f.write("# Canonical description patterns (placeholder X, count token)\n")
        f.write(f"# Total unique patterns: {len(pattern_counts)}\n\n")
        for pattern, count in pattern_counts.items():
            f.write(f"{count}\t{pattern}\n")
    print(f"Wrote {len(pattern_counts)} canonical patterns to {OUT_PATTERNS}")


if __name__ == "__main__":
    main()
