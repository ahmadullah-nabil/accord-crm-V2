# Accord CRM V1 — SQL Package (Final)

This is the single source of truth for the Accord CRM V1 database. It is designed to run, in order, against a **completely empty, brand-new Supabase project** with zero manual edits.

---

## 1. Execution Order

Run the 12 migration files in `supabase/migrations/` in numeric order. Each file is idempotent where practical (`CREATE TABLE IF NOT EXISTS`, `ON CONFLICT DO NOTHING`), but they are **not** designed to be re-run out of order or skipped.

| # | File | What it builds |
|---|---|---|
| 001 | `001_auth_foundation.sql` | Extensions, `users` table, core RLS helper functions (stubs that get redefined in 002), `auth.users` sync trigger |
| 002 | `002_rbac.sql` | `roles`, `permissions`, `role_permissions`, `user_roles`. Seeds 4 roles and 19 permissions. Redefines the RBAC helper functions with their real implementation |
| 003 | `003_lookup_tables.sql` | 10 lookup tables (stages, statuses, priorities, sources, industries, products, modules, won/loss reasons, contact roles), fully seeded |
| 004 | `004_core_deals.sql` | `deals`, `deal_modules`, `deal_contacts`, plus the audit trail (`stage_logs`, `assignment_logs`, `deal_events`) and `can_access_deal()` — the central RLS helper used everywhere downstream |
| 005 | `005_customers.sql` | `customers`, `customer_modules`. Auto-creates a customer when a deal is marked Won |
| 006 | `006_tasks.sql` | `tasks`, with follow-up source linkage and overdue tracking |
| 007 | `007_meetings.sql` | `meetings`, with contact linkage and outcome tracking |
| 008 | `008_documents.sql` | `notes`, `documents` (metadata only — files live in Supabase Storage) |
| 009 | `009_notifications.sql` | `deal_timeline` (the unified activity feed, 13 event types) and `notifications` (in-app notification system) |
| 010 | `010_seed.sql` | Pre-provisions **one** Admin user profile and assigns the Admin role. No transactional sample data |
| 011 | `011_views.sql` | 15 reporting/dashboard views, all RLS-inheriting |
| 012 | `012_rpc_functions.sql` | RPC functions the frontend calls directly: `rpc_change_deal_stage`, `rpc_reassign_deal`, `rpc_mark_deal_won`, `rpc_mark_deal_lost`, `rpc_complete_task`. Final `verify_full_install()` check |

---

## 2. Required Supabase Extensions

Both are declared and enabled automatically by `001_auth_foundation.sql` — no manual Dashboard step needed:

- **`pgcrypto`** — provides `gen_random_uuid()`, used as the default for every primary key
- **`pg_trgm`** — trigram indexes for fast partial-text search on company names, contact names, etc.

No other extensions are required. `btree_gist` is **not** needed — the one `EXCLUDE` constraint in this schema (`deal_stages`, ensuring only one Won stage and one Lost stage) uses `EXCLUDE USING btree`, which PostgreSQL supports natively for scalar equality without any extension.

---

## 3. How to Run This

### Option A — Supabase CLI (recommended)

```bash
# From your project root, with the Supabase CLI installed and linked:
supabase link --project-ref <your-project-ref>

# Copy this package's migrations into your project's migrations folder
cp accord-crm-sql-final/supabase/migrations/*.sql supabase/migrations/

# Push all migrations in order
supabase db push
```

### Option B — Supabase Dashboard SQL Editor

Open **SQL Editor** in your Supabase Dashboard and run each file's contents, in order, 001 through 012. Wait for each to complete successfully before running the next.

---

## 4. Expected Result After Each Migration

After each file runs, you can confirm it landed correctly using the verification helper defined at the end of that file:

| After running... | Run this | You should see |
|---|---|---|
| 002 | `SELECT * FROM public.verify_rbac_seed();` | `roles_count` = 4/4 passed, `permissions_count` = 19/19 passed, `admin_has_all_permissions` passed |
| 003 | `SELECT * FROM public.verify_lookup_seed();` | 10 rows, one per lookup table, with non-zero row counts |
| 004 | `SELECT * FROM public.verify_core_deals_seed();` | All 8 checks `passed = true` |
| 010 | `SELECT * FROM public.verify_seed_data();` | `admin_user_provisioned` and `admin_role_assigned` both `passed = true`. `admin_auth_user_id_pending` should be `true` until you complete step 5 below |
| 012 (final) | `SELECT * FROM public.verify_full_install() WHERE passed = false;` | **Zero rows returned.** If this returns any rows, something did not install correctly — do not proceed to frontend development until this query returns empty |

---

## 5. Creating the First Admin Account

`010_seed.sql` pre-provisions a `public.users` row for `admin@accordtechnologies.example` with the Admin role already assigned — but `auth_user_id` is `NULL` because no matching Supabase Auth account exists yet. Two steps connect them:

### Step 1 — Edit the seed email (recommended, before running 010)

Before running `010_seed.sql`, open it and replace `admin@accordtechnologies.example` with the real email address of your first administrator, in **both** places it appears (the `INSERT INTO public.users` and the `INSERT INTO public.user_roles` query).

If you've already run it with the placeholder email, you can instead update the row directly:

```sql
UPDATE public.users
SET email = 'your-real-admin-email@yourcompany.com'
WHERE email = 'admin@accordtechnologies.example';
```

### Step 2 — Create the matching Supabase Auth account

In the Supabase Dashboard, go to **Authentication → Users → Add User**, and create a user with the **exact same email address** used in step 1. You can either:
- Set a password directly (uncheck "Send invite"), or
- Send a magic-link / invite email and let them set their own password

### Step 3 — Automatic linking

The moment that Supabase Auth user is created, the `handle_new_auth_user()` trigger (from `001_auth_foundation.sql`) fires automatically on `auth.users` insert. It looks for a `public.users` row with a matching email and `auth_user_id IS NULL`, and links them by setting `auth_user_id`.

### Step 4 — Confirm the link

```sql
SELECT id, full_name, email, auth_user_id, is_active
FROM public.users
WHERE email = 'your-real-admin-email@yourcompany.com';
```

`auth_user_id` should now be populated (not `NULL`).

---

## 6. How to Assign the Admin Role (to additional users)

The first Admin is seeded automatically by step 5 above. To make any **other** existing user an Admin (or any other role):

```sql
INSERT INTO public.user_roles (user_id, role_id, assigned_by, is_active)
SELECT
    u.id,
    r.id,
    (SELECT id FROM public.users WHERE email = 'your-real-admin-email@yourcompany.com'),  -- who is granting this
    true
FROM   public.users u
CROSS JOIN public.roles r
WHERE  u.email = 'the-persons-email@yourcompany.com'
AND    r.name  = 'Admin'   -- or 'Partner' / 'Manager' / 'Executive'
ON CONFLICT (user_id, role_id) DO NOTHING;
```

A user can hold more than one role simultaneously — their effective permission set is the **union** of all permissions across all their active roles (see `has_permission()` in `002_rbac.sql`).

To remove a role from a user (soft-deactivate the assignment, never hard-delete):

```sql
UPDATE public.user_roles
SET    is_active = false
WHERE  user_id = (SELECT id FROM public.users WHERE email = 'someone@yourcompany.com')
AND    role_id = (SELECT id FROM public.roles WHERE name = 'Manager');
```

---

## 7. How to Test Login

Once steps 5–6 are complete:

1. Point your frontend's `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` at this Supabase project.
2. Go to your application's `/login` page.
3. Sign in with the email and password you set in Step 2 of Section 5.
4. On successful login, your frontend should resolve the session, fetch the `public.users` profile via `auth_user_id = auth.uid()`, and resolve the permission map via the `user_roles → roles → role_permissions → permissions` join — all of which are backed by the functions and seed data in this package.

### Quick manual SQL test (without a frontend)

You can simulate the permission resolution your frontend will perform, run directly in the SQL Editor while impersonating no one (these functions use `auth.uid()` internally, which only resolves inside an actual authenticated request — so this check from the SQL Editor will show `NULL`/`false` since the SQL Editor runs as the `postgres` superuser, not as an authenticated app user). To genuinely test RLS and permission resolution end-to-end, the login must happen through your application (or `supabase.auth.signInWithPassword()` from any Supabase client), not through the SQL Editor.

To verify the underlying data is correct without a live session:

```sql
-- Confirms the Admin's permission set resolves correctly when their user_id is supplied directly
SELECT p.name
FROM   public.user_roles ur
JOIN   public.roles r ON r.id = ur.role_id
JOIN   public.role_permissions rp ON rp.role_id = r.id
JOIN   public.permissions p ON p.id = rp.permission_id
WHERE  ur.user_id = (SELECT id FROM public.users WHERE email = 'your-real-admin-email@yourcompany.com')
AND    ur.is_active = true
ORDER  BY p.name;
```

This should return all 19 permission names for an Admin.

---

## 8. A Note on the RPC Functions (012_rpc_functions.sql)

Stage changes and deal reassignments **cannot** be performed via a plain `UPDATE` through the Supabase REST/JS client (`supabase.from('deals').update(...)`). The audit-trail triggers in `004_core_deals.sql` require a mandatory remark to be set via a PostgreSQL session-local parameter (`SET LOCAL crm.stage_change_reason = '...'`) in the **same transaction** as the `UPDATE` — something a single REST call cannot do.

Instead, the frontend must call these as RPCs:

```ts
const { data, error } = await supabase.rpc('rpc_change_deal_stage', {
  p_deal_id: dealId,
  p_new_stage_id: newStageId,
  p_remark: 'Customer confirmed budget approval',
});
```

The same applies to `rpc_reassign_deal`, `rpc_mark_deal_won`, `rpc_mark_deal_lost`, and `rpc_complete_task`. All five are documented with full parameter lists inside `012_rpc_functions.sql`.

---

## 9. Corrections Applied in This Package

Every fix identified during the original debugging session has been built into this package from the start — there is nothing left to patch:

- **`system_user` reserved keyword** — never used as an identifier anywhere; the seed CTE in `002_rbac.sql` is named `seed_actor`
- **`NEW` referenced inside an RLS `WITH CHECK` clause** — never done anywhere; OLD/NEW comparisons (self-deactivation guard, system-role protection) live in dedicated `BEFORE UPDATE` triggers
- **`has_permission()` only checking the single highest-priority role** — fixed to union permissions across *all* active role assignments for a user
- **Dependency order** — verified programmatically: every `REFERENCES`, every `EXECUTE FUNCTION`, every `ENABLE ROW LEVEL SECURITY` target resolves to something created earlier in the same file or an earlier-numbered file
- **Foreign key ordering** — all 31 tables created in strict dependency order; zero forward references
- **AFTER trigger `NEW.xxx :=` mutation bug** — `won_at`/`won_by`/`lost_at`/`lost_by` are stamped via explicit `UPDATE` statements inside the AFTER triggers, never via direct `NEW` field assignment (which PostgreSQL silently ignores in AFTER triggers)
- **`SECURITY DEFINER` functions** — every helper and RPC function explicitly sets `SET search_path = public` to prevent search-path hijacking, and every RPC in `012_rpc_functions.sql` re-implements its own authorization check (since `SECURITY DEFINER` bypasses RLS)
- **`auth.uid()` lookups** — centralised in exactly one place (`get_current_crm_user_id()` in `001_auth_foundation.sql`); every other function calls that, never `auth.uid()` directly
- **Window function nested inside an aggregate** (`v_pipeline_performance`) — `LEAD()` is computed in a separate CTE (`stage_periods`) before `AVG()` aggregates over the result in a second query level
- **UUID seed references** — all seed data uses `WHERE name = '...'` lookups against already-inserted rows, never hardcoded UUIDs
- **`role_permissions` / `user_roles` inserts** — built via `JOIN`-based CTEs resolving names to UUIDs at insert time, with `ON CONFLICT DO NOTHING` for safe re-runs
- **Verification helpers** — every migration ends with a `verify_*()` function; `012_rpc_functions.sql` ends with `verify_full_install()`, which checks all 12 migrations in one query

---

## 10. File Structure

```
accord-crm-sql-final.zip
└── supabase/
    └── migrations/
        ├── 001_auth_foundation.sql
        ├── 002_rbac.sql
        ├── 003_lookup_tables.sql
        ├── 004_core_deals.sql
        ├── 005_customers.sql
        ├── 006_tasks.sql
        ├── 007_meetings.sql
        ├── 008_documents.sql
        ├── 009_notifications.sql
        ├── 010_seed.sql
        ├── 011_views.sql
        └── 012_rpc_functions.sql
└── README.md   (this file)
```
