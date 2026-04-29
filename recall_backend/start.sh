#!/bin/bash
# Production startup script for Render deployment
# This script ensures database is ready, runs migrations, and starts the server

set -e  # Exit on any error

echo "=========================================="
echo "  ReCall Backend - Production Startup"
echo "=========================================="

# =============================================================================
# 1. VALIDATE REQUIRED ENVIRONMENT VARIABLES
# =============================================================================

echo ""
echo "Step 1: Validating environment variables..."

# Check required variables
REQUIRED_VARS=("DATABASE_URL" "JWT_SECRET_KEY" "OPENAI_API_KEY")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "❌ ERROR: Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Please set these variables in Render dashboard before deploying."
    exit 1
fi

echo "✅ All required environment variables are set"

# =============================================================================
# 2. WAIT FOR DATABASE TO BE READY
# =============================================================================

echo ""
echo "Step 2: Waiting for database to be ready..."

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
    echo "❌ ERROR: DATABASE_URL environment variable is not set!"
    echo ""
    echo "Please add DATABASE_URL in Render Dashboard:"
    echo "  1. Go to rekall-backend service → Environment tab"
    echo "  2. Click 'Add Environment Variable'"
    echo "  3. Click 'Add from Database'"
    echo "  4. Select 'rekall-db' database"
    echo "  5. Property: 'Connection String' (Internal)"
    echo "  6. Save and redeploy"
    exit 1
fi

# Extract database connection details from DATABASE_URL
# Format: postgresql://user:password@host:port/database
DB_HOST=$(echo $DATABASE_URL | sed -n 's/.*@\(.*\):.*/\1/p')
DB_PORT=$(echo $DATABASE_URL | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')

if [ -z "$DB_PORT" ]; then
    DB_PORT=5432  # Default PostgreSQL port
fi

# Validate extraction worked
if [ -z "$DB_HOST" ]; then
    echo "❌ ERROR: Could not extract database host from DATABASE_URL"
    echo ""
    echo "DATABASE_URL format: $DATABASE_URL"
    echo ""
    echo "Expected format: postgresql://user:password@host:port/database"
    echo ""
    echo "Please check DATABASE_URL in Render Environment tab"
    exit 1
fi

echo "Database host: $DB_HOST"
echo "Database port: $DB_PORT"

# Wait for database to accept connections (max 180 seconds / 3 minutes)
MAX_RETRIES=180
RETRY_COUNT=0

echo "Attempting to connect to database..."
echo "If this takes too long, check:"
echo "  1. DATABASE_URL is set correctly in Render Environment tab"
echo "  2. Database status is 'Available' (not 'Creating')"
echo "  3. Both services are in the same region (singapore)"

while ! nc -z $DB_HOST $DB_PORT 2>/dev/null; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "❌ ERROR: Database not available after $MAX_RETRIES seconds"
        echo "Database URL: $DATABASE_URL"
        echo "Extracted host: $DB_HOST"
        echo "Extracted port: $DB_PORT"
        exit 1
    fi
    # Only print every 10 seconds to reduce log spam
    if [ $((RETRY_COUNT % 10)) -eq 0 ]; then
        echo "⏳ Still waiting for database... ($RETRY_COUNT/$MAX_RETRIES seconds)"
    fi
    sleep 1
done

echo "✅ Database is ready"

# =============================================================================
# 3. ENABLE PGVECTOR EXTENSION
# =============================================================================

echo ""
echo "Step 3: Enabling pgvector extension..."

# Enable pgvector extension (needed for semantic search)
if ! psql "$DATABASE_URL" -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>&1; then
    echo "⚠️  Warning: Failed to create pgvector extension"
    echo "   Migration will continue, but semantic search may not work"
    echo "   To enable manually: psql \$DATABASE_URL -c 'CREATE EXTENSION vector;'"
fi

# Verify extension is loaded
EXTENSION_CHECK=$(psql "$DATABASE_URL" -t -A -c "SELECT 1 FROM pg_extension WHERE extname='vector';" 2>/dev/null || echo "0")

if [ "$EXTENSION_CHECK" = "1" ]; then
    echo "✅ pgvector extension enabled"
else
    echo "⚠️  Warning: Could not verify pgvector extension"
    echo "   Migration will continue, but semantic search may not work"
    echo "   To enable manually: psql \$DATABASE_URL -c 'CREATE EXTENSION vector;'"
fi

# =============================================================================
# 4. RUN DATABASE MIGRATIONS
# =============================================================================

echo ""
echo "Step 4: Running database migrations..."

# Run Alembic migrations
alembic upgrade head

if [ $? -eq 0 ]; then
    echo "✅ Migrations completed successfully"
else
    echo "❌ ERROR: Migrations failed"
    exit 1
fi

# =============================================================================
# 5. START UVICORN WEB SERVER
# =============================================================================

echo ""
echo "Step 5: Starting uvicorn server..."

# Debug: Check current directory and structure
echo ""
echo "Current directory: $(pwd)"
echo "Directory contents:"
ls -la
echo ""
echo "Checking for main.py:"
ls -la main.py || echo "main.py not found in current directory!"
echo ""
echo "Python path:"
python -c "import sys; print('\n'.join(sys.path))"
echo ""

# Test import before starting server
echo "Testing app import..."
python -c "import sys; sys.path.insert(0, '.'); from main import app; print('✅ App imported successfully')" || {
    echo "❌ ERROR: Failed to import main"
    echo ""
    echo "Checking current directory:"
    ls -la
    echo ""
    echo "Checking if main.py exists:"
    test -f main.py && echo "✅ main.py exists" || echo "❌ main.py NOT FOUND"
    echo ""
    echo "Python import error:"
    python -c "import sys; sys.path.insert(0, '.'); from main import app" 2>&1
    exit 1
}

echo ""
echo "Configuration:"
echo "  - Host: ${HOST:-0.0.0.0}"
echo "  - Port: ${PORT:-10000}"
echo "  - Workers: 2"
echo "  - Keep-alive: 65 seconds"
echo "  - Log level: info"
echo ""
echo "=========================================="
echo "  Server starting..."
echo "=========================================="

# Start uvicorn with production settings
exec uvicorn main:app \
    --host ${HOST:-0.0.0.0} \
    --port ${PORT:-10000} \
    --workers 2 \
    --timeout-keep-alive 65 \
    --log-level info
