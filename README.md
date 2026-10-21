# Painel de acompanhamento mensal: Suinocultura

Mesmo painel da ovinocaprinocultura (FastAPI + Chart.js na Vercel), adaptado à suinocultura.
Lê as views `vw_suino_mensal`, `vw_suino_propriedades`, `vw_suino_despesa_subgrupo` e `vw_suino_tipo` do banco `painel_ateg`.
Não mexe nas views das outras cadeias (nomes próprios).

## O que o painel mostra
Receita bruta, despesa direta, venda de animais, preço médio por animal, animais vendidos (cabeças), margem bruta da atividade,
margem da venda de animais e animais vendidos por produtor.
Abas: Gráficos, Destaques do mês, Causas (entradas/saídas, preço por animal, despesa por subgrupo), Receitas e despesas (por tipo) e Tabela mensal (+ Excel).
Os filtros conversam entre si e respeitam o período De/Até.

## Regras (atividade SUINOCULTURA, status ATIVO, tipo PRINCIPAL; valor = QUANTIDADE x VALOR_UNITARIO)
- Receita bruta = toda a receita menos empréstimo (recebimento) e investimento (venda de bem). Inclui venda de animal vivo, venda para abate (terminação), animal abatido (kg), esterco e outras.
- Animais vendidos = cabeças de "Venda de Animal Vivo" + "Venda de Animal Abate". O item "Venda Animal Abatido" é em kg: entra em R$, não em cabeças.
- Preço por animal = venda em cabeças (R$) ÷ animais vendidos, média entre as propriedades.
- Despesa direta = despesas menos empréstimo, investimento (inclui aquisição de leitões / animal de produção) e mão de obra familiar.
  A compra de animais para recria/terminação conta como despesa direta.
- Total de despesas (aba Receitas e despesas) = direta + outras (mão de obra familiar) + investimento/empréstimo.
- O painel começa em jun/2024 (`MES_INICIO`).

## Pontos a conferir com a planilha do SisATeG (um técnico, "Só ativas")
1. Venda para abate dentro da receita bruta (aqui SIM; na ovinocaprinocultura ficou fora). Para mudar: `suino_abate_na_receita()` no SQL.
2. Subgrupo "Mão de obra familiar" inteiro (inclui os itens Água e Energia) fora da despesa direta.
3. "Leite para Leitões" (aleitamento) dentro da despesa direta.
Use `sql/conferencia_regras.sql` para ver o valor de cada classe/item.

## Rotina
Ver ROTINA_DIARIA.md. Primeira publicação: copiar o `.env`, criar repositório no GitHub e projeto na Vercel (variáveis REMOTE_DB_* em COLAR_NO_VERCEL.txt; apagar o arquivo depois).
