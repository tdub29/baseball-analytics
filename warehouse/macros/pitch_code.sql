{#
  pitch_code: map a free-text pitch-type label to the normalized bucket used
  across the warehouse and the schema's per-code columns (fb/si/sl/cb/ch/ct).

  Mirrors src/portal/arsenal.py `_CODE` (and trackman.py `_PITCH_CODE`):
    Fastball / Four-Seam / FourSeamFastBall   -> fb
    Sinker / Two-Seam / TwoSeamFastBall       -> si
    Cutter                                    -> ct
    Slider / Sweeper                          -> sl
    Curveball / Curve / Knuckle Curve         -> cb
    Changeup / Change / Splitter              -> ch
  Anything else (incl. 'Undefined', 'Other')  -> NULL.

  Matching is case-insensitive and ignores spaces / hyphens, so 'Four-Seam',
  'FourSeamFastBall', and 'four seam' all collapse to 'fb' the same way the
  Python lower()-keyed dict does.
#}
{% macro pitch_code(column) %}
    {#- normalize: lowercase, drop spaces and hyphens -#}
    {%- set norm -%}
        replace(replace(lower(cast({{ column }} as varchar)), ' ', ''), '-', '')
    {%- endset -%}
    case
        when {{ norm }} in ('fastball', 'fourseam', 'fourseamfastball', 'four') then 'fb'
        when {{ norm }} in ('sinker', 'twoseam', 'twoseamfastball') then 'si'
        when {{ norm }} = 'cutter' then 'ct'
        when {{ norm }} in ('slider', 'sweeper') then 'sl'
        when {{ norm }} in ('curveball', 'curve', 'knucklecurve') then 'cb'
        when {{ norm }} in ('changeup', 'change', 'splitter') then 'ch'
        else null
    end
{% endmacro %}
