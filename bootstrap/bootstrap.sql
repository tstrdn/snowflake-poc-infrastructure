-- Bootstrap for one Snowflake account.
--
-- Run this once per account (development, test, production) as ACCOUNTADMIN,
-- before the first Terraform apply against that account.
--
-- It creates exactly one thing: the service user Terraform authenticates as.
-- Everything else - roles, grants, warehouses, databases, the dbt service user
-- - is managed as code in this repository. This is the single hand-made
-- credential per account, and it exists only because Terraform cannot create
-- the identity it uses to connect.
--
-- Usage:
--   1. ./generate_keypair.sh SVC_TERRAFORM <env>
--   2. Replace <PUBLIC_KEY> below with the contents of
--      keys/<env>/SVC_TERRAFORM.pub.oneline
--   3. Run in a Snowsight worksheet as ACCOUNTADMIN.
--
-- The public key is not a secret. The matching .p8 private key goes into the
-- HCP Terraform workspace as the sensitive Terraform variable
-- snowflake_private_key, and nowhere else.

USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS SVC_TERRAFORM
  TYPE = SERVICE
  COMMENT = 'Terraform platform automation. Bootstrapped by hand; not in Terraform state.'
  DEFAULT_ROLE = ACCOUNTADMIN
  RSA_PUBLIC_KEY = '<PUBLIC_KEY>';

-- Re-running with a new key rotates it. CREATE USER IF NOT EXISTS will not
-- update an existing user, so rotation is explicit:
-- ALTER USER SVC_TERRAFORM SET RSA_PUBLIC_KEY = '<NEW_PUBLIC_KEY>';

-- Terraform manages account-level objects (databases, warehouses, resource
-- monitors) and the full role hierarchy including role creation and grants.
-- That needs both SYSADMIN and SECURITYADMIN, plus CREATE DATABASE and
-- CREATE WAREHOUSE at account level. ACCOUNTADMIN covers all of it.
--
-- Narrowing this is the first thing to do beyond a proof of concept: grant
-- SYSADMIN and SECURITYADMIN plus the specific account-level privileges
-- instead, so the automation identity is not the most powerful role in the
-- account. Left broad here so the PoC bootstrap is a single reliable step.
GRANT ROLE ACCOUNTADMIN TO USER SVC_TERRAFORM;

-- Verify: should return one row with TYPE = SERVICE and a non-null RSA key.
SHOW USERS LIKE 'SVC_TERRAFORM';
