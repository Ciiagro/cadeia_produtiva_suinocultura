# Rotina do painel de suinocultura

Depende da rotina da bovinocultura: a carga de receita/despesa e a atualização de `sisateg_receita_despesa` são as MESMAS.

## 1) pgAdmin, banco `api_sisateg`
Rodar o arquivo inteiro `sql/criar_resumo_suinocultura.sql`. Conferir a última linha: propriedades, com_lancamento, linhas_mensais, ultimo_mes.
(Opcional) `sql/conferencia_regras.sql` mostra os valores por classe e item.

## 2) Git Bash: copiar para o servidor
```
cd "/c/CIIAGRO2/painel_cadeias/Suinocultura"
python scripts/transferir_resumo.py
```
Depois abrir o painel e apertar Ctrl+F5.

Teste local: `uvicorn app.main:app --port 8004` e abrir http://localhost:8004

Se um passo der erro, as tabelas ficam como estavam (trocas "tudo ou nada"). Não siga para o passo seguinte.
