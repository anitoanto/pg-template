#!/bin/sh

# Exit on error
set -e

if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

# -------------------------
# Load environment safely
# -------------------------
set -a
. ./.env
set +a


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
mkdir -p "./${POSTGRES_CONTAINER_NAME}-data"
chmod 700 "./${POSTGRES_CONTAINER_NAME}-data"
$SUDO chown "${HOST_UID}":"${HOST_GID}" "./${POSTGRES_CONTAINER_NAME}-data"

mkdir -p "./backups"

echo "Initialization complete."
echo "Artifacts created:"
echo "- ${OUTPUT_FILE}"
echo "- ./${POSTGRES_CONTAINER_NAME}-data/"
echo "- ./backups/"
