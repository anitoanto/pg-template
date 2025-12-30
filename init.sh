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

OUTPUT_FILE="./pgadmin-servers.json"

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

# Create volume directories
mkdir "./${POSTGRES_CONTAINER_NAME}-data"
chmod 700 "./${POSTGRES_CONTAINER_NAME}-data"
sudo chown "${HOST_UID}":"${HOST_GID}" "./${POSTGRES_CONTAINER_NAME}-data"

echo "Initialization complete."
echo "Artifacts created:"
echo "- ${OUTPUT_FILE}"
echo "- ./${POSTGRES_CONTAINER_NAME}-data/"
