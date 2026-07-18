#!/bin/bash

set -e
set -u

psql_args=(
    -v ON_ERROR_STOP=1
    --username "$POSTGRES_USER"
    --dbname postgres
)

if [[ -n "${POSTGRES_HOST:-}" ]]; then
    psql_args+=(--host "$POSTGRES_HOST")
fi

if [[ -n "${POSTGRES_PORT:-}" ]]; then
    psql_args+=(--port "$POSTGRES_PORT")
fi

function create_user_and_database() {
    local database=$1
    local username=$2
    local password=$3
    echo "Ensuring user '$username' and database '$database' exist"
    psql "${psql_args[@]}" \
        --set=database="$database" \
        --set=db_user="$username" \
        --set=db_password="$password" <<-'EOSQL'
        SELECT format('CREATE USER %I WITH PASSWORD %L', :'db_user', :'db_password')
        WHERE NOT EXISTS (
            SELECT FROM pg_catalog.pg_roles WHERE rolname = :'db_user'
        )\gexec

        SELECT format('ALTER USER %I WITH PASSWORD %L', :'db_user', :'db_password')\gexec

        SELECT format('CREATE DATABASE %I OWNER %I', :'database', :'db_user')
        WHERE NOT EXISTS (
            SELECT FROM pg_database WHERE datname = :'database'
        )\gexec

        ALTER DATABASE :"database" OWNER TO :"db_user";
        GRANT ALL PRIVILEGES ON DATABASE :"database" TO :"db_user";
EOSQL
    psql "${psql_args[@]}" \
        --dbname "$database" \
        --set=db_user="$username" <<-'EOSQL'
        GRANT ALL ON SCHEMA public TO :"db_user";
        ALTER SCHEMA public OWNER TO :"db_user";
EOSQL
    echo "  User '$username' and database '$database' are ready"
}

# Metadata database
create_user_and_database $METADATA_DATABASE_NAME $METADATA_DATABASE_USERNAME $METADATA_DATABASE_PASSWORD

# Celery result backend database
create_user_and_database $CELERY_BACKEND_NAME $CELERY_BACKEND_USERNAME $CELERY_BACKEND_PASSWORD

# ELT database
create_user_and_database $ELT_DATABASE_NAME $ELT_DATABASE_USERNAME $ELT_DATABASE_PASSWORD

echo "All databases and users created successfully"
