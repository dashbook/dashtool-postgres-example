select
  sum(o.quantity * p.weight),
  date_trunc('month', o.date) as month
from 
  silver.inventory.fact_order as o
join
  silver.inventory.dim_product as p
on
  o.productId = p.productId
group by
  month;
