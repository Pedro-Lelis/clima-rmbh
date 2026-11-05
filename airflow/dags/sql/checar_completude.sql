with conferir_completude as (
	select dmm.municipio_id, dmm.nome, COUNT(cah.municipio_id) as linhas from dbo.dim_municipio dmm
	left join dbo.fact_clima_atual_hora cah on (dmm.municipio_id = cah.municipio_id and
												cah.dt_carga >= (select top 1 dt_inicio from dbo.etl_execucao
																 where modo = 'incremental'
																 order by dt_inicio desc))
	group by dmm.municipio_id, dmm.nome
)

select case
	when sum( case
				when ccm.linhas <> 552 then 1 -- (7 dias passados + 16 de previsão) × 24 horas
				else 0
			  end ) = 0 then 1
	else 0
end as conferencia
from conferir_completude ccm;
