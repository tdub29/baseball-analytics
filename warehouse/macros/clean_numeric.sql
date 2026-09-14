{#
  clean_numeric: strip units / formatting from a dimensional or percent cell and
  coerce to a double.

  Mirrors the Python pipeline's two coercers:
    - src/portal/arsenal.py `_dim`  : iVB '0.3"', RelHeight "6.3'", VAA '-9.1°'
        -> re.sub(r"[^0-9.\-]", "", s) then float
    - src/portal/util.py    `to_float`: strips '%' and ',' then float

  We strip everything that is not a digit, a dot, or a leading minus, then cast.
  Empty / lone-'-' / lone-'.' become NULL (matching the Python guards).

  Implemented with DuckDB regexp_replace so it works on the raw text columns.
#}
{% macro clean_numeric(column) %}
    {#- remove any char that is not 0-9, '.', or '-' (handles %, ", ', °, commas) -#}
    nullif(
        nullif(
            nullif(
                regexp_replace(cast({{ column }} as varchar), '[^0-9.\-]', '', 'g'),
                ''
            ),
            '-'
        ),
        '.'
    )::double
{% endmacro %}
