# Database Project — Staging Layer (Olist Brazilian E-commerce)

Minimal Dockerised PostgreSQL project. **Phase 1 only: staging.**
The Olist dataset (9 CSVs in `Datasets/`) is landed raw — every column is stored
as TEXT in the `stage` schema, with no typing, transformation, or analysis.

## Quick start

1. Create a `.env` file in the project root (it is git-ignored — do it manually):

   ```env
   DB_HOST=db
   DB_PORT=5432
   DB_NAME=DatabaseProject
   DB_USER=postgres
   DB_PASSWORD=postgres
   ```

   > Note: `DB_NAME` is passed to the `db` container as `POSTGRES_DB`, but that
   > environment variable only takes effect when the `pgdata` volume is first
   > initialised. If the volume already exists from an earlier run with a
   > different database name, delete it (`docker compose down -v`) and re-run.

2. Start the stack and run the staging loader:

   ```bash
   docker compose run --rm app python 01_staging/load_staging.py
   ```

3. Inspect the loaded data:

   ```bash
   docker compose exec db psql -U postgres -d DatabaseProject
   ```

   ```sql
   \dt stage.
   SELECT COUNT(*) FROM stage.olist_orders_raw;
   SELECT * FROM stage.olist_order_items_raw LIMIT 10;
   ```

## Design choice: all-TEXT staging

Every column in `stage` is `TEXT`. Raw source data is landed untransformed and
no types are applied before inspection. This keeps the staging layer a faithful
copy of the CSVs (dates, numeric-looking IDs such as zip code prefixes, and
free-text columns alike), and defers all casting/typing decisions to later
phases. Surrogate keys and warehouse modelling are deliberately out of scope.

## Layout

```
docker-compose.yml        # db (postgres:17, port 5435) + app container
Dockerfile                # python:3.11-slim + requirements.txt
requirements.txt
.env                      # git-ignored; create manually
01_staging/staging_schema.sql   # stage schema + 9 raw TEXT tables + TRUNCATEs
01_staging/load_staging.py      # SQL runner + pandas loader (all 9 CSVs) + row-count check
```

Conventions preserved: one numbered folder per phase, SQL lives in `.sql`
files executed by Python runners (never embedded in strings), every script
resolves paths from its own location, lowercase snake_case everywhere.
