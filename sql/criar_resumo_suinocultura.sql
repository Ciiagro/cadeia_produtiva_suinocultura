-- =====================================================================
-- SUINOCULTURA
-- RODAR NO BANCO LOCAL  api_sisateg   (F5 uma vez; leva alguns minutos)
-- Cria QUATRO tabelas (nomes próprios, para não misturar com as outras cadeias no servidor):
--   public.resumo_suino_propriedades        -> 1 linha por propriedade (ativas e inativas com lançamento)
--   public.resumo_suino_mensal              -> 1 linha por propriedade e mês: animais vendidos, receita bruta, despesa direta
--   public.resumo_suino_despesa_subgrupo    -> despesa direta por subgrupo e mês (a soma dos subgrupos = despesa direta)
--   public.resumo_suino_tipo                -> receitas e despesas por classe/tipo (aba "Receitas e despesas")
--
-- Mesma lógica da ovinocaprinocultura, ajustada aos itens da suinocultura:
--   valor do lançamento = QUANTIDADE x VALOR_UNITARIO (mesma visita e mesmo item)
--   Receita bruta    = toda a receita MENOS empréstimo (recebimento) e investimento (venda de bem).
--                      Inclui venda de animal vivo (leitão, leitoa, matriz, reprodutor...), venda para abate (terminação),
--                      venda de animal abatido (kg), esterco e outras receitas.
--   Despesa direta   = despesas MENOS empréstimo, investimento (aquisição de bem, inclui compra de leitões/animal de produção)
--                      e mão de obra familiar. A compra de animais para recria/terminação CONTA como despesa direta.
--   Animais vendidos = cabeças dos subgrupos "Venda de Animal ..." (o item "Venda Animal Abatido" é em kg, não conta como cabeça).
--
-- DECISÕES A CONFERIR com a planilha do SisATeG de um técnico (rodar sql/conferencia_regras.sql para ver os valores):
--   1) Venda para abate (terminação) entra na receita bruta? AQUI: SIM (é o principal produto da suinocultura).
--      Na ovinocaprinocultura ela ficou fora porque a planilha assim pedia. Para tirar: mude suino_abate_na_receita() para FALSE e rode tudo de novo.
--   2) Subgrupo "Mão de obra familiar" inteiro (inclui os itens Água/Energia lançados ali) fica FORA da despesa direta.
--   3) "Leite para Leitões" (aleitamento artificial) CONTA como despesa direta (na ovinocaprinocultura ficou fora).
-- =====================================================================

-- ---- regras em um lugar só (as 4 tabelas usam estas funções) ----
CREATE OR REPLACE FUNCTION public.suino_abate_na_receita() RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT TRUE $$;

CREATE OR REPLACE FUNCTION public.suino_classe(p_grupo text, p_subgrupo text, p_item text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_grupo = 'Receita' THEN
      CASE WHEN p_subgrupo ILIKE 'Empr%' OR p_subgrupo ILIKE 'Investimento%' THEN 'Fora da receita bruta'
           WHEN p_subgrupo ILIKE 'Venda de Animal Abate%' AND NOT public.suino_abate_na_receita() THEN 'Fora da receita bruta'
           ELSE 'Receita bruta' END
    WHEN p_grupo = 'Despesa' THEN
      CASE WHEN p_subgrupo ILIKE 'Empr%' OR p_subgrupo ILIKE 'Investimento%' THEN 'Fora das despesas'
           WHEN p_subgrupo ILIKE 'M_o de obra familiar%' OR p_item ILIKE 'M_o de obra familiar' THEN 'Outras despesas'
           ELSE 'Despesa direta' END
  END
$$;

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS public.resumo_suino_propriedades;
CREATE TABLE public.resumo_suino_propriedades AS
WITH ativas AS (  -- propriedades ATIVAS que têm vínculo ATIVO de SUINOCULTURA
  SELECT id_propriedade, MAX(produtor) AS produtor, MAX(NULLIF(tecnico_atual,'')) AS tecnico_a,
         MAX(NULLIF(supervisor_atual,'')) AS supervisor_a
  FROM public.propriedades_ativas_na_ateg
  WHERE id_propriedade::text IN (
        SELECT id_propriedade::text FROM public.sisateg_vinculo_propriedade
        WHERE atividade ILIKE '%SUINOCULTURA%' AND UPPER(status_vinculo) = 'ATIVO')
  GROUP BY 1
),
lanc_ids AS (  -- toda propriedade que já teve lançamento de suinocultura (ativa ou não) desde o início da base
  SELECT DISTINCT id_propriedade FROM public.sisateg_receita_despesa
  WHERE atividade = 'SUINOCULTURA' AND status_item = 'ATIVO' AND tipo_registro = 'PRINCIPAL'
    AND dt_referencia >= DATE '2023-01-01'
),
todas AS (  -- ativas + inativas que têm lançamento (ativa = TRUE/FALSE)
  SELECT id_propriedade, produtor, tecnico_a, supervisor_a, TRUE AS ativa FROM ativas
  UNION ALL
  SELECT l.id_propriedade, NULL, NULL, NULL, FALSE FROM lanc_ids l
  WHERE l.id_propriedade NOT IN (SELECT id_propriedade FROM ativas)
),
acomp AS (
  SELECT id_propriedade, MAX(tecnico_atual) AS tecnico_m, MAX(tecnico_responsavel) AS tecnico_r,
         MAX(supervisor_atual) AS supervisor_m, MAX(produtor) AS produtor_m, MAX(imovel) AS imovel_m
  FROM public.acompanhamento_mensal_visitas
  WHERE id_propriedade IN (SELECT id_propriedade FROM todas) GROUP BY 1
),
nome AS (
  SELECT id_propriedade, MAX(propriedade) AS propriedade
  FROM public.sisateg_rel_indicador_padrao_mensal
  WHERE propriedade IS NOT NULL AND id_propriedade IN (SELECT id_propriedade FROM todas) GROUP BY 1
),
area AS (  -- área produtiva: do cadastro; se for 0/vazia, usa a do relatório de indicadores do SisATeG
  SELECT d.id_propriedade, MAX(d.area_total) AS area_total,
         COALESCE(NULLIF(MAX(d.area_atividades_produtivas), 0), MAX(i.area_prod)) AS area_produtiva,
         MAX(d.municipio) AS municipio, MAX(d.uf) AS uf
  FROM public.dim_propriedade d
  LEFT JOIN (SELECT id_propriedade::text AS idp, MAX(NULLIF(area_produtiva::text, '')::numeric) AS area_prod
             FROM public.sisateg_rel_indicador_padrao_mensal GROUP BY 1) i ON i.idp = d.id_propriedade::text
  WHERE d.id_propriedade IN (SELECT id_propriedade FROM todas) GROUP BY 1
),
vinc AS (
  SELECT id_propriedade::text AS idp, id_projeto, projeto, status_vinculo, motivo_desativacao,
         dt_inicio::date AS ini, dt_fim::date AS fim
  FROM public.sisateg_vinculo_propriedade
  WHERE atividade ILIKE '%SUINOCULTURA%' AND id_propriedade::text IN (SELECT id_propriedade::text FROM todas)
),
vu AS (  -- um vínculo por propriedade: o ATIVO (se houver) de início mais recente
  SELECT DISTINCT ON (idp) idp, id_projeto, projeto, ini, fim, status_vinculo, motivo_desativacao
  FROM vinc
  ORDER BY idp, (UPPER(status_vinculo) = 'ATIVO') DESC, ini DESC, fim DESC NULLS FIRST
),
nproj AS (SELECT idp, COUNT(DISTINCT id_projeto) AS qtd_projetos FROM vinc GROUP BY 1)
SELECT a.id_propriedade,
       COALESCE(n.propriedade, ac.imovel_m) AS propriedade,
       COALESCE(a.produtor, ac.produtor_m) AS produtor,
       btrim(COALESCE(a.tecnico_a, ac.tecnico_m, ac.tecnico_r), E' \t\r\n') AS tecnico,
       COALESCE(a.supervisor_a, ac.supervisor_m)         AS supervisor_sisateg,
       ar.municipio, ar.uf,
       ROUND(ar.area_total::numeric, 2)    AS area_total,
       ROUND(ar.area_produtiva::numeric, 2) AS area_produtiva,
       vu.projeto, np.qtd_projetos,
       vu.ini AS inicio_projeto, vu.fim AS fim_projeto,
       vu.status_vinculo, vu.motivo_desativacao, a.ativa
FROM todas a
LEFT JOIN acomp ac ON ac.id_propriedade = a.id_propriedade
LEFT JOIN nome n   ON n.id_propriedade  = a.id_propriedade
LEFT JOIN area ar  ON ar.id_propriedade = a.id_propriedade
LEFT JOIN vu       ON vu.idp = a.id_propriedade::text
LEFT JOIN nproj np ON np.idp = a.id_propriedade::text;

CREATE INDEX ON public.resumo_suino_propriedades (id_propriedade);
CREATE INDEX ON public.resumo_suino_propriedades (tecnico);

-- ---------------------------------------------------------------------
-- Itens da suinocultura com o MÊS CORRIGIDO e SEM visitas excluídas (a planilha do SisATeG conta assim):
--  * mês = referência da visita (vale mesmo que os itens tenham data bem mais antiga, ex.: item copiado de visita antiga);
--    só ignora referência MUITO ANTERIOR aos itens (mais de 366 dias antes);
--  * visita EXCLUÍDA no SisATeG (dt_exclusao_visita preenchida) não entra.
DROP TABLE IF EXISTS public.resumo_suino_rd;
CREATE TABLE public.resumo_suino_rd AS
SELECT r.* FROM public.sisateg_receita_despesa r
WHERE r.atividade = 'SUINOCULTURA' AND r.status_item = 'ATIVO' AND r.tipo_registro = 'PRINCIPAL'
  AND r.dt_referencia >= DATE '2023-01-01'
  AND NOT EXISTS (SELECT 1 FROM public.sisateg_rel_listar_visita lvx WHERE lvx.id_visita::text = r.id_visita::text AND lvx.dt_exclusao_visita IS NOT NULL);
UPDATE public.resumo_suino_rd b SET dt_referencia = to_date(lv.referencia_visita || '-01', 'YYYY-MM-DD')
FROM public.sisateg_rel_listar_visita lv
WHERE lv.id_visita::text = b.id_visita::text AND lv.referencia_visita ~ '^[0-9]{4}-[0-9]{2}$'
  AND (to_date(lv.referencia_visita || '-01', 'YYYY-MM-DD') - b.dt_referencia::date) >= -366;
CREATE INDEX ON public.resumo_suino_rd (id_propriedade, id_visita);
ANALYZE public.resumo_suino_rd;

DROP TABLE IF EXISTS public.resumo_suino_mensal;
CREATE TABLE public.resumo_suino_mensal AS
WITH base AS (
  SELECT r.*
  FROM public.resumo_suino_rd r
  WHERE r.atividade = 'SUINOCULTURA'
    AND r.status_item = 'ATIVO'
    AND r.tipo_registro = 'PRINCIPAL'
    AND r.dt_referencia BETWEEN DATE '2023-01-01' AND DATE '2026-12-31'
    AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_suino_propriedades)
),
q AS (
  SELECT id_propriedade, grupo, id_visita, id_item, dt_referencia, subgrupo, item, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6,7
),
pr AS (
  SELECT id_propriedade, grupo, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4,5
),
v AS (
  SELECT q.id_propriedade, date_trunc('month', q.dt_referencia)::date AS mes,
         q.grupo, q.subgrupo, q.item, q.qtd, q.qtd * pr.preco AS valor,
         public.suino_classe(q.grupo, q.subgrupo, q.item) AS classe,
         -- "Venda Animal Abatido" é lançado em kg (carcaça): vale em R$, mas não conta como cabeça
         (q.grupo = 'Receita' AND q.subgrupo ILIKE 'Venda de Animal%' AND q.item NOT ILIKE 'Venda Animal Abatido%') AS venda_cab
  FROM q JOIN pr USING (id_propriedade, grupo, id_visita, id_item, dt_referencia)
),
tec_mes AS (  -- técnico responsável pela visita daquele mês (técnico da época)
  SELECT b.id_propriedade, date_trunc('month', b.dt_referencia)::date AS mes,
         MAX(btrim(av.tecnico_responsavel, E' \t\r\n')) AS tecnico
  FROM base b
  JOIN public.acompanhamento_mensal_visitas av ON av.id_visita::text = b.id_visita::text
  GROUP BY 1, 2
),
fin AS (
  SELECT id_propriedade, mes,
    SUM(qtd)   FILTER (WHERE venda_cab)                                              AS animais_vendidos,
    SUM(valor) FILTER (WHERE venda_cab)                                              AS venda_cab_rs,
    SUM(valor) FILTER (WHERE grupo = 'Receita' AND subgrupo ILIKE 'Venda de Animal%'
                         AND classe = 'Receita bruta')                               AS venda_animais_rs,
    SUM(valor) FILTER (WHERE classe = 'Receita bruta')                               AS receita_bruta,
    SUM(valor) FILTER (WHERE classe = 'Despesa direta')                              AS despesa_direta,
    SUM(valor) FILTER (WHERE grupo = 'Despesa' AND (subgrupo ILIKE 'M_o de obra familiar%' OR item ILIKE 'M_o de obra familiar'))
                                                                                     AS mao_obra_familiar,
    SUM(valor) FILTER (WHERE grupo = 'Despesa')                                      AS despesa_total
  FROM v GROUP BY 1,2
)
SELECT f.id_propriedade,
       to_char(f.mes, 'YYYY-MM') AS mes,
       t.tecnico,
       ROUND(f.animais_vendidos::numeric, 1)     AS animais_vendidos,
       ROUND(f.venda_animais_rs::numeric, 2)     AS venda_animais_rs,
       ROUND(f.venda_cab_rs::numeric, 2)         AS venda_cab_rs,
       ROUND(f.receita_bruta::numeric, 2)        AS receita_bruta,
       ROUND(f.despesa_direta::numeric, 2)       AS despesa_direta,
       ROUND(f.mao_obra_familiar::numeric, 2)    AS mao_obra_familiar,
       ROUND(f.despesa_total::numeric, 2)        AS despesa_total
FROM fin f
LEFT JOIN tec_mes t ON t.id_propriedade = f.id_propriedade AND t.mes = f.mes;

CREATE INDEX ON public.resumo_suino_mensal (id_propriedade);
CREATE INDEX ON public.resumo_suino_mensal (tecnico);
CREATE INDEX ON public.resumo_suino_mensal (mes);

-- ---------------------------------------------------------------------
-- Despesa direta por SUBGRUPO e mês (a soma dos subgrupos = despesa_direta acima)
DROP TABLE IF EXISTS public.resumo_suino_despesa_subgrupo;
CREATE TABLE public.resumo_suino_despesa_subgrupo AS
WITH base AS (
  SELECT r.* FROM public.resumo_suino_rd r
  WHERE r.atividade = 'SUINOCULTURA' AND r.status_item = 'ATIVO' AND r.tipo_registro = 'PRINCIPAL'
    AND r.dt_referencia BETWEEN DATE '2023-01-01' AND DATE '2026-12-31'
    AND r.grupo = 'Despesa'
    AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_suino_propriedades)
),
q AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, subgrupo, item, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6
),
pr AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4
)
SELECT q.id_propriedade, to_char(date_trunc('month', q.dt_referencia), 'YYYY-MM') AS mes, q.subgrupo,
       ROUND(SUM(q.qtd * pr.preco)::numeric, 2) AS valor
FROM q JOIN pr USING (id_propriedade, id_visita, id_item, dt_referencia)
WHERE public.suino_classe('Despesa', q.subgrupo, q.item) = 'Despesa direta'
GROUP BY 1,2,3;
CREATE INDEX ON public.resumo_suino_despesa_subgrupo (id_propriedade, mes);

-- ---------------------------------------------------------------------
-- Receitas e despesas por TIPO e classe (aba "Receitas e despesas").
--   classe: Receita bruta | Fora da receita bruta (empréstimo / venda de bem)
--           Despesa direta | Outras despesas (mão de obra familiar) | Fora das despesas (empréstimo / investimento)
--   Receita: o tipo mostrado é o ITEM (leitão, terminação, matriz...); despesa: o SUBGRUPO.
--   total de despesas da aba = Despesa direta + Outras despesas + Fora das despesas (= Total Despesas do SisATeG)
DROP TABLE IF EXISTS public.resumo_suino_tipo;
CREATE TABLE public.resumo_suino_tipo AS
WITH base AS (
  SELECT r.* FROM public.resumo_suino_rd r
  WHERE r.atividade = 'SUINOCULTURA' AND r.status_item = 'ATIVO' AND r.tipo_registro = 'PRINCIPAL'
    AND r.dt_referencia BETWEEN DATE '2023-01-01' AND DATE '2026-12-31'
    AND r.grupo IN ('Receita','Despesa')
    AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_suino_propriedades)
),
q AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, grupo, subgrupo, item, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6,7
),
pr AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4
),
v AS (
  SELECT q.id_propriedade, to_char(date_trunc('month', q.dt_referencia), 'YYYY-MM') AS mes, q.grupo, q.subgrupo,
         CASE WHEN q.grupo = 'Receita' THEN q.item END AS item,
         public.suino_classe(q.grupo, q.subgrupo, q.item) AS classe,
         q.qtd * pr.preco AS valor
  FROM q JOIN pr USING (id_propriedade, id_visita, id_item, dt_referencia)
)
SELECT id_propriedade, mes, grupo, classe, subgrupo, item, ROUND(SUM(valor)::numeric, 2) AS valor
FROM v GROUP BY 1,2,3,4,5,6;
CREATE INDEX ON public.resumo_suino_tipo (id_propriedade, mes);

ANALYZE public.resumo_suino_propriedades;
ANALYZE public.resumo_suino_mensal;

-- Conferência: propriedades e quantas têm lançamento de suinocultura
SELECT (SELECT COUNT(*) FROM public.resumo_suino_propriedades) AS propriedades,
       (SELECT COUNT(DISTINCT id_propriedade) FROM public.resumo_suino_mensal) AS com_lancamento,
       (SELECT COUNT(*) FROM public.resumo_suino_mensal) AS linhas_mensais,
       (SELECT MAX(mes) FROM public.resumo_suino_mensal) AS ultimo_mes;
