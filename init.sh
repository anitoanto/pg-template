#!/bin/sh
set -e

if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  SUDO=""
fi

set -a
. ./.env
set +a

cat > ./pgadmin-servers.json <<EOF
{
    "Servers": {
        "1": {
            "Name": "${POSTGRES_CONTAINER_NAME}",
            "Group": "Servers",
            "Host": "${POSTGRES_CONTAINER_NAME}",
            "Port": 5432,
            "MaintenanceDB": "postgres",
            "Username": "${POSTGRES_USER}",
            "SSLMode": "prefer"
        }
    }
}
EOF

mkdir -p "./${POSTGRES_CONTAINER_NAME}-data"
chmod 700 "./${POSTGRES_CONTAINER_NAME}-data"
$SUDO chown "${HOST_UID}:${HOST_GID}" "./${POSTGRES_CONTAINER_NAME}-data"

mkdir -p ./backups
mkdir -p ./logs

echo "Initialized:"
echo "  ./pgadmin-servers.json"
echo "  ./${POSTGRES_CONTAINER_NAME}-data/"
echo "  ./backups/"
echo "  ./logs/"
