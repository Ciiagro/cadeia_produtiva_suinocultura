-- RODAR NO SERVIDOR (banco painel_ateg), com o usuário administrador. SÓ se o usuário painel_leitura ainda não existir.
-- Troque TROQUE_ESTA_SENHA por uma senha forte e NOVA (não use a do postgres) antes de rodar.
CREATE ROLE painel_leitura LOGIN PASSWORD 'TROQUE_ESTA_SENHA';
GRANT CONNECT ON DATABASE painel_ateg TO painel_leitura;
GRANT USAGE ON SCHEMA public TO painel_leitura;
GRANT SELECT ON public.vw_suino_propriedades, public.vw_suino_mensal, public.vw_suino_despesa_subgrupo, public.vw_suino_tipo TO painel_leitura;
-- Depois de cada cópia o script reaplica o GRANT sozinho (as views são recriadas).
