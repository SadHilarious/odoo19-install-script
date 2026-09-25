#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
compose_file="${ODOO_COMPOSE_FILE:-$script_dir/docker-compose.yml}"
project="${ODOO_PROJECT:-odoo19fresh}"
container="${ODOO_CONTAINER:-odoo19-fresh-web}"

# Right here !
ADDON_DIR="/opt/docker-data/odoo19-enterprise-crack"

addons_path="$ADDON_DIR"
network="${ODOO_NETWORK:-cloudflared_net}"
admin_password="${ODOO_ADMIN_PASSWORD:-123456789}"
max_attempts="${ODOO_BOOTSTRAP_RETRIES:-120}"

compose() {
    docker compose -f "$compose_file" -p "$project" "$@"
}

require_runtime() {
    if ! command -v docker >/dev/null 2>&1; then
        printf '%s\n' "Docker CLI is not installed." >&2
        exit 1
    fi
    if ! docker compose version >/dev/null 2>&1; then
        printf '%s\n' "Docker Compose v2 is not available." >&2
        exit 1
    fi
    if [[ ! -f "$compose_file" ]]; then
        printf 'Compose file not found: %s\n' "$compose_file" >&2
        exit 1
    fi
}

ensure_addons_path() {
    if [[ ! -f "$addons_path/accountant/__manifest__.py" ]]; then
        printf 'Accounting addon not found under: %s\n' "$addons_path" >&2
        printf 'Edit ADDON_DIR in this script to set the host addon directory.\n' >&2
        exit 1
    fi
}

ensure_network() {
    if ! docker network inspect "$network" >/dev/null 2>&1; then
        docker network create "$network" >/dev/null
    fi
}

bootstrap_admin() {
    local attempt
    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        if docker exec -i \
            -e ODOO_ADMIN_PASSWORD="$admin_password" \
            "$container" odoo shell \
            --db_host=db \
            --db_port=5432 \
            --db_user=odoo \
            --db_password=odoo \
            --database=odoo \
            --data-dir=/var/lib/odoo \
            --http-interface=127.0.0.1 >/dev/null 2>&1 <<'PY'
import os

password = os.environ["ODOO_ADMIN_PASSWORD"]
users = env["res.users"].sudo().with_context(active_test=False)
admin = users.search([("login", "=", "admin")], limit=1)

if admin:
    admin.write({"password": password, "active": True})
else:
    company = env["res.company"].sudo().search([], limit=1)
    if not company:
        raise RuntimeError("No company found")

    group_user = env.ref("base.group_user")
    group_system = env.ref("base.group_system")
    partner = env["res.partner"].sudo().create({
        "name": "Administrator",
        "email": "admin@example.com",
        "company_id": company.id,
    })
    admin = users.create({
        "partner_id": partner.id,
        "login": "admin",
        "password": password,
        "company_id": company.id,
        "company_ids": [(6, 0, company.ids)],
        "group_ids": [(6, 0, [group_user.id, group_system.id])],
    })

env.cr.commit()
PY
        then
            return 0
        fi
        sleep 5
    done

    printf '%s\n' "Could not initialize the Odoo database." >&2
    compose logs --tail=100 init web >&2 || true
    return 1
}

start_server() {
    require_runtime
    ensure_addons_path
    ensure_network
    export ADDON_DIR="$addons_path"
    printf 'WARNING: Odoo admin account will be reset to admin / %s on every start.\n' "$admin_password" >&2

    compose up -d --remove-orphans
    bootstrap_admin
    printf 'Odoo is running at http://127.0.0.1:8069\n'
    printf 'Admin login: admin\n'
}

stop_server() {
    require_runtime
    compose stop
    printf '%s\n' "Odoo containers stopped; volumes were preserved."
}

delete_server() {
    local confirmation
    local volume
    local remaining_volumes

    require_runtime
    printf '%s\n' "WARNING: This will stop the running Odoo stack and permanently delete its Odoo and PostgreSQL data." >&2
    if ! read -r -p "Type DELETE to erase all Odoo data: " confirmation; then
        printf '%s\n' "Deletion cancelled." >&2
        exit 1
    fi
    if [[ "$confirmation" != "DELETE" ]]; then
        printf '%s\n' "Deletion cancelled." >&2
        exit 0
    fi

    if ! compose down --volumes --remove-orphans --timeout 30; then
        printf '%s\n' "Failed to stop the stack and remove its volumes. Check Docker output; data may still exist." >&2
        return 1
    fi

    for volume in odoo19_fresh_v2_odoo_data odoo19_fresh_v2_postgres_data; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            if ! docker volume rm "$volume"; then
                printf 'Could not remove volume %s; it may still be in use.\n' "$volume" >&2
                return 1
            fi
        fi
    done

    if ! remaining_volumes="$(docker volume ls --format '{{.Name}}')"; then
        printf '%s\n' "Could not verify whether the data volumes were deleted." >&2
        return 1
    fi
    for volume in odoo19_fresh_v2_odoo_data odoo19_fresh_v2_postgres_data; do
        if grep -Fxq "$volume" <<<"$remaining_volumes"; then
            printf 'Data volume still exists: %s\n' "$volume" >&2
            return 1
        fi
    done

    printf '%s\n' "Odoo containers and data volumes were deleted."
}

print_menu() {
    printf '%s\n' \
        "1. Start Odoo" \
        "2. Stop Odoo" \
        "3. Delete all Odoo data" \
        "0. Exit"
}

main() {
    local choice

    if [[ $# -gt 0 ]]; then
        case "$1" in
            start) start_server ;;
            stop) stop_server ;;
            delete) delete_server ;;
            *) printf 'Usage: %s [start|stop|delete]\n' "$0" >&2; exit 1 ;;
        esac
        return
    fi

    while true; do
        print_menu
        if ! read -r -p "Choose an option: " choice; then
            exit 1
        fi
        case "$choice" in
            1) start_server ;;
            2) stop_server ;;
            3) delete_server ;;
            0) exit 0 ;;
            *) printf '%s\n' "Invalid option." ;;
        esac
    done
}

main "$@"
