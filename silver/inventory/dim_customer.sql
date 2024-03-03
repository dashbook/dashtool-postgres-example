select 
  id as customerId,
  sha256(email) as uuid 
from 
  bronze.inventory.customers;
