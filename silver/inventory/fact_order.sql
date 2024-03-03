select 
  id as orderId,
  order_date as date,
  quantity,
  purchaser as customerId,
  product_id as productId 
from 
  bronze.inventory.orders;
