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

-- PLATFORM_AUTOMATION: the guinea pig's least-privilege trial (docs/decisions.md,
-- "Least privilege for the guinea pig"). It owns what it creates and can grant on
-- its own objects without MANAGE GRANTS, but it holds nothing account-wide beyond
-- CREATE DATABASE / CREATE WAREHOUSE / CREATE ROLE. SVC_TERRAFORM keeps
-- ACCOUNTADMIN as its default role above; the guinea pig's Terraform provider
-- alias switches to this role explicitly (envs/*/versions.tf).
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS PLATFORM_AUTOMATION
  COMMENT = 'Least-privilege trial for automation identities. Currently used by the guinea pig only.';

GRANT ROLE PLATFORM_AUTOMATION TO ROLE SYSADMIN;
GRANT ROLE PLATFORM_AUTOMATION TO USER SVC_TERRAFORM;

GRANT CREATE DATABASE ON ACCOUNT TO ROLE PLATFORM_AUTOMATION;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE PLATFORM_AUTOMATION;

-- Needed to create GUINEA_PIG_READER (snowflake_account_role.reader). Granting
-- that role on to SYSADMIN afterwards needs no separate privilege - owning a
-- role is enough to grant it, the same rule that lets PLATFORM_AUTOMATION grant
-- on the objects it owns without MANAGE GRANTS.
GRANT CREATE ROLE ON ACCOUNT TO ROLE PLATFORM_AUTOMATION;

-- Resource monitor creation is exclusively an ACCOUNTADMIN privilege - it cannot
-- be delegated even via a custom role grant. So it is created here, once, and
-- Terraform (modules/snowflake-guinea-pig) only references it by name and manages
-- its thresholds via ALTER, which MODIFY below permits.
CREATE RESOURCE MONITOR IF NOT EXISTS RM_GUINEA_PIG
  WITH
    CREDIT_QUOTA = 1
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
      ON 75  PERCENT DO NOTIFY
      ON 90  PERCENT DO NOTIFY
      ON 95  PERCENT DO SUSPEND
      ON 100 PERCENT DO SUSPEND_IMMEDIATE;

GRANT MODIFY ON RESOURCE MONITOR RM_GUINEA_PIG TO ROLE PLATFORM_AUTOMATION;

-- Verify: should return one row with TYPE = SERVICE and a non-null RSA key.
SHOW USERS LIKE 'SVC_TERRAFORM';

-- Verify: PLATFORM_AUTOMATION should show CREATE DATABASE, CREATE WAREHOUSE,
-- CREATE ROLE, and (via the resource monitor grant) MODIFY on RM_GUINEA_PIG.
SHOW GRANTS TO ROLE PLATFORM_AUTOMATION;
