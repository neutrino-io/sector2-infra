#!/bin/bash

# Superset Configuration Verification Script
# This script helps verify that all configuration files are properly set up

set -e

echo "======================================================================"
echo "Superset Configuration Verification"
echo "======================================================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

# Check if file exists
check_file() {
    if [ -f "$1" ]; then
        print_pass "File exists: $1"
        return 0
    else
        print_fail "File missing: $1"
        return 1
    fi
}

# Check if directory exists
check_dir() {
    if [ -d "$1" ]; then
        print_pass "Directory exists: $1"
        return 0
    else
        print_fail "Directory missing: $1"
        return 1
    fi
}

echo "1. Checking Required Files"
echo "──────────────────────────────────────────────────────────────────────"

check_file "railway.toml"
check_file "Dockerfile"
check_file "config/superset_config.py"
check_file "config/superset_init.sh"
check_file ".env.example"
check_file ".gitignore"
check_file "clickhouse_railway_engine.py"

echo ""
echo "2. Checking Documentation Files"
echo "──────────────────────────────────────────────────────────────────────"

check_file "README.md"
check_file "DEPLOYMENT.md"
check_file "QUICKSTART.md"
check_file "CHANGES.md"

echo ""
echo "3. Checking Railway Configuration"
echo "──────────────────────────────────────────────────────────────────────"

if [ -f "railway.toml" ]; then
    # Check for required environment variables in railway.toml
    if grep -q "SQLALCHEMY_DATABASE_URI" railway.toml; then
        print_pass "SQLALCHEMY_DATABASE_URI configured"
    else
        print_fail "SQLALCHEMY_DATABASE_URI not found in railway.toml"
    fi

    if grep -q "ADMIN_USERNAME" railway.toml; then
        print_pass "ADMIN_USERNAME configured"
    else
        print_fail "ADMIN_USERNAME not found in railway.toml"
    fi

    if grep -q "ADMIN_EMAIL" railway.toml; then
        print_pass "ADMIN_EMAIL configured"
    else
        print_fail "ADMIN_EMAIL not found in railway.toml"
    fi

    if grep -q "SECRET_KEY" railway.toml; then
        print_pass "SECRET_KEY configured"
    else
        print_fail "SECRET_KEY not found in railway.toml"
    fi

    if grep -q "SUPERSET_SECRET_KEY" railway.toml; then
        print_pass "SUPERSET_SECRET_KEY configured"
    else
        print_fail "SUPERSET_SECRET_KEY not found in railway.toml"
    fi

    # Check volume configuration
    if grep -q "deploy.volumes" railway.toml; then
        print_pass "Volume configuration found"
        if grep -q "/app/superset_home" railway.toml; then
            print_pass "Volume mount path configured"
        else
            print_warn "Volume mount path may not be correct"
        fi
    else
        print_fail "Volume configuration not found"
    fi
fi

echo ""
echo "4. Checking Superset Configuration"
echo "──────────────────────────────────────────────────────────────────────"

if [ -f "config/superset_config.py" ]; then
    # Check PostgreSQL configuration
    if grep -q "SQLALCHEMY_DATABASE_URI" config/superset_config.py; then
        print_pass "PostgreSQL configuration found"
    else
        print_fail "PostgreSQL configuration not found"
    fi

    # Check ClickHouse configuration
    if grep -q "clickhouse" config/superset_config.py; then
        print_pass "ClickHouse configuration preserved"
    else
        print_warn "ClickHouse configuration may be missing"
    fi

    # Check persistent storage directories
    if grep -q "DATA_DIR" config/superset_config.py; then
        print_pass "Data directory configured"
    else
        print_fail "Data directory not configured"
    fi

    if grep -q "UPLOAD_FOLDER" config/superset_config.py; then
        print_pass "Upload folder configured"
    else
        print_fail "Upload folder not configured"
    fi

    # Check secret key handling
    if grep -q "SUPERSET_SECRET_KEY" config/superset_config.py; then
        print_pass "Secret key handling configured"
    else
        print_warn "Secret key handling may need review"
    fi
fi

echo ""
echo "5. Checking Dockerfile Configuration"
echo "──────────────────────────────────────────────────────────────────────"

if [ -f "Dockerfile" ]; then
    # Check base image
    if grep -q "FROM apache/superset" Dockerfile; then
        print_pass "Base image: apache/superset"
    else
        print_fail "Base image not found"
    fi

    # Check PostgreSQL driver
    if grep -q "psycopg2-binary" Dockerfile; then
        print_pass "PostgreSQL driver installed"
    else
        print_fail "PostgreSQL driver not found"
    fi

    # Check ClickHouse drivers
    if grep -q "clickhouse-connect" Dockerfile; then
        print_pass "ClickHouse HTTP driver installed"
    else
        print_fail "ClickHouse HTTP driver not found"
    fi

    if grep -q "clickhouse-driver" Dockerfile; then
        print_pass "ClickHouse native driver installed"
    else
        print_fail "ClickHouse native driver not found"
    fi

    # Check volume declaration
    if grep -q "VOLUME" Dockerfile; then
        print_pass "Volume declaration found"
    else
        print_warn "Volume declaration may be missing"
    fi

    # Check directory creation
    if grep -q "mkdir -p /app/superset_home" Dockerfile; then
        print_pass "Persistent directories created"
    else
        print_fail "Persistent directory creation not found"
    fi
fi

echo ""
echo "6. Checking Initialization Script"
echo "──────────────────────────────────────────────────────────────────────"

if [ -f "config/superset_init.sh" ]; then
    # Check if executable
    if [ -x "config/superset_init.sh" ]; then
        print_pass "Init script is executable"
    else
        print_warn "Init script may not be executable (will be set in Dockerfile)"
    fi

    # Check database connectivity test
    if grep -q "Testing PostgreSQL" config/superset_init.sh; then
        print_pass "Database connectivity test found"
    else
        print_fail "Database connectivity test not found"
    fi

    # Check error handling
    if grep -q "set -e" config/superset_init.sh; then
        print_pass "Error handling enabled"
    else
        print_warn "Error handling may not be enabled"
    fi

    # Check admin user creation
    if grep -q "superset fab create-admin" config/superset_init.sh; then
        print_pass "Admin user creation found"
    else
        print_fail "Admin user creation not found"
    fi
fi

echo ""
echo "7. Security Checks"
echo "──────────────────────────────────────────────────────────────────────"

# Check if .env exists (should not be committed)
if [ -f ".env" ]; then
    print_warn ".env file exists - ensure it's in .gitignore and not committed"
else
    print_pass "No .env file (use .env.example as template)"
fi

# Check .gitignore
if [ -f ".gitignore" ]; then
    if grep -q ".env" .gitignore; then
        print_pass ".env is in .gitignore"
    else
        print_fail ".env not found in .gitignore"
    fi
fi

# Check for default/example passwords in railway.toml
if [ -f "railway.toml" ]; then
    if grep -q "ADMIN_PASSWORD.*=.*\".*\"" railway.toml; then
        print_warn "Review admin password in railway.toml - ensure it's secure"
    fi

    # Check if using example secret keys
    if grep -q "SECRET_KEY.*=.*\"REDACTED_SECRET_KEY\"" railway.toml; then
        print_warn "Using example SECRET_KEY - generate new key for production"
    fi
fi

echo ""
echo "8. Checking ClickHouse Compatibility"
echo "──────────────────────────────────────────────────────────────────────"

if [ -f "clickhouse_railway_engine.py" ]; then
    print_pass "ClickHouse Railway engine exists"
else
    print_warn "ClickHouse Railway engine not found"
fi

if [ -f "config/superset_config.py" ]; then
    if grep -q "register.*clickhouse" config/superset_config.py; then
        print_pass "ClickHouse dialect registration found"
    else
        print_fail "ClickHouse dialect registration not found"
    fi
fi

echo ""
echo "======================================================================"
echo "Verification Summary"
echo "======================================================================"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ Configuration verification passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review and update credentials in railway.toml"
    echo "  2. Generate new secret keys:"
    echo "     python3 -c \"import secrets; print(secrets.token_urlsafe(32))\""
    echo "  3. Update SQLALCHEMY_DATABASE_URI with your PostgreSQL connection"
    echo "  4. Deploy to Railway:"
    echo "     railway up"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Configuration verification failed with $FAILED error(s)${NC}"
    echo ""
    echo "Please fix the errors above before deploying."
    echo "See DEPLOYMENT.md for detailed configuration instructions."
    echo ""
    exit 1
fi
