{#
  weighted_mean: pitches-weighted mean, rounded to 1 dp — the SQL twin of
  src/portal/rollup.py `_weighted_mean`.

  Python semantics reproduced exactly:
    - sum(value * weight) / sum(weight)
    - skip any pair where value OR weight is null (the Python `continue`)
    - return NULL if the surviving total weight is 0 (the `if den == 0: return None`)
    - round to 1 decimal place

  Use inside a GROUP BY. Optional `predicate` restricts to a subset of rows
  (e.g. "code = 'fb'") the way rollup.py filters `crows`/`fb_rows`.

  Args:
    value     - the column being averaged (e.g. 'stuff_plus')
    weight    - the weight column (e.g. 'pitches')
    predicate - optional SQL boolean to scope the rows (default: all rows)
#}
{% macro weighted_mean(value, weight, predicate=none) %}
    {%- set base_filter -%}
        {{ value }} is not null and {{ weight }} is not null
        {%- if predicate %} and ({{ predicate }}){% endif -%}
    {%- endset -%}
    round(
        sum(({{ value }}) * ({{ weight }})) filter (where {{ base_filter }})
        / nullif(sum({{ weight }}) filter (where {{ base_filter }}), 0),
        1
    )
{% endmacro %}
