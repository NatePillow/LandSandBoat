# Install Planning

Working draft of the eventual README Installation section. Not user-facing yet —
the Docker packaging (compose stack, release bundle, preconfigured Ashita
profile) doesn't exist yet, so `<placeholders>` mark what still needs to be
built/finalized before this moves into the README.

---

Two halves: a **server** you run locally (via Docker) and the **client** (retail FFXI + Ashita v3 with the addon suite). Do the server first, then the client.

## Prerequisites

- **A retail Final Fantasy XI install.** The game's data files can't be distributed — you must own and install FFXI yourself (Steam or PlayOnline).
- **Docker Desktop.** The server (game servers + database) runs as containers, so you don't install or configure MariaDB by hand.
- **Ashita v3.** The client launcher/injector that loads the addon suite.

## 1. Server (Docker)

1. Download the release bundle (`<release-url>`) and unzip it.
2. *(Optional)* Edit `.env` — the defaults are fine for local single-player; you generally don't need to change anything.
3. From the bundle directory, bring it up:
   ```
   docker compose up -d
   ```
   The **first** run initializes the database (schema + data) and starts the map / world / search servers. This takes a few minutes; wait until the containers report healthy before launching the client.

The server now listens on `localhost`. Leave it running while you play; `docker compose down` stops it, and your characters/data persist between runs.

## 2. Client (Ashita v3)

1. Install **Ashita v3** and point it at your retail FFXI installation.
2. Copy this project's `addons/` into your Ashita `addons` directory.
3. Point Ashita at the local server and enable the addons:
   - Set the server address to `127.0.0.1`.
   - Add the addons to Ashita's boot load list.

   *(A preconfigured Ashita profile with the server address and addon list already set is provided in the release bundle — drop it in rather than editing by hand.)*

## 3. First launch

Launch the game through Ashita and connect to the private server. On the login screen you create your account and first character right there — the same flow as any private server — then log in and you're in Vana'diel.

## Backup & restore

A complete save is **two** things — back up both. The database alone is not enough.

- **Database** — all character state: inventory, jobs/levels, key items, quest/mission progress, gil, appearance, AH listings.
- **`singleplayer/config/`** — your bot setups and gear: `alliance/`, `food/`, `lot/` configs, the `equip/` gear XMLs, and `auction/items.csv`. These are files on disk, *not* in the database. Restore only the DB and your bot rosters and gear sets are gone.

**Backing up** (Docker):

```
# database -> save.sql
docker compose exec -T database mariadb-dump -uroot -p<rootpw> xidb > save.sql

# config files -> archive
tar czf config-backup.tgz singleplayer/config
```

**Restoring:**

```
# database: import into the running container (or drop save.sql into the DB
# init dir on a fresh volume, same as the initial dump)
docker compose exec -T database mariadb -uroot -p<rootpw> xidb < save.sql

# config: extract back over singleplayer/config
tar xzf config-backup.tgz
```

> Planned (`#198`): a single "backup" command that bundles the DB dump + `singleplayer/config/` into one archive, so users don't have to remember both halves.
