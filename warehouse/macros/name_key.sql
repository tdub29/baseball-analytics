{#
  name_key: a stable, sorted, de-accented join key for a player name.

  Mirrors src/portal/util.py `name_key` / `normalize_name`:
    - lowercase
    - strip accents (DuckDB `strip_accents`)
    - drop punctuation/digits (keep a-z and spaces)
    - drop common suffixes (jr/sr/ii/iii/iv/v)
    - sort the remaining tokens so 'First Last' and 'Last, First' collapse equal

  NOTE on scope (honest): the Python version also (a) expands a small nickname
  table (alex->alexander, mike->michael, ...) and (b) merges runs of single-letter
  tokens ('a j' -> 'aj'). Those two refinements are intentionally NOT reproduced
  here — they exist to help fuzzy *entity resolution* in the Python loader, which
  is out of dbt's scope (dbt consumes the already-resolved exports). This macro
  gives a deterministic, accent/case/order-insensitive key, which is what the
  warehouse joins need. See MIGRATION.md.
#}
{% macro name_key(column) %}
    (
        select string_agg(tok, ' ' order by tok)
        from (
            select unnest(
                string_split_regex(
                    trim(
                        regexp_replace(
                            strip_accents(lower(cast({{ column }} as varchar))),
                            '[^a-z ]', ' ', 'g'
                        )
                    ),
                    '\s+'
                )
            ) as tok
        ) t
        where tok <> ''
          and tok not in ('jr', 'sr', 'ii', 'iii', 'iv', 'v')
    )
{% endmacro %}
