// AquaDesk live-data migration ETL driver.
// Usage:
//   node etl.js --dry-run <export_dir>          (validate only, no DB touched)
//   AQUADESK_TARGET_DB_URL=... node etl.js <export_dir>   (real insert)
//
// <export_dir> is a directory of per-table .json files produced by
// parse_export.js from a Supabase SQL Editor export — see
// migration_exports/parse_export.js and the batch1_test_accounts example.
//
// See LIVE_DATA_MIGRATION_MAPPING.md and LIVE_APP_SCHEMA_SNAPSHOT.md at the
// repo root for the reasoning behind every transform in transforms.js.

const fs = require("fs");
const path = require("path");
const T = require("./transforms");

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const exportDir = args.find((a) => !a.startsWith("--"));

if (!exportDir) {
  console.error("Usage: node etl.js [--dry-run] <export_dir>");
  process.exit(1);
}

function load(table) {
  const p = path.join(exportDir, `${table}.json`);
  if (!fs.existsSync(p)) return [];
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

function reportSkips(table, skipped) {
  if (!skipped.length) return;
  console.log(`  [WARN] ${table}: ${skipped.length} row(s) skipped:`);
  for (const s of skipped.slice(0, 10)) {
    console.log(`    - ${s.reason} (id=${s.row?.id ?? "?"})`);
  }
  if (skipped.length > 10) console.log(`    ... and ${skipped.length - 10} more`);
}

async function main() {
  const plan = []; // [{ table, columns/jsonColumns metadata not needed here, rows }]
  const warnings = [];

  // ---- raw loads --------------------------------------------------------
  const rawDiveCenters = load("dive_centers");
  const rawUsers = load("users");
  const rawAuthUsers = load("auth_users");
  const rawAuthIdentities = load("auth_identities");
  const rawStaff = load("staff");
  const rawCourseRates = load("course_rates");
  const rawRateTiers = load("rate_tiers");
  const rawPackages = load("packages");
  const rawDiveSites = load("dive_sites");
  const rawOtherCharges = load("other_charges");
  const rawEquipmentRentalRates = load("equipment_rental_rates");
  const rawPaymentSurcharges = load("payment_surcharges");
  const rawExchangeRates = load("exchange_rates");
  const rawMedicalQuestions = load("medical_questions");
  const rawTanks = load("tanks");
  const rawEquipment = load("equipment");
  const rawBoats = load("boats");
  const rawGroups = load("groups");
  const rawDivers = load("divers");
  const rawDiverRegistrations = load("diver_registrations");
  const rawDiverStaffDefaults = load("diver_staff_defaults");
  const rawVisits = load("visits");
  const rawActivities = load("activities");
  const rawPayments = load("payments");
  const rawDeposits = load("deposits");
  const rawInvoiceEmails = load("invoice_emails");
  const rawVisitRateSelections = load("visit_rate_selections");
  const rawDiverNotes = load("diver_notes");
  const rawSchedules = load("schedules");
  const rawScheduleDivers = load("schedule_divers");
  const rawScheduleTeamClips = load("schedule_team_clips");
  const rawScheduleTeamClipDivers = load("schedule_team_clip_divers");
  const rawScheduleDayDiverExclusions = load("schedule_day_diver_exclusions");
  const rawFuelLogs = load("fuel_logs");
  const rawManifests = load("manifests");
  const rawExpenses = load("expenses");
  const rawGovtFees = load("govt_fees");
  const rawJoinRideStatements = load("join_ride_statements");
  const rawJoinRideRecords = load("join_ride_records");
  const rawRentalGearRecords = load("rental_gear_records");
  const rawStaffCommissionRecords = load("staff_commission_records");
  const rawAuditLogs = load("audit_logs");

  // ---- transform, in dependency order -----------------------------------

  const step = (label, table, result) => {
    reportSkips(label, result.skipped || []);
    console.log(`  ${label}: ${(result.rows || result).length} row(s)`);
    plan.push({ table, rows: result.rows || result });
    return result.rows || result;
  };

  console.log("== auth ==");
  step("auth.users", "auth.users", T.authUsers(rawAuthUsers));
  step("auth.identities", "auth.identities", T.authIdentities(rawAuthIdentities));

  console.log("== tenant root ==");
  const diveCentersRes = T.diveCenters(rawDiveCenters);
  reportSkips("dive_centers", diveCentersRes.skipped);
  console.log(`  dive_centers: ${diveCentersRes.rows.length} row(s)`);
  plan.push({
    table: "dive_centers",
    rows: diveCentersRes.rows,
    // billing_password / owner_password rehash needs the ORIGINAL raw
    // plaintext value, matched by id, applied via crypt() in SQL — done
    // as a dedicated step so the generic inserter never sees plaintext
    passwordRehash: rawDiveCenters.map((r) => ({
      id: r.id,
      billing_password: r.billing_password,
      owner_password: r.owner_password,
    })),
    // waiver_content_updated_by references `users`, inserted later —
    // backfilled once the users step below has run
    waiverUpdatedByBackfill: rawDiveCenters
      .filter((r) => r.waiver_content_updated_by)
      .map((r) => ({ id: r.id, waiver_content_updated_by: r.waiver_content_updated_by })),
  });

  console.log("== users / platform admin ==");
  step("users", "users", T.users(rawUsers));
  step("platform_admins", "platform_admins", T.platformAdmins(rawUsers));

  console.log("== config tables ==");
  const staffRows = step("staff", "staff", T.staff(rawStaff));
  step("course_rates", "course_rates", T.courseRates(rawCourseRates));
  step("rate_tiers", "rate_tiers", T.rateTiers(rawRateTiers));
  step("packages", "packages", T.packages(rawPackages));
  const diveSitesRows = step("dive_sites", "dive_sites", T.diveSites(rawDiveSites));
  step("other_charges", "other_charges", T.otherCharges(rawOtherCharges));
  step("equipment_rental_rates", "equipment_rental_rates", T.equipmentRentalRates(rawEquipmentRentalRates));
  step("payment_surcharges", "payment_surcharges", T.paymentSurcharges(rawPaymentSurcharges));
  step("exchange_rates", "exchange_rates", T.exchangeRates(rawExchangeRates));
  step("medical_questions", "medical_questions", T.medicalQuestions(rawMedicalQuestions));
  step("tanks", "tanks", T.tanks(rawTanks));
  step("equipment", "equipment", T.equipment(rawEquipment));
  step("boats", "boats", T.boats(rawBoats));
  const groupsRows = step("groups", "groups", T.groups(rawGroups));
  const validGroupIds = new Set(groupsRows.map((g) => g.id));

  console.log("== divers ==");
  let diversRows = step("divers", "divers", T.divers(rawDivers));
  {
    let danglingCount = 0;
    diversRows = diversRows.map((d) => {
      if (d.group_id && !validGroupIds.has(d.group_id)) {
        danglingCount++;
        return { ...d, group_id: null };
      }
      return d;
    });
    if (danglingCount) {
      warnings.push(`divers: ${danglingCount} row(s) referenced a group_id not present in the exported groups (orphaned in the live DB itself) — nulled out`);
      plan[plan.length - 1].rows = diversRows; // divers was the just-pushed plan entry
    }
  }
  const diversById = new Map(diversRows.map((d) => [d.id, d]));
  const diversByName = new Map(
    diversRows.map((d) => [`${d.first_name || ""} ${d.last_name || ""}`.trim().toLowerCase(), d.id])
  );
  {
    const regRows = step("diver_registrations", "diver_registrations", T.diverRegistrations(rawDiverRegistrations, diversById));
    let danglingCount = 0;
    const sanitized = regRows.map((r) => {
      if (r.group_id && !validGroupIds.has(r.group_id)) {
        danglingCount++;
        return { ...r, group_id: null };
      }
      return r;
    });
    if (danglingCount) {
      warnings.push(`diver_registrations: ${danglingCount} row(s) referenced a group_id not present in the exported groups — nulled out`);
      plan[plan.length - 1].rows = sanitized;
    }
  }
  step("diver_staff_defaults", "diver_staff_defaults", T.diverStaffDefaults(rawDiverStaffDefaults));

  console.log("== scheduling ==");
  // Must run before activities — activities.schedule_id references schedules.id
  const { schedules, scheduleSites, scheduleCrew, skipped: schedSkipped } = T.schedulesAndChildren(rawSchedules);
  reportSkips("schedules", schedSkipped);
  console.log(`  schedules: ${schedules.length} row(s)`);
  plan.push({ table: "schedules", rows: schedules });

  // resolve schedule_sites.site_name -> dive_sites.id (same dive center)
  const siteIdByKey = new Map(diveSitesRows.map((s) => [`${s.dive_center_id}::${s.site_name}`, s.id]));
  // Real live-DB data quality: some child rows reference a schedule_id
  // whose parent schedule no longer exists (deleted schedule, orphaned
  // children — same class of issue as the divers.group_id finding above).
  // Every table below that references schedules.id gets validated against
  // the actually-migrated set, not assumed clean.
  const validScheduleIds = new Set(schedules.map((s) => s.id));

  const resolvedSites = [];
  let unresolvedSiteCount = 0;
  for (const s of scheduleSites) {
    if (!validScheduleIds.has(s.schedule_id)) { unresolvedSiteCount++; continue; }
    const id = siteIdByKey.get(`${s.dive_center_id}::${s.site_name}`);
    if (!id) {
      warnings.push(`schedule_sites: no dive_sites match for "${s.site_name}" (schedule ${s.schedule_id}) — skipped`);
      continue;
    }
    resolvedSites.push({ dive_center_id: s.dive_center_id, schedule_id: s.schedule_id, dive_site_id: id, sort_order: s.sort_order });
  }
  if (unresolvedSiteCount) warnings.push(`schedule_sites: ${unresolvedSiteCount} row(s) referenced a schedule not present in the migrated schedules (orphaned in the live DB) — skipped`);
  console.log(`  schedule_sites: ${resolvedSites.length} row(s)`);
  plan.push({ table: "schedule_sites", rows: resolvedSites });

  const validScheduleCrew = scheduleCrew.filter((c) => validScheduleIds.has(c.schedule_id));
  if (validScheduleCrew.length !== scheduleCrew.length) warnings.push(`schedule_crew: ${scheduleCrew.length - validScheduleCrew.length} row(s) referenced a missing schedule — skipped`);
  console.log(`  schedule_crew: ${validScheduleCrew.length} row(s)`);
  plan.push({ table: "schedule_crew", rows: validScheduleCrew });

  const { divers: schedDiversRaw, diveTanks: diveTanksRaw, skipped: schedDiversSkipped } = T.scheduleDivers(rawScheduleDivers);
  reportSkips("schedule_divers", schedDiversSkipped);
  const schedDivers = schedDiversRaw.filter((d) => validScheduleIds.has(d.schedule_id));
  if (schedDivers.length !== schedDiversRaw.length) warnings.push(`schedule_divers: ${schedDiversRaw.length - schedDivers.length} row(s) referenced a missing schedule — skipped`);
  const validSchedDiverIds = new Set(schedDivers.map((d) => d.id));
  const diveTanks = diveTanksRaw.filter((t) => validSchedDiverIds.has(t.schedule_diver_id));
  const staffNameById = new Map(staffRows.map((s) => [s.id, `${s.first_name || ""} ${s.last_name || ""}`.trim()]));
  for (const sd of schedDivers) {
    if (sd.staff_id && staffNameById.has(sd.staff_id)) sd.staff_name = staffNameById.get(sd.staff_id);
  }
  console.log(`  schedule_divers: ${schedDivers.length} row(s)`);
  plan.push({ table: "schedule_divers", rows: schedDivers });
  console.log(`  schedule_diver_dive_tanks: ${diveTanks.length} row(s)`);
  plan.push({ table: "schedule_diver_dive_tanks", rows: diveTanks });

  const { rows: staffTankRowsRaw } = T.staffDiveTanks(rawSchedules);
  const staffTankRows = staffTankRowsRaw.filter((t) => validScheduleIds.has(t.schedule_id));
  if (staffTankRows.length !== staffTankRowsRaw.length) warnings.push(`schedule_staff_dive_tanks: ${staffTankRowsRaw.length - staffTankRows.length} row(s) referenced a missing schedule — skipped`);
  console.log(`  schedule_staff_dive_tanks: ${staffTankRows.length} row(s)`);
  plan.push({ table: "schedule_staff_dive_tanks", rows: staffTankRows });

  step("schedule_team_clips", "schedule_team_clips", T.scheduleTeamClips(rawScheduleTeamClips));
  step("schedule_team_clip_divers", "schedule_team_clip_divers", T.scheduleTeamClipDivers(rawScheduleTeamClipDivers));
  step("schedule_day_diver_exclusions", "schedule_day_diver_exclusions", T.scheduleDayDiverExclusions(rawScheduleDayDiverExclusions));

  {
    const fuelRows = step("fuel_logs", "fuel_logs", T.fuelLogs(rawFuelLogs));
    const validFuel = fuelRows.filter((f) => validScheduleIds.has(f.schedule_id));
    if (validFuel.length !== fuelRows.length) {
      warnings.push(`fuel_logs: ${fuelRows.length - validFuel.length} row(s) referenced a missing schedule (schedule_id is NOT NULL, can't null it out) — skipped`);
      plan[plan.length - 1].rows = validFuel;
    }
  }
  {
    const manifestRows = step("manifests", "manifests", T.manifests(rawManifests));
    const validManifests = manifestRows.filter((m) => validScheduleIds.has(m.schedule_id));
    if (validManifests.length !== manifestRows.length) {
      warnings.push(`manifests: ${manifestRows.length - validManifests.length} row(s) referenced a missing schedule (schedule_id is NOT NULL, can't null it out) — skipped`);
      plan[plan.length - 1].rows = validManifests;
    }
  }

  console.log("== visits & money ==");
  step("visits", "visits", T.visits(rawVisits));
  {
    const activityRows = step("activities", "activities", T.activities(rawActivities));
    // schedule_id is nullable here — null out a dangling reference rather
    // than drop the row, unlike fuel_logs/manifests above (real money/dive
    // data, shouldn't be lost over an orphaned schedule link)
    let danglingCount = 0;
    const sanitized = activityRows.map((a) => {
      if (a.schedule_id && !validScheduleIds.has(a.schedule_id)) {
        danglingCount++;
        return { ...a, schedule_id: null };
      }
      return a;
    });
    if (danglingCount) {
      warnings.push(`activities: ${danglingCount} row(s) referenced a missing schedule — schedule_id nulled out, row kept`);
      plan[plan.length - 1].rows = sanitized;
    }
  }
  step("payments", "payments", T.payments(rawPayments));
  step("deposits", "deposits", T.deposits(rawDeposits));
  step("invoice_emails", "invoice_emails", T.invoiceEmails(rawInvoiceEmails));
  step("visit_rate_selections", "visit_rate_selections", T.visitRateSelections(rawVisitRateSelections));
  step("diver_notes", "diver_notes", T.diverNotes(rawDiverNotes));

  console.log("== reports / financial ==");
  step("expenses", "expenses", T.expenses(rawExpenses));
  step("govt_fees", "govt_fees", T.govtFees(rawGovtFees));
  const joinRideStatementRows = step("join_ride_statements", "join_ride_statements", T.joinRideStatements(rawJoinRideStatements));
  const validStatementIds = new Set(joinRideStatementRows.map((s) => s.id));
  {
    const jrRows = step("join_ride_records", "join_ride_records", T.joinRideRecords(rawJoinRideRecords));
    let danglingCount = 0;
    const sanitized = jrRows.map((r) => {
      if (r.statement_id && !validStatementIds.has(r.statement_id)) {
        danglingCount++;
        return { ...r, statement_id: null };
      }
      return r;
    });
    if (danglingCount) {
      warnings.push(`join_ride_records: ${danglingCount} row(s) referenced a missing statement — statement_id nulled out, row kept`);
      plan[plan.length - 1].rows = sanitized;
    }
  }
  step("rental_gear_records", "rental_gear_records", T.rentalGearRecords(rawRentalGearRecords));
  step("staff_commission_records", "staff_commission_records", T.staffCommissionRecords(rawStaffCommissionRecords, diversByName));

  console.log("== audit ==");
  step("audit_logs", "audit_logs", T.auditLogs(rawAuditLogs));

  if (warnings.length) {
    console.log("\n== cross-reference warnings ==");
    warnings.forEach((w) => console.log(`  [WARN] ${w}`));
  }

  const totalRows = plan.reduce((sum, p) => sum + p.rows.length, 0);
  console.log(`\nTotal rows planned across ${plan.length} tables: ${totalRows}`);

  if (dryRun) {
    console.log("\n--dry-run: no database was touched.");
    return;
  }

  const dbUrl = process.env.AQUADESK_TARGET_DB_URL;
  if (!dbUrl) {
    console.error("\nAQUADESK_TARGET_DB_URL is not set — refusing to run for real. Set it to the rebuild project's pooler connection string, or pass --dry-run.");
    process.exit(1);
  }

  const { Client } = require("pg");
  const client = new Client({ connectionString: dbUrl, ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    await client.query("begin");

    let pendingWaiverBackfill = [];
    for (const { table, rows, passwordRehash, waiverUpdatedByBackfill } of plan) {
      if (waiverUpdatedByBackfill) pendingWaiverBackfill = waiverUpdatedByBackfill;
      if (!rows.length) continue;
      await insertBatch(client, table, rows);
      if (table === "dive_centers" && passwordRehash) {
        for (const p of passwordRehash) {
          if (p.billing_password) {
            await client.query(
              `update dive_centers set billing_unlock_hash = crypt($1, gen_salt('bf')) where id = $2`,
              [p.billing_password, p.id]
            );
          }
          if (p.owner_password) {
            await client.query(
              `update dive_centers set owner_unlock_hash = crypt($1, gen_salt('bf')) where id = $2`,
              [p.owner_password, p.id]
            );
          }
        }
      }
      if (table === "users" && pendingWaiverBackfill.length) {
        for (const w of pendingWaiverBackfill) {
          await client.query(
            `update dive_centers set waiver_content_updated_by = $1 where id = $2`,
            [w.waiver_content_updated_by, w.id]
          );
        }
        pendingWaiverBackfill = [];
      }
    }

    await client.query("commit");
    console.log("\nMigration committed.");
  } catch (e) {
    await client.query("rollback");
    console.error("\nMigration failed, rolled back:", e);
    process.exit(1);
  } finally {
    await client.end();
  }
}

const JSON_COLUMNS_BY_TABLE = {
  activities: ["equipment_breakdown", "addon_breakdown", "flags"],
  diver_registrations: ["medical_answers", "medical_answers_snapshot"],
  invoice_emails: ["invoice_snapshot"],
  auth_users: ["raw_app_meta_data", "raw_user_meta_data"],
  auth_identities: ["identity_data"],
};

async function insertBatch(client, table, rows) {
  const jsonCols = JSON_COLUMNS_BY_TABLE[table] || [];
  const columns = Object.keys(rows[0]);
  const CHUNK = 200;
  for (let start = 0; start < rows.length; start += CHUNK) {
    const chunk = rows.slice(start, start + CHUNK);
    const values = [];
    const placeholders = chunk.map((row) => {
      const rowPh = columns.map((col) => {
        let v = row[col];
        if (v === undefined) v = null;
        if (jsonCols.includes(col) && v !== null && typeof v !== "string") v = JSON.stringify(v);
        values.push(v);
        return `$${values.length}`;
      });
      return `(${rowPh.join(",")})`;
    });
    const quotedCols = columns.map((c) => `"${c}"`).join(",");
    const sql = `insert into ${table} (${quotedCols}) values ${placeholders.join(",")}`;
    await client.query(sql, values);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
