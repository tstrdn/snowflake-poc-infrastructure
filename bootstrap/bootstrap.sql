-- Bootstrap for one Snowflake account.
--
-- Run this once per account (development, test, production) as ACCOUNTADMIN,
-- before the first Terraform apply against that account.
--
-- It creates the minimum that Terraform cannot create for itself: the service
-- user Terraform authenticates as, the restricted role it runs under, and the
-- resource monitors, whose creation Snowflake reserves for ACCOUNTADMIN alone.
-- Everything else - databases, schemas, warehouses, the role hierarchy, the dbt
-- service user - is managed as code in this repository.
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
  DEFAULT_ROLE = PLATFORM_AUTOMATION
  RSA_PUBLIC_KEY = '<PUBLIC_KEY>';

-- Re-running with a new key rotates it. CREATE USER IF NOT EXISTS will not
-- update an existing user, so rotation is explicit:
-- ALTER USER SVC_TERRAFORM SET RSA_PUBLIC_KEY = '<NEW_PUBLIC_KEY>';
--
-- Same reason DEFAULT_ROLE above is a no-op on an account where SVC_TERRAFORM
-- already exists (decision 12 changed it from ACCOUNTADMIN). Run once, by hand,
-- against any such account:
-- ALTER USER SVC_TERRAFORM SET DEFAULT_ROLE = PLATFORM_AUTOMATION;

-- PLATFORM_AUTOMATION is the only role SVC_TERRAFORM holds. It is deliberately
-- NOT granted ACCOUNTADMIN: it owns what it creates and grants on its own objects
-- by virtue of that ownership, but holds nothing account-wide beyond the four
-- CREATE privileges below - and specifically not MANAGE GRANTS, which would let
-- it grant any privilege on any object and put it back within reach of
-- ACCOUNTADMIN. Reasoning in full: docs/decisions.md, decisions 11 and 12.
CREATE ROLE IF NOT EXISTS PLATFORM_AUTOMATION
  COMMENT = 'Terraform automation. Owns the platform objects; holds no account-wide grant privilege.';

GRANT ROLE PLATFORM_AUTOMATION TO ROLE SYSADMIN;
GRANT ROLE PLATFORM_AUTOMATION TO USER SVC_TERRAFORM;

GRANT CREATE DATABASE ON ACCOUNT TO ROLE PLATFORM_AUTOMATION;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE PLATFORM_AUTOMATION;

-- The access and functional roles of module "rbac", plus GUINEA_PIG_READER.
-- Granting those roles on to SYSADMIN afterwards needs no separate privilege -
-- owning a role is enough to grant it.
GRANT CREATE ROLE ON ACCOUNT TO ROLE PLATFORM_AUTOMATION;

-- SVC_DBT (snowflake_service_user.dbt in module "rbac"). SVC_TERRAFORM itself
-- is created above by hand, because Terraform cannot create the identity it
-- authenticates as.
GRANT CREATE USER ON ACCOUNT TO ROLE PLATFORM_AUTOMATION;

-- Resource monitors ----------------------------------------------------------
--
-- Resource monitor creation is exclusively an ACCOUNTADMIN privilege - it cannot
-- be delegated even via a custom role grant. So both are created here, once, and
-- Terraform only references them by name; MODIFY below lets it manage their
-- thresholds afterwards.
--
-- The cost of this: RM_ENV's credit quota is no longer a Terraform variable per
-- environment. Set it per account when running this script - the agreed values
-- are dev 6, tst 5, prd 10 - and adjust with ALTER RESOURCE MONITOR rather than
-- by re-running.
CREATE RESOURCE MONITOR IF NOT EXISTS RM_ENV
  WITH
    CREDIT_QUOTA = 6  -- dev 6 / tst 5 / prd 10
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
      ON 75  PERCENT DO NOTIFY
      ON 90  PERCENT DO NOTIFY
      ON 95  PERCENT DO SUSPEND
      ON 100 PERCENT DO SUSPEND_IMMEDIATE;

GRANT MODIFY ON RESOURCE MONITOR RM_ENV TO ROLE PLATFORM_AUTOMATION;

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
-- CREATE ROLE, CREATE USER, and MODIFY on RM_ENV and RM_GUINEA_PIG. It must NOT
-- show MANAGE GRANTS, and SVC_TERRAFORM must NOT hold ACCOUNTADMIN.
SHOW GRANTS TO ROLE PLATFORM_AUTOMATION;
SHOW GRANTS TO USER SVC_TERRAFORM;
