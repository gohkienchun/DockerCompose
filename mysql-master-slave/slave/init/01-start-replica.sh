#!/bin/sh
set -eu

echo "Waiting for master ${MASTER_HOST}:${MASTER_PORT}..."
ok=0
attempts=0
while [ "$ok" -lt 3 ]; do
  attempts=$((attempts + 1))
  if [ "$attempts" -gt 90 ]; then
    echo "Master ${MASTER_HOST}:${MASTER_PORT} did not stay ready." >&2
    exit 1
  fi
  if mysql --connect-timeout=5 -h"${MASTER_HOST}" -P"${MASTER_PORT}" -u"${REPL_USER}" -p"${REPL_PASSWORD}" --get-server-public-key -e "SELECT 1" >/dev/null 2>&1; then
    ok=$((ok + 1))
  else
    ok=0
  fi
  sleep 2
done

mysql --protocol=socket -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='${MASTER_HOST}',
  SOURCE_PORT=${MASTER_PORT},
  SOURCE_USER='${REPL_USER}',
  SOURCE_PASSWORD='${REPL_PASSWORD}',
  SOURCE_AUTO_POSITION=1,
  GET_SOURCE_PUBLIC_KEY=1;
SET PERSIST read_only = ON;
SET PERSIST super_read_only = ON;
SQL
