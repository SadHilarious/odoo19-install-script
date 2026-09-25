# Odoo 19 with Docker Compose

> [!CAUTION]
> **For educational and research purposes only**
> Do not use this repo in a production environment
> [Purchase a valid license](https://www.odoo.com/pricing)

> [!NOTE]
> Must run on Linux host (WSL is ok)
- `docker-compose.yml`: postgresdb and odoo itself
- `odoo-control.sh`: script to start, stop, or delete those docker container/volume and set the admin password on startup
- `reset-odoo-password.sh`: changes the password of an existing user

## Enabled applications

On a fresh database, the Compose `init` service installs these Odoo 19 applications:

| Application | Module | Source |
| --- | --- | --- |
| Accounting | `accountant` | Addon directory mounted at `/mnt/extra-addons` |
| Sales | `sale_management` | [Odoo 19 manifest](https://github.com/odoo/odoo/blob/19.0/addons/sale_management/__manifest__.py) |
| Purchase | `purchase` | [Odoo 19 manifest](https://github.com/odoo/odoo/blob/19.0/addons/purchase/__manifest__.py) |
| Inventory | `stock` | [Odoo 19 manifest](https://github.com/odoo/odoo/blob/19.0/addons/stock/__manifest__.py) |

Odoo automatically installs required dependencies and eligible integration modules. Sales depends on the underlying `sale` module. See [Odoo's `-i` option](https://www.odoo.com/documentation/19.0/developer/reference/cli.html#cmdoption-odoo-bin-i) for installing multiple modules

## Prerequisites

Install [Docker](https://docs.docker.com/engine/install) depend on your Linux distro

Clone this repo
```bash
git clone https://github.com/SadHilarious/odoo19-install-script
```

Clone **totally legit repo**
```bash
git clone https://github.com/chandsharma/odoo19-enterprise-crack /opt/docker-data/odoo19-enterprise-crack
```

Edit `ADDON_DIR` near the top of `docker/odoo-control.sh` to the absolute path:

```bash
# Right here !
ADDON_DIR="/opt/docker-data/odoo19-enterprise-crack"
```

Check the directory before deploying:

```bash
cat /opt/docker-data/odoo19-enterprise-crack/accountant/__manifest__.py
```

The control script checks this path and passes `ADDON_DIR` to Compose. Both `init` and `web` mount it read only on `/mnt/extra-addons`. If you run `docker compose` instead of using the script, set `ADDON_DIR` in your environment; otherwise compose file uses the default path in `docker-compose.yml`

## Deploy 

Run this command:
```bash
cd docker
chmod +x odoo-control.sh reset-odoo-password.sh
./odoo-control.sh
```

The menu offers these options:

| Option | Action |
| --- | --- |
| `1` | Start PostgreSQL and Odoo; on the first run, initialize the database and install the enabled applications. |
| `2` | Stop the containers while preserving their data |
| `3` | Prompt for `DELETE`, stop the stack even if it is running, then remove its containers and **both odoo/postgres data volumes**. The script reports an error if removal fails |
| `0` | Exit script |

You can also run `./odoo-control.sh start`, `./odoo-control.sh stop`, or `./odoo-control.sh delete` directly. <br>
After deleting the data, choose `1` or `start` to create a new database. Deletion does not remove the host addon directory or the external network (`cloudflared_net`).<br>
Initializing the database and installing these apps may take several minutes.

## Install enabled applications on an existing database

Changing the one-time `init` command alone will not install newly added applications on an existing database. Install missing apps **without deleting either volume**. From the `docker/` directory, stop only the web service, run a one-off Odoo installer with the same configuration and addon mount, then start the web service again:

```bash
docker compose -p odoo19fresh stop web
ADDON_DIR="/opt/docker-data/odoo19-enterprise-crack" docker compose -p odoo19fresh run --rm --no-deps init \
  odoo --db_host=db --db_port=5432 --db_user=odoo --db_password=odoo \
  --database=odoo --data-dir=/var/lib/odoo --without-demo=True --no-http \
  -i sale_management,purchase,stock --stop-after-init &&
docker compose -p odoo19fresh start web
```

Set `ADDON_DIR` in the command above to the same Linux host path configured in `odoo-control.sh`. The command installs any listed modules that are not already installed; existing data remains in place. Confirm all three apps are installed with:

```bash
docker compose -p odoo19fresh exec db psql -U odoo -d odoo -c \
  "SELECT name, state FROM ir_module_module WHERE name IN ('sale_management', 'purchase', 'stock') ORDER BY name;"
```

**Admin account:** Each time the control script starts Odoo, it warns you and creates or resets the Odoo user to `admin / 123456789`<br>
This default password is easy to guess; set `ODOO_ADMIN_PASSWORD` before running the script to use a different value. If you change the password in Odoo, the next `start` will reset it to the configured values

Odoo is available at `http://localhost:8069`. To check installation progress and service status:

```bash
docker compose -p odoo19fresh ps -a
docker compose -p odoo19fresh logs --tail=100 init web
```

The script uses the `odoo19fresh` project for every operation. When running Compose manually, use `-p odoo19fresh` for both `up` **and** `down` to avoid operating on a different project

## Check the addon mount and change a password

Check the addon directory mounted in the container:

```bash
docker inspect odoo19-fresh-web --format '{{range .Mounts}}{{if eq .Destination "/mnt/extra-addons"}}{{.Source}} -> {{.Destination}}{{end}}{{end}}'
```

Change an existing user's password (the script prompts for a new password without displaying what you type):

```bash
./reset-odoo-password.sh admin
```

The database is initialized without demo data, so `demo@demo.com` does not exist by default. If you change the admin password this way, the next `./odoo-control.sh start` will reset it again

