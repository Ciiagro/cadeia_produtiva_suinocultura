-- CONFERÊNCIA DAS REGRAS (rodar no banco LOCAL api_sisateg, depois de criar_resumo_suinocultura.sql)
-- Mostra, por classe e por item, quanto vale cada coisa desde jun/2024. Use para decidir os 3 pontos abertos:
--   1) venda para abate (terminação) dentro da receita bruta?  2) Água/Energia dentro de "Mão de obra familiar"  3) Leite para Leitões
-- Compare o total de "Receita bruta" e "Despesa direta" de UM técnico/mês com a planilha do SisATeG ("Só ativas").
SELECT t.grupo, t.classe, t.subgrupo, COALESCE(t.item, '') AS item,
       COUNT(DISTINCT t.id_propriedade) AS propriedades,
       ROUND(SUM(t.valor)::numeric, 2) AS valor_rs
FROM public.resumo_suino_tipo t
GROUP BY 1,2,3,4
ORDER BY t.grupo DESC, t.classe, valor_rs DESC;
