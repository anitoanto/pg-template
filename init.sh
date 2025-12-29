#!/bin/sh

# Exit on error
set -e

# Load environment variables from .env
if [ -f .env ]; then
    # Export variables defined in .env
    export $(grep -v '^#' .env | xargs)
else
    echo ".env file not found"
    exit 1
fi

# Output file
OUTPUT_FILE=".servers.json"

cat > "$OUTPUT_FILE" <<EOF
{
    "Servers": {
        "1": {
            "Name": "${POSTGRES_CONTAINER_NAME}",
            "Group": "Servers",
            "Host": "${POSTGRES_CONTAINER_NAME}",
            "Port": ${POSTGRES_PORT},
            "MaintenanceDB": "postgres",
            "Username": "${POSTGRES_USER}",
            "SSLMode": "prefer"
        }
    }
}
EOF

# Set permissions for pgAdmin
chmod 600 "$OUTPUT_FILE"

echo "pgAdmin servers configuration written to $OUTPUT_FILE"
echo "Permissions set to 600 (rw-------)"
echo ""

# Creating volume directories
mkdir "./${POSTGRES_CONTAINER_NAME}-data"
mkdir "./${POSTGRES_CONTAINER_NAME}-pgadmin-data"
echo "Volume directories created:"
echo "./${POSTGRES_CONTAINER_NAME}-data"
echo "./${POSTGRES_CONTAINER_NAME}-pgadmin-data"

# Set permissions for volume directories
chmod 700 "./${POSTGRES_CONTAINER_NAME}-data"
chmod 700 "./${POSTGRES_CONTAINER_NAME}-pgadmin-data"
echo "Permissions set to 700 (rwx------)"
echo ""

echo "Initialization complete."
