# Design Decisions: Azure Monitor Observability Demo Lab

> **Last updated:** 2026-07-15  
> **Sources:** `.squad/decisions/inbox/trinity-scaffold-infra.md`, `.squad/decisions/inbox/tank-tables-dcr.md`, `.squad/decisions/inbox/mouse-kql-schema.md`

---

## Decision 1 — Logs Ingestion API over Legacy HTTP Data Collector API

**Decision:** Use the modern **Logs Ingestion API** (azure-monitor-ingestion SDK, DCE + DCR pipeline) rather than the legacy HTTP Data Collector API (`/api/logs?api-version=2016-04-01`).

**Why:**
- The HTTP Data Collector API is deprecated. Microsoft's guidance is to migrate to the Logs Ingestion API.
- The Logs Ingestion API enforces a **typed column schema** defined in DCR/table Bicep — columns have explicit `real`, `long`, `int`, `boolean`, `string`, `datetime` types, preventing silent type coercion.
- `transformKql` in the DCR provides a future-proof transform layer: `source` today means pass-through, but complex projections, enrichment, or PII-scrubbing can be added without changing the generator or the table schema.
- The SDK (`azure-monitor-ingestion`) handles batching, retry, and auth transparently.
- The ingestion path is **auditable via DCR** — the DCR's `immutableId` is the stable contract between generator and workspace. Rotating the workspace or table does not require changing generator code.

---

## Decision 2 — One DCR and One Custom Table per Scenario

**Decision:** Five DCRs, five custom tables — one of each per scenario. No shared/multiplex DCR.

**Why:**
- **Schema isolation:** Each scenario's column set is distinct. A single multiplex table would require nullable columns for every scenario, making KQL queries verbose and error-prone.
- **Independent alerting:** Alert rules target a single table. Per-scenario tables mean alert KQL is simpler and faster (no `where Scenario ==` filter on a union table).
- **Granular RBAC:** If a future reader needs access to only one scenario's data, per-table access control is straightforward.
- **Idempotent Bicep loop:** The `[for scenario in scenarioConfigs: {...}]` pattern in `main.bicep` keeps the module count predictable and the code DRY without a shared resource.

---

## Decision 3 — Monitoring Metrics Publisher Least-Privilege on DCRs

**Decision:** Grant the generator's principal the built-in **Monitoring Metrics Publisher** role (`3913510d-42f4-4e42-8a64-420c390055eb`) scoped to each DCR and to the DCE — not Contributor or Owner on the Resource Group.

**Why:**
- The Logs Ingestion API only requires this single role. It authorises the principal to POST data to the DCE endpoint and reference a specific DCR — nothing else.
- Granting broad Contributor access to the RG would allow the generator process (or a compromised credential) to delete/modify infrastructure, a significant blast radius.
- The role assignment is parameterised (`principalId` in `main.bicep`). Passing an empty string skips the assignment, which is correct for dry-run and CI scenarios where no Azure connection is needed.
- This aligns with the Azure Well-Architected Framework security pillar (least-privilege identity).

---

## Decision 4 — Deterministic Naming via `uniqueString`

**Decision:** All resource names are derived from `take(uniqueString(subscription().id, namePrefix), 6)`.

**Why:**
- **Idempotency:** Re-running `az deployment sub create` with the same subscription and `namePrefix` produces identical resource names. No orphaned duplicate resources.
- **Global uniqueness:** Log Analytics workspace names and DCE names must be globally unique within Azure. `uniqueString` provides a collision-resistant 6-char hex suffix without requiring a random seed file.
- **Predictability for scripts:** `scripts/deploy` can compute the same suffix independently if needed (though in practice it reads Bicep outputs).
- **No user friction:** Workshop attendees do not need to choose unique names.

---

## Decision 5 — `transformKql = 'source'` (Pass-Through Transform)

**Decision:** Every DCR uses `transformKql = 'source'` — the KQL identity transform — rather than a projection or column-rename expression.

**Why:**
- The generator emits records whose column names already match the custom table schema exactly (PascalCase, per `mouse-kql-schema.md`). No renaming or type coercion is needed at the DCR layer.
- `source` is the most performant transform (no KQL execution overhead in the ingestion path).
- Keeping the transform trivial makes the lab easier to understand: the schema is fully defined in the table columns and in the generator models — not hidden in a DCR expression.
- If a future scenario requires field enrichment (e.g., adding a `LabVersion` column from a DCR parameter), it can be added to `transformKql` without changing the generator payload.

---

## Decision 6 — Custom-Table Schema Choices

**Decision:** All schemas use PascalCase column names with explicit types (`real`, `long`, `int`, `boolean`, `string`, `datetime`). No `_s` / `_d` / `_b` suffixes.

**Why:**
- DCR-based custom tables (Logs Ingestion API) preserve declared types — columns are stored and returned as their declared type, not as dynamically-typed `string`/`real`. The legacy HTTP Data Collector API appended type suffixes (`_s`, `_d`); these are absent with the new API.
- PascalCase matches Azure Monitor's built-in table conventions (`TimeGenerated`, `ResourceId`, etc.), making cross-table `union` queries natural.
- `bool` in `mouse-kql-schema.md` maps to `boolean` in Bicep/DCR (Tank confirmed this in `tank-tables-dcr.md`). The Python generator uses native `bool`, and the `azure-monitor-ingestion` SDK serialises it correctly.
- `long` is chosen for counters that could exceed `int` range (e.g., `NetworkInBytes`, `StorageUsedMB`, `RequestCount`). `real` is chosen for percentages and durations.
- `TimeGenerated` uses `datetime` and is always UTC — required by Log Analytics for time-range queries and retention policies.

---

## Decision 7 — `southcentralus` as Default Region

**Decision:** `location` defaults to `'southcentralus'` in `main.bicep` and `main.bicepparam`.

**Why:**
- Workshop author (@dmauser) is US-based; South Central US is the nearest Azure region with full availability of all required services (Log Analytics, DCE, DCR, Monitor Workbooks, Scheduled-Query Alerts).
- `southcentralus` supports Availability Zones, ensuring the workspace and DCE can be high-availability if the lab is extended to HA patterns.
- Any Azure region can be used by overriding the `location` parameter — the default is a convenience, not a constraint.

---

## Decision 8 — `config/lab.env` as Output Contract

**Decision:** Bicep outputs are written to `config/lab.env` by `scripts/deploy`. `config/lab.env` is gitignored; `config/lab.env.example` is committed.

**Why:**
- The generator, smoke-test scripts, and any future tooling read a single authoritative file. No Bicep output is hardcoded in script logic.
- Gitignoring `lab.env` prevents accidental commit of subscription IDs, DCR immutable IDs, and DCE endpoint URLs, which — while not secrets — should not be in source control.
- The `.example` file doubles as a contract document: every consumer (Dozer, Mouse scripts, Ghost tests) can see the full variable set without deploying.

---

## Decision 9 — Subscription-Scoped Bicep Entry Point

**Decision:** `infra/main.bicep` uses `targetScope = 'subscription'` and creates the Resource Group as its first module.

**Why:**
- A subscription-scoped deployment allows the lab to be fully bootstrapped with a single `az deployment sub create` command — no pre-existing Resource Group required.
- Workshop attendees need only `az login` + Contributor on their subscription. No prior portal steps.
- The RG module output (`rgModule.outputs.name`) is used as the `scope` for all subsequent resource-group-scoped modules, making the dependency graph explicit in Bicep.
