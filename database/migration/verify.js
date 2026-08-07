// Post-migration verification: row counts + spot checks against the real
// target database for a given batch of dive_center_id(s).
// Usage: AQUADESK_TARGET_DB_URL=... node verify.js <id1> [id2] [...]
const { Client } = require("pg");

const DIVE_CENTER_IDS = process.argv.slice(2);
if (!DIVE_CENTER_IDS.length) {
  console.error("Usage: node verify.js <dive_center_id> [more ids...]");
  process.exit(1);
}
const TABLES = [
  "dive_centers", "users", "staff", "boats", "dive_sites", "course_rates", "rate_tiers",
  "packages", "other_charges", "equipment_rental_rates", "payment_surcharges", "exchange_rates",
  "medical_questions", "tanks", "equipment", "groups", "divers", "diver_registrations",
  "diver_staff_defaults", "visits", "activities", "payments", "deposits", "invoice_emails",
  "visit_rate_selections", "diver_notes", "schedules", "schedule_sites", "schedule_crew",
  "schedule_divers", "schedule_diver_dive_tanks", "schedule_staff_dive_tanks",
  "schedule_team_clips", "schedule_team_clip_divers", "schedule_day_diver_exclusions",
  "fuel_logs", "manifests", "expenses", "govt_fees", "join_ride_statements",
  "join_ride_records", "rental_gear_records", "staff_commission_records", "audit_logs",
];

async function main() {
  const client = new Client({ connectionString: process.env.AQUADESK_TARGET_DB_URL, ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    console.log("== row counts per table (scoped to the migrated dive centers) ==");
    for (const t of TABLES) {
      const idFilter = t === "dive_centers" ? "id" : "dive_center_id";
      const res = await client.query(`select count(*) from ${t} where ${idFilter} = any($1)`, [DIVE_CENTER_IDS]);
      console.log(`  ${t}: ${res.rows[0].count}`);
    }

    console.log("\n== spot check: dive_centers ==");
    const dc = await client.query(
      `select id, name, subscription_status, pricing_mode,
              (billing_unlock_hash is not null) as has_billing_hash,
              (owner_unlock_hash is not null) as has_owner_hash
       from dive_centers where id = any($1)`,
      [DIVE_CENTER_IDS]
    );
    console.log(dc.rows);

    console.log("\n== spot check: auth logins can be found for migrated users ==");
    const logins = await client.query(
      `select u.email, u.role, au.email as auth_email, (au.encrypted_password is not null) as has_password
       from users u join auth.users au on au.id = u.id
       where u.dive_center_id = any($1)`,
      [DIVE_CENTER_IDS]
    );
    console.log(logins.rows);

    console.log("\n== spot check: one real diver + their visit/activities/payment total reconciles ==");
    const diver = await client.query(
      `select d.id, d.first_name, d.last_name, d.certification_level
       from divers d where d.dive_center_id = any($1) limit 1`,
      [DIVE_CENTER_IDS]
    );
    if (diver.rows.length) {
      const d = diver.rows[0];
      console.log("Diver:", d);
      const visits = await client.query(`select id, visit_status, experience_type from visits where diver_id = $1`, [d.id]);
      console.log("Visits:", visits.rows);
      for (const v of visits.rows) {
        const acts = await client.query(`select count(*), sum(total) from activities where visit_id = $1`, [v.id]);
        console.log(`  Visit ${v.id}: ${acts.rows[0].count} activities, total sum ${acts.rows[0].sum}`);
        const pay = await client.query(`select total_paid, balance, grand_total_php from payments where visit_id = $1`, [v.id]);
        console.log(`  Payment:`, pay.rows[0] || "none");
      }
    }

    console.log("\n== spot check: a real trip's schedule + sites + crew + divers ==");
    const sched = await client.query(
      `select id, schedule_date, captain, closed, is_joiner, notes from schedules where dive_center_id = any($1) order by schedule_date limit 1`,
      [DIVE_CENTER_IDS]
    );
    if (sched.rows.length) {
      const s = sched.rows[0];
      console.log("Schedule:", s);
      const sites = await client.query(`select ds.site_name, ss.sort_order from schedule_sites ss join dive_sites ds on ds.id = ss.dive_site_id where ss.schedule_id = $1 order by ss.sort_order`, [s.id]);
      console.log("Sites:", sites.rows);
      const crew = await client.query(`select crew_name, sort_order from schedule_crew where schedule_id = $1 order by sort_order`, [s.id]);
      console.log("Crew:", crew.rows);
    }

    console.log("\n== ensuring the real Demo Dive Center wasn't touched ==");
    const demo = await client.query(`select id, name from dive_centers where name = 'Demo Dive Center'`);
    console.log(demo.rows);
  } finally {
    await client.end();
  }
}

main().catch((e) => { console.error(e.message); process.exit(1); });
