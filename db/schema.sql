DO $$
BEGIN
   -- Create the crmadmin user if it doesn't exist
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles WHERE rolname = 'crmadmin'
   ) THEN
      CREATE ROLE crmadmin LOGIN;
   END IF;

   -- Ensure the crmadmin role has rds_iam granted
   GRANT rds_iam TO crmadmin;
END
$$;
-- Enable pgcrypto extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
-- Clients table
CREATE TABLE IF NOT EXISTS clients (
    client_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name  VARCHAR(50) NOT NULL,
    last_name   VARCHAR(50) NOT NULL,
    dob         DATE NOT NULL,
    gender      VARCHAR(20) NOT NULL,
    email       VARCHAR(100) UNIQUE NOT NULL,
    phone       VARCHAR(15) UNIQUE NOT NULL,
    address     VARCHAR(100) NOT NULL,
    city        VARCHAR(50) NOT NULL,
    state       VARCHAR(50) NOT NULL,
    country     VARCHAR(50) NOT NULL,
    postal_code VARCHAR(10) NOT NULL
);

-- Accounts table
CREATE TABLE IF NOT EXISTS accounts (
    account_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id    UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
    account_type VARCHAR(20) NOT NULL,
    status       VARCHAR(20) NOT NULL,
    opening_date DATE NOT NULL DEFAULT CURRENT_DATE,
    initial_deposit NUMERIC(12,2) NOT NULL,
    currency     VARCHAR(10) NOT NULL,
    branch_id    VARCHAR(20) NOT NULL
);
