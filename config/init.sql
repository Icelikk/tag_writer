CREATE UNLOGGED TABLE IF NOT EXISTS public.Guts (
    id int2 NOT NULL,
    q int2 NOT NULL,
    v float4 NOT NULL,
    t int8 NOT NULL
) WITH (fillfactor = 95);
CREATE INDEX IF NOT EXISTS idx_aboba_id ON public.Guts USING btree (id);
CREATE INDEX IF NOT EXISTS idx_aboba_t_brin ON public.Guts USING brin (t) WITH (pages_per_range = 32);