-- Pitch-type dimension, seeded from pitch_type_map (raw label -> code + label).
-- Kept as a small conformed dimension so fct_pitch and the arsenal mart share one
-- definition of the fb/si/sl/cb/ch/ct buckets.

with map as (

    select distinct
        code,
        code_label
    from {{ ref('pitch_type_map') }}

),

codes as (

    -- the canonical six buckets (so the dim exists even if the seed grows)
    select * from (values
        ('fb', 'Four-Seam Fastball'),
        ('si', 'Sinker'),
        ('ct', 'Cutter'),
        ('sl', 'Slider/Sweeper'),
        ('cb', 'Curveball'),
        ('ch', 'Changeup/Splitter')
    ) as t(code, code_label)

)

select
    {{ dbt_utils.generate_surrogate_key(['code']) }}                 as pitch_type_sk,
    code,
    coalesce(map.code_label, codes.code_label)                       as code_label,
    case code
        when 'fb' then 'fastball'
        when 'si' then 'fastball'
        when 'ct' then 'fastball'
        else 'offspeed/breaking'
    end                                                              as pitch_family
from codes
left join map using (code)
