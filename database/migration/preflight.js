// Dumps every schema trap this migration tooling actually needs to know
// about before writing to the target: generated columns (can't insert),
// NOT NULL columns (must never send null, explicit or via undefined),
// every enum type's real labels, and every check constraint. Consolidates
// what was, on 2026-08-07, four separate ad hoc scripts written and then
// deleted while building the first real migration batch — costing a
// rollback-and-fix cycle for each one discovered. Re-run this before
// building/adjusting transforms.js for each new batch (Atlas, Divergems,
// Dive Nation), not just once — the target schema can change between
// sessions same as any other part of this codebase.
//
// Usage: AQUADESK_TARGET_DB_URL=... node preflight.js [table1 table2 ...]
//   No args = dump everything. Args = filter to just those tables.
const { Client } = require("pg");

async function main() {
  const filterTables = process.argv.slice(2);
  const client = new Client({ connectionString: process.env.AQUADESK_TARGET_DB_URL, ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    const tableFilter = filterTables.length ? `and table_name = any($1)` : "";
    const params = filterTables.length ? [filterTables] : [];

    console.log("=".repeat(70));
    console.log("GENERATED COLUMNS (never insert into these — target computes them)");
    console.log("=".repeat(70));
    const gen = await client.query(
      `select table_schema, table_name, column_name, generation_expression
       from information_schema.columns
       where is_generated = 'ALWAYS' and table_schema in ('public','auth') ${tableFilter}
       order by table_schema, table_name, column_name`,
      params
    );
    if (!gen.rows.length) console.log("  (none found)");
    for (const r of gen.rows) console.log(`  ${r.table_schema}.${r.table_name}.${r.column_name} = ${r.generation_expression}`);

    console.log("\n" + "=".repeat(70));
    console.log("NOT NULL COLUMNS (never send null/undefined for these, even via a spread)");
    console.log("=".repeat(70));
    const nn = await client.query(
      `select table_name, column_name, column_default
       from information_schema.columns
       where is_nullable = 'NO' and table_schema = 'public' ${tableFilter}
       order by table_name, ordinal_position`,
      params
    );
    let lastTable = null;
    for (const r of nn.rows) {
      if (r.table_name !== lastTable) { console.log(`  ${r.table_name}:`); lastTable = r.table_name; }
      console.log(`    ${r.column_name}${r.column_default ? ` (default: ${r.column_default})` : " (NO DEFAULT — every row must supply this)"}`);
    }

    console.log("\n" + "=".repeat(70));
    console.log("ENUM TYPES (exact real labels — old-schema values almost never match these verbatim)");
    console.log("=".repeat(70));
    const enums = await client.query(`
      select t.typname as enum_name, e.enumlabel as value
      from pg_type t
      join pg_enum e on t.oid = e.enumtypid
      join pg_catalog.pg_namespace n on n.oid = t.typnamespace
      where n.nspname = 'public'
      order by t.typname, e.enumsortorder
    `);
    const byEnum = {};
    for (const r of enums.rows) (byEnum[r.enum_name] ||= []).push(r.value);
    for (const [name, values] of Object.entries(byEnum)) console.log(`  ${name}: [${values.join(", ")}]`);

    console.log("\n" + "=".repeat(70));
    console.log("CHECK CONSTRAINTS (plain-text columns with enum-like allowed values)");
    console.log("=".repeat(70));
    const checks = await client.query(`
      select conname, pg_get_constraintdef(oid) as definition
      from pg_constraint
      where connamespace = 'public'::regnamespace and contype = 'c'
      order by conname
    `);
    for (const r of checks.rows) console.log(`  ${r.conname}: ${r.definition}`);

    console.log("\n" + "=".repeat(70));
    console.log("Tables that exist in target but a batch's transforms.js might not expect");
    console.log("(sanity check — compare against LIVE_DATA_MIGRATION_MAPPING.md's table list)");
    console.log("=".repeat(70));
    const allTables = await client.query(
      `select distinct table_name from information_schema.tables where table_schema = 'public' order by table_name`
    );
    console.log("  " + allTables.rows.map((r) => r.table_name).join(", "));
  } finally {
    await client.end();
  }
}
main().catch((e) => { console.error(e.message); process.exit(1); });
