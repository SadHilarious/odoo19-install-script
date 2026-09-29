#!/usr/bin/env bash
set -euo pipefail

container="${ODOO_CONTAINER:-odoo19-fresh-web}"
login="${1:-}"

if [[ -z "$login" ]]; then
    read -r -p "Odoo user login: " login
fi

if [[ -z "$login" ]]; then
    printf '%s\n' "Login is required." >&2
    exit 1
fi

if [[ -n "${ODOO_NEW_PASSWORD:-}" ]]; then
    password="$ODOO_NEW_PASSWORD"
elif [[ -t 0 ]]; then
    read -r -s -p "New password: " password
    printf '\n'
else
    printf '%s\n' "Set ODOO_NEW_PASSWORD or run this script interactively." >&2
    exit 1
fi

if [[ -z "$password" ]]; then
    printf '%s\n' "Password is required." >&2
    exit 1
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)" != "true" ]]; then
    printf 'Container is not running: %s\n' "$container" >&2
    exit 1
fi

docker exec -i \
    -e ODOO_RESET_LOGIN="$login" \
    -e ODOO_RESET_PASSWORD="$password" \
    "$container" odoo shell \
    --db_host=db \
    --db_port=5432 \
    --db_user=odoo \
    --db_password=odoo \
    --database=odoo \
    --data-dir=/var/lib/odoo \
    --http-interface=127.0.0.1 <<'PY'
import os

login = os.environ["ODOO_RESET_LOGIN"]
password = os.environ["ODOO_RESET_PASSWORD"]
users = env["res.users"].sudo().with_context(active_test=False)
user = users.search([("login", "=ilike", login)], limit=1)

if not user:
    raise RuntimeError(f"User not found: {login}")

user.write({"password": password})
env.cr.commit()
print(f"Password reset for Odoo user: {user.login}")
PY
