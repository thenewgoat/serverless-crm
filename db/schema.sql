SELECT current_database(), current_user, current_schema();

GRANT rds_iam TO :"DB_USER";

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
GRANT CONNECT ON DATABASE :"DB_NAME" TO :"DB_USER";
GRANT USAGE ON SCHEMA public TO :"DB_USER";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"DB_USER";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"DB_USER";

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"DB_USER";

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO :"DB_USER";


-- Clients table;
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

-- Accounts table;
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

-- Verification: list out key objects;
SELECT 'Current DB:' AS label, current_database()
UNION ALL
SELECT 'Current User:', current_user
UNION ALL
SELECT 'Current Schema:', current_schema();

-- Verify that tables exist;
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('clients', 'accounts')
ORDER BY table_name;

-- Show columns for clients table;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'clients'
ORDER BY ordinal_position;

-- Show columns for accounts table;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'accounts'
ORDER BY ordinal_position;
