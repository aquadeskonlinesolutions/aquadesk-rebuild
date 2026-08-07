// Per-table old-schema -> new-schema transforms.
// Source of truth: ../../LIVE_DATA_MIGRATION_MAPPING.md and
// ../../LIVE_APP_SCHEMA_SNAPSHOT.md (both at the repo root) — read those
// before changing anything here, they explain *why* each transform exists.
//
// Every transform function takes the raw exported old rows (already
// scoped to the batch's dive_center_id(s) by the export query) and
// returns an array of {values, warnings} for the new schema, or for the
// handful of reshaping tables, a combined result touching multiple new
// tables at once.

const sanitizeHtml = require("sanitize-html");

const WAIVER_SANITIZE_OPTS = {
  allowedTags: ["p", "br", "b", "strong", "i", "em", "ul", "ol", "li"],
  allowedAttributes: {},
};

function sanitizeWaiver(html) {
  if (!html) return html;
  return sanitizeHtml(html, WAIVER_SANITIZE_OPTS);
}

// ---- enum / value transform maps -----------------------------------

const BOAT_TYPE_MAP = {
  Outrigger: "outrigger",
  "Flat Boat": "flat_boat",
  "Chase Boat": "chase_boat",
  "Speed Boat": "speed_boat",
};
const FUEL_TYPE_MAP = { Gasoline: "gasoline", Diesel: "diesel" };
const EMPLOYMENT_STATUS_MAP = {
  "Full Time": "full_time",
  "Part Time": "part_time",
  Freelance: "freelance",
};
const TANK_TYPE_MAP = { "Air 12L": "air_12l", "Air 15L": "air_15l", Nitrox: "nitrox" };
const EXPENSE_CATEGORY_MAP = {
  Fuel: "fuel",
  "Boat Maintenance": "boat_maintenance",
  "Equipment Maintenance": "equipment_maintenance",
  "Compressor / Fill Station": "compressor_fill_station",
  "Staff Meals": "staff_meals",
  "Food Expenses": "food_expenses",
  "Office Supplies": "office_supplies",
  Utilities: "utilities",
  "Licenses & Permits": "licenses_permits",
  Marketing: "marketing",
  Repairs: "repairs",
  Other: "other",
  Uncategorized: "uncategorized",
};
const JOIN_RIDE_STATUS_MAP = {
  "To Collect": "to_collect",
  "Statement Printed": "statement_printed",
  Collected: "collected",
  "Expected To Pay": "expected_to_pay",
  "Statement Received": "statement_received",
  Paid: "paid",
};
const JOIN_RIDE_STATEMENT_STATUS_MAP = { "Statement Printed": "statement_printed" };
const RENTAL_GEAR_STATUS_MAP = {
  "To Collect": "to_collect",
  Collected: "collected",
  "To Pay": "to_pay",
  Paid: "paid",
};
const COMMISSION_STATUS_MAP = { Paid: "paid", Unpaid: "unpaid" };

// certification_level is a real multi-word display string old-side
// ("Advanced Open Water") vs. a snake_case enum on target
// (advanced_open_water) — needs a real lookup, not .toLowerCase(). Real
// exported data also surfaced "Advance" (a shorthand/typo variant), not
// just the clean 6 label set.
const CERTIFICATION_LEVEL_MAP = {
  none: "none",
  "": "none",
  "open water diver": "open_water_diver",
  "open water": "open_water_diver",
  "advanced open water": "advanced_open_water",
  advance: "advanced_open_water",
  advanced: "advanced_open_water",
  "rescue diver": "rescue_diver",
  rescue: "rescue_diver",
  divemaster: "divemaster",
  instructor: "instructor",
};
function mapCertificationLevel(old) {
  if (!old) return "none";
  const mapped = CERTIFICATION_LEVEL_MAP[old.trim().toLowerCase()];
  return mapped || null; // null signals "couldn't map" to the caller
}

// training_agency real values seen: 'SSI', 'PADI', null, '' — all clean
// single-word acronyms that .toLowerCase() handles, but guard against an
// unmapped value rather than trust that blindly for every dive center.
const TRAINING_AGENCY_VALUES = new Set(["padi", "ssi", "naui", "cmas", "other"]);
function mapTrainingAgency(old) {
  if (!old) return null;
  const lower = old.trim().toLowerCase();
  return TRAINING_AGENCY_VALUES.has(lower) ? lower : null;
}

function classifySurchargeType(old) {
  const s = (old || "").toLowerCase();
  if (s.includes("card") || s.includes("credit")) return "card";
  if (s.includes("online")) return "online";
  return null; // caller should flag this as unmapped
}

// ---- simple/direct tables --------------------------------------------
// Each entry: old array -> new array of plain objects (column: value).
// Rows that hit an unmapped enum value are returned separately as
// `skipped` with a reason, never silently coerced.

function mapDirect(rows, fn) {
  const out = [];
  const skipped = [];
  for (const r of rows || []) {
    try {
      const mapped = fn(r);
      if (mapped === null) {
        skipped.push({ row: r, reason: "transform returned null (unmapped value)" });
      } else {
        out.push(mapped);
      }
    } catch (e) {
      skipped.push({ row: r, reason: e.message });
    }
  }
  return { rows: out, skipped };
}

const diveCenters = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    name: r.name,
    email: r.email,
    phone: r.phone,
    address: r.address,
    logo_url: null, // real file needs re-upload to the new Storage bucket separately, see LIVE_DATA_MIGRATION_MAPPING.md
    subscription_status: (r.subscription_status || "active").toLowerCase(),
    pricing_mode: (r.pricing_mode || "").toLowerCase().includes("package")
      ? "package"
      : "tier",
    // billing_password / owner_password are handled specially in etl.js
    // (crypt()'d server-side via SQL, never plaintext-inserted here)
    fuel_current_level: r.fuel_current_level ?? 0,
    fuel_low_threshold: r.fuel_low_threshold ?? 0,
    fuel_gasoline_level: r.fuel_gasoline_level ?? 0,
    fuel_gasoline_threshold: r.fuel_gasoline_threshold ?? 20,
    fuel_gasoline_last_reset_at: r.fuel_gasoline_last_reset_at,
    fuel_diesel_level: r.fuel_diesel_level ?? 0,
    fuel_diesel_threshold: r.fuel_diesel_threshold ?? 50,
    fuel_diesel_last_reset_at: r.fuel_diesel_last_reset_at,
    staff_token: null, // ephemeral, never migrate — see mapping doc
    staff_token_date: null,
    waiver_content: sanitizeWaiver(r.waiver_content),
    waiver_updated_at: r.waiver_updated_at,
    // waiver_content_updated_by references `users`, which loads *after*
    // dive_centers in build order — nulled here, backfilled in etl.js
    // once users exist, same two-phase pattern as the password rehash
    waiver_content_updated_by: null,
    billing_due_date: r.billing_due_date,
    last_payment_date: r.last_payment_date,
    billing_amount: r.billing_amount ?? 4000,
    offers_dive_insurance: r.offers_dive_insurance ?? false,
    insurance_referral_link: r.insurance_referral_link,
    divemaster_rate_per_dive: 0,
    ratio_bonus_enabled: false,
    ratio_bonus_extra_rate: 0,
    join_ride_rate_per_diver_per_dive: 0,
  }));

const users = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    full_name: r.full_name,
    email: r.email,
    role: r.role,
    is_active: r.is_active ?? true,
    can_view_revenue: r.can_view_revenue ?? false,
    password_changed: r.password_changed ?? false,
    failed_login_attempts: 0, // don't carry over transient lockout state — see mapping doc
    locked_until: null,
  }));

const platformAdmins = (rows) =>
  mapDirect(
    (rows || []).filter((r) => r.is_platform_admin),
    (r) => ({
      user_id: r.id,
      full_name: r.full_name,
      email: r.email,
      is_active: r.is_active ?? true,
    })
  );

const authUsers = (rows) =>
  mapDirect(rows, (r) => {
    // verbatim copy, see mapping doc's Auth section — except `confirmed_at`,
    // which is a GENERATED column on the target project (computed from
    // email_confirmed_at) and can't be inserted directly
    const { confirmed_at, ...rest } = r;
    return rest;
  });

const authIdentities = (rows) =>
  mapDirect(rows, (r) => {
    // verbatim copy — except `email`, GENERATED on the target as
    // lower(identity_data->>'email')
    const { email, ...rest } = r;
    return rest;
  });

const staff = (rows) =>
  mapDirect(rows, (r) => {
    const employment = EMPLOYMENT_STATUS_MAP[r.employment_status];
    if (r.employment_status && !employment) {
      throw new Error(`unmapped staff.employment_status: ${r.employment_status}`);
    }
    return {
      id: r.id,
      created_at: r.created_at,
      dive_center_id: r.dive_center_id,
      first_name: r.first_name,
      last_name: r.last_name,
      email: r.email,
      phone: r.phone,
      whatsapp: r.whatsapp,
      position: r.access_level || "crew", // NOT r.role — access_level is the real field, see mapping doc; NOT NULL on target with a default, coalesce defensively
      employment_status: employment || null,
      date_hired: r.date_hired,
      daily_rate: r.daily_rate,
      nitrox_certified: r.nitrox_certified ?? false,
      is_active: r.is_active ?? true,
      user_id: r.auth_user_id,
      // certification_level / commission_rate / pay_type / salary_amount
      // confirmed dead in the old app (LIVE_APP_SCHEMA_SNAPSHOT.md #12) — not migrated
      // emergency_contact_* — no old source, left null by omission
    };
  });

const boats = (rows) =>
  mapDirect(rows, (r) => {
    const boatType = BOAT_TYPE_MAP[r.boat_type];
    const fuelType = FUEL_TYPE_MAP[r.fuel_type];
    if (r.boat_type && !boatType) throw new Error(`unmapped boats.boat_type: ${r.boat_type}`);
    if (r.fuel_type && !fuelType) throw new Error(`unmapped boats.fuel_type: ${r.fuel_type}`);
    return {
      id: r.id,
      created_at: r.created_at,
      dive_center_id: r.dive_center_id,
      name: r.name,
      captain: r.captain,
      boat_type: boatType || null,
      fuel_type: fuelType || null,
      capacity: r.capacity,
      is_active: r.is_active ?? true,
      // old `type` column confirmed dead (LIVE_APP_SCHEMA_SNAPSHOT.md #10) — not migrated
    };
  });

const diveSites = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    // no created_at on the new dive_sites table at all — confirmed in
    // LIVE_DATA_MIGRATION_MAPPING.md, don't reintroduce it
    dive_center_id: r.dive_center_id,
    site_name: r.site_name,
    distance: r.distance,
    fuel_estimate: r.fuel_estimate,
    linked_package_id: r.linked_package_id,
    is_active: r.is_active ?? true,
    shark_fee: r.shark_fee ?? false,
  }));

const courseRates = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    course_name: r.course_name,
    rate: r.price, // renamed
    is_active: r.is_active ?? true,
  }));

const rateTiers = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    tier_from: r.tier_from,
    tier_to: r.tier_to,
    base_rate: r.base_rate,
    rate_type: r.rate_type,
    is_active: true, // no old equivalent, old rows are implicitly always active
  }));

const packages = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    package_name: r.package_name,
    dive_site: r.dive_site, // free text, comma-joined, order/repeat-sensitive — copy verbatim, never normalize
    price: r.price,
    equipment_included: r.equipment_included ?? false,
    is_active: r.is_active ?? true,
  }));

const otherCharges = (rows) =>
  mapDirect(rows, (r) => {
    // real data has surfaced a third charge_type value, "fixed" (a
    // one-time charge, e.g. "Night Surcharge"), beyond the documented
    // per_dive/per_day pair — map to per_day (won't get multiplied per
    // dive, the safer analog for a flat one-time fee)
    const chargeType = r.charge_type === "fixed" ? "per_day" : r.charge_type;
    return {
      id: r.id,
      created_at: r.created_at,
      dive_center_id: r.dive_center_id,
      charge_name: r.charge_name, // exact casing matters, downstream pricing string-matches on this
      amount: r.amount,
      charge_type: chargeType,
      sub_type: r.sub_type,
      is_active: r.is_active ?? true,
    };
  });

const equipmentRentalRates = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    item_name: r.item_name,
    rate: r.rate,
    charge_type: r.charge_type,
    is_active: r.is_active ?? true,
  }));

const paymentSurcharges = (rows) =>
  mapDirect(rows, (r) => {
    const type = classifySurchargeType(r.surcharge_type);
    if (!type) throw new Error(`unclassifiable payment_surcharges.surcharge_type: ${r.surcharge_type}`);
    return {
      id: r.id,
      dive_center_id: r.dive_center_id,
      surcharge_type: type,
      rate: (r.percentage ?? 0) / 100, // THE rescale — see mapping doc, this is the one that silently breaks if missed
      is_active: true,
    };
  });

const exchangeRates = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    dive_center_id: r.dive_center_id,
    currency_code: r.currency_code,
    rate_to_php: r.rate_to_php,
    is_active: r.is_active ?? true,
    updated_at: r.updated_at ?? r.created_at ?? new Date().toISOString(), // NOT NULL on target, some old rows have it null
  }));

const { randomUUID } = require("crypto");

const medicalQuestions = (rows) =>
  mapDirect(rows, (r) => ({
    id: randomUUID(), // old id is bigint, new is uuid — fresh id, nothing else references it by FK
    dive_center_id: r.dive_center_id,
    question_text: r.question_text,
    is_active: r.is_active ?? true,
    sort_order: r.sort_order ?? 0, // confirmed real on old side too, no synthesis needed
  }));

const tanks = (rows) =>
  mapDirect(rows, (r) => {
    const type = TANK_TYPE_MAP[r.type];
    if (r.type && !type) throw new Error(`unmapped tanks.type: ${r.type}`);
    return {
      id: r.id,
      dive_center_id: r.dive_center_id,
      type: type || null,
      total_count: r.total_count,
      available_count: r.available_count,
      in_use_count: r.in_use_count,
      low_alert_threshold: r.low_alert_threshold,
    };
  });

const equipment = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    name: r.name,
    type: r.type,
    total_count: r.total_count,
    low_alert_threshold: r.low_alert_threshold,
    is_active: true,
  }));

const groups = (rows) =>
  mapDirect(rows, (r) => {
    // old leader_email/leader_whatsapp have no new-schema column — folded
    // into notes rather than silently dropped (new finding, not in the
    // original JS-only mapping — see LIVE_APP_SCHEMA_SNAPSHOT.md)
    const extra = [];
    if (r.leader_email) extra.push(`Leader email: ${r.leader_email}`);
    if (r.leader_whatsapp) extra.push(`Leader WhatsApp: ${r.leader_whatsapp}`);
    const notes = [r.notes, ...extra].filter(Boolean).join(" | ") || null;
    return {
      id: r.id,
      created_at: r.created_at,
      dive_center_id: r.dive_center_id,
      group_name: r.group_name,
      leader_name: r.leader_name,
      arrival_date: r.arrival_date,
      expected_count: r.expected_count,
      is_active: r.is_active ?? true,
      departure_date: r.departure_date,
      notes,
    };
  });

const divers = (rows) =>
  mapDirect(rows, (r) => {
    const cert = mapCertificationLevel(r.certification_level);
    if (cert === null) {
      throw new Error(`unmapped divers.certification_level: "${r.certification_level}"`);
    }
    return {
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    first_name: r.first_name,
    last_name: r.last_name,
    birthday: r.birthday,
    age: r.age,
    is_minor: r.is_minor ?? false,
    nationality: r.nationality,
    email: r.email,
    phone: r.phone,
    whatsapp: r.whatsapp,
    emergency_contact_name: r.emergency_contact_name,
    emergency_contact_phone: r.emergency_contact_phone,
    emergency_contact_email: r.emergency_contact_email,
    emergency_contact_relationship: r.emergency_contact_relationship,
    emergency_contact_whatsapp: r.emergency_contact_whatsapp ?? null,
    certification_level: cert,
    training_agency: mapTrainingAgency(r.training_agency),
    logged_dives: r.logged_dives ?? 0,
    last_dive_date: r.last_dive_date,
    nitrox_certified: r.nitrox_certified ?? false,
    food_allergies: r.food_allergies,
    has_dive_insurance: r.has_dive_insurance,
    insurance_provider: r.insurance_provider,
    insurance_policy_number: r.insurance_policy_number,
    needs_equipment: r.needs_equipment ?? false,
    equipment_requested: r.equipment_requested,
    equipment_notes: r["equipment notes"] ?? null, // literal old column name has a space
    medical_acknowledged: r.medical_acknowledged ?? false,
    medical_acknowledged_at: r.medical_acknowledged_at,
    medical_acknowledged_by: r.medical_acknowledged_by,
    cert_card_url: null, // real cert-card image needs separate re-upload to the new Storage bucket
    notes: r.notes,
    group_id: r.group_id,
    accommodation: r.accommodation,
    // waiver_*/medical_flag/medical_answers*/privacy_*/duplicate_email_flag/
    // equipment_preference/wants_insurance_referral/arrival_date/departure_date
    // are all diver_registrations-only in the new schema — see divers() transform note
    };
  });

// diver_registrations: the old app's own registration insert never wrote
// several fields it collected (emergency contact, accommodation, insurance,
// last_dive_date, identity snapshot) — those are backfilled here from the
// linked `divers` row's *current* value, which is a reconstructed
// approximation, not a true historical snapshot (see mapping doc's
// dedicated caveat).
function buildRegistrationRow(id, r, diver) {
  return {
    id,
    created_at: r.created_at,
    diver_id: r.diver_id ?? r.id,
    dive_center_id: r.dive_center_id,
    waiver_signed: r.waiver_signed ?? false, // NOT NULL with a default on target — never send null explicitly
    waiver_date: r.waiver_date,
    waiver_signature_url: r.waiver_signature_url, // base64 data URI, large — expected
    waiver_content_snapshot: r.waiver_content_snapshot,
    medical_flag: r.medical_flag ?? false, // NOT NULL with a default on target — never send null explicitly
    medical_answers: r.medical_answers,
    medical_answers_snapshot: r.medical_answers_snapshot ?? null,
    privacy_notice_snapshot: r.privacy_notice_snapshot,
    privacy_consent_at: r.privacy_consent_at,
    arrival_date: r.arrival_date,
    departure_date: r.departure_date,
    certification_level: mapCertificationLevel(r.certification_level) || "none",
    equipment_requested: r.equipment_requested,
    group_id: r.group_id,
    needs_equipment: r.needs_equipment ?? false,
    equipment_preference: r.equipment_preference,
    // backfilled-from-divers, reconstructed not historical — flagged per mapping doc
    accommodation: diver?.accommodation ?? null,
    emergency_contact_name: diver?.emergency_contact_name ?? null,
    emergency_contact_phone: diver?.emergency_contact_phone ?? null,
    emergency_contact_whatsapp: diver?.emergency_contact_whatsapp ?? null,
    emergency_contact_email: diver?.emergency_contact_email ?? null,
    emergency_contact_relationship: diver?.emergency_contact_relationship ?? null,
    last_dive_date: diver?.last_dive_date ?? null,
    food_allergies: diver?.food_allergies ?? null,
    has_dive_insurance: diver?.has_dive_insurance ?? null,
    insurance_provider: diver?.insurance_provider ?? null,
    insurance_policy_number: diver?.insurance_policy_number ?? null,
    wants_insurance_referral: null, // nullable on target, no old source at all — fine to leave null
    waiver_opened: false, // NOT NULL with a default on target — no old source, use the default rather than sending null
    duplicate_email_flag: false, // same — NOT NULL with a default
    first_name: diver?.first_name ?? null,
    last_name: diver?.last_name ?? null,
    birthday: diver?.birthday ?? null,
    nationality: diver?.nationality ?? null,
    email: diver?.email ?? null,
    phone: diver?.phone ?? null,
    whatsapp: diver?.whatsapp ?? null,
  };
}

// `diversById` is a Map of already-transformed new divers rows, keyed by
// id, built by the caller before this runs.
const diverRegistrations = (rows, diversById) =>
  mapDirect(rows, (r) => buildRegistrationRow(r.id, r, diversById.get(r.diver_id)));

// Real, confirmed finding (2026-08-07 live investigation): the vast
// majority of real divers in this app's actual historical data have NO
// diver_registrations row at all, despite carrying a full registration-
// equivalent record (arrival_date, waiver, medical answers, equipment
// request) directly on their OLD `divers` row — the old app has (at
// least) one diver-creation path that writes rich data onto `divers`
// without ever inserting into `diver_registrations`. The new schema
// deliberately dropped arrival_date/waiver/medical/etc. from `divers`
// entirely (they live only on `diver_registrations` now), so without
// this synthesis step, that data — and anything reading it, like
// Reports' Equipment Management page, which the live app drives off
// `divers.arrival_date` directly — silently has nothing to show for
// these divers. `rawOldDivers` is scoped to rows whose id is NOT in
// `existingRegistrationDiverIds` (already-migrated real registrations,
// don't duplicate) and that show a real signal of registration-equivalent
// data (arrival_date set) — a bare walk-in profile with no such field
// set gets no synthetic row, there's nothing to synthesize.
function synthesizeMissingRegistrations(rawOldDivers, existingRegistrationDiverIds) {
  const { randomUUID } = require("crypto");
  const rows = [];
  for (const r of rawOldDivers || []) {
    if (existingRegistrationDiverIds.has(r.id)) continue;
    if (!r.arrival_date) continue;
    rows.push(buildRegistrationRow(randomUUID(), { ...r, diver_id: r.id }, r));
  }
  return rows;
}

const diverStaffDefaults = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    dive_center_id: r.dive_center_id,
    diver_id: r.diver_id,
    staff_id: r.staff_id,
    updated_at: r.updated_at,
  }));

const visits = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    diver_id: r.diver_id,
    course_rate_id: r.course_rate_id,
    experience_type: r.experience_type || "fun_diving",
    visit_start: r.visit_start,
    visit_end: r.visit_end,
    visit_status: r.visit_status || "open",
    is_active: r.is_active ?? true,
    is_paid: r.is_paid ?? false,
    invoice_count: r.invoice_count ?? 0,
    updated_at: r.created_at, // no old equivalent, not load-bearing — see mapping doc
  }));

const activities = (rows) =>
  mapDirect(rows, (r) => {
    let flags = null;
    if (r.notes) {
      try {
        const parsed = JSON.parse(r.notes);
        flags = {
          nitrox_requested: !!parsed.nitrox_requested,
          tank_15l_requested: !!(parsed.tank_15l_requested ?? parsed.fifteen_l_requested),
        };
      } catch {
        // old notes wasn't valid JSON — leave flags null, nothing to reshape
      }
    }
    return {
      id: r.id,
      created_at: r.created_at,
      dive_center_id: r.dive_center_id,
      diver_id: r.diver_id,
      visit_id: r.visit_id,
      schedule_id: r.schedule_id,
      date: r.date,
      dive_site: r.dive_site, // raw joined site-combo text — copy verbatim, never "clean up"
      staff_name: r.staff_name, // NOT staff_id — confirmed dead-for-writes, see mapping doc
      dive_rate: r.dive_rate ?? 0,
      fuel_surcharge: r.fuel_surcharge ?? 0,
      marine_tax: r.marine_tax ?? 0,
      shark_fee: r.shark_fee ?? 0,
      nitrox_fee: r.nitrox_fee ?? 0,
      fifteen_l_fee: r.fifteen_l_fee ?? 0, // NOT fee_15l — confirmed the live/current column
      equipment_rental: r.equipment_rental ?? 0,
      equipment_breakdown: r.equipment_breakdown,
      addons: r.addons ?? 0,
      addon_breakdown: r.addon_breakdown,
      discount: 0, // new-only, no old per-row discount
      total: r.total ?? 0, // recompute pass recommended post-migration, see mapping doc
      status: (r.status || "planned").toLowerCase(),
      flags,
      notes: null, // old `notes` meant something else entirely — never copy verbatim, see mapping doc's critical warning
      package_id: null,
    };
  });

const payments = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    diver_id: r.diver_id,
    visit_id: r.visit_id,
    cash_amount: r.cash_amount ?? 0,
    cash_amount_foreign: r.cash_amount_foreign ?? 0,
    cash_currency_code: r.cash_currency_code || r.cash_currency || "PHP",
    cash_exchange_rate: r.cash_exchange_rate,
    card_amount: r.card_amount ?? 0,
    online_amount: r.online_amount ?? 0,
    total_paid: r.total_paid ?? 0,
    balance: r.balance ?? 0,
    discount: r.discount ?? 0,
    grand_total_php: r.grand_total_php ?? 0,
    card_surcharge_rate: r.card_surcharge_rate ?? 5,
    online_surcharge_rate: r.online_surcharge_rate ?? 2,
    card_surcharge_amount: r.card_surcharge_amount ?? 0,
    online_surcharge_amount: r.online_surcharge_amount ?? 0,
    total_surcharge: r.total_surcharge ?? 0,
    total_collected: r.total_collected ?? 0,
    is_paid: r.is_paid ?? false,
    paid_at: r.paid_at,
    excess_amount: 0, // new-only concept, no old source
    // old `currency`/`exchange_rate`/`currency_code` (bare, non-cash-prefixed)
    // look like legacy duplicates of cash_currency_code/cash_exchange_rate —
    // not confirmed live/dead by the investigation pass, treated as dead;
    // verify if any real row's cash_currency_code ends up unexpectedly null
  }));

const deposits = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    visit_id: r.visit_id,
    diver_id: r.diver_id,
    amount: r.amount,
    method: r.method,
    deposit_date: r.deposit_date,
    received_by: r.received_by,
    recorded_by_user_id: r.recorded_by_user_id,
  }));

const invoiceEmails = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    dive_center_id: r.dive_center_id,
    visit_id: r.visit_id,
    diver_id: r.diver_id,
    sent_at: r.sent_at,
    sent_by: r.sent_by,
    invoice_snapshot: r.invoice_snapshot,
    email_sent_at: null, // old app conflated "generated" and "emailed" — left null per mapping doc's decision
    email_sent_by: null,
    email_delivery_status: "not_sent",
  }));

const visitRateSelections = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    dive_center_id: r.dive_center_id,
    visit_id: r.visit_id,
    site_key: r.site_key,
    package_id: r.package_id,
    custom_price: r.custom_price,
  }));

const diverNotes = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    diver_id: r.diver_id,
    note: r.note,
    created_by: r.author_user_id, // author_name (write-time snapshot) has no new-schema equivalent — real, accepted loss
  }));

// ---- schedules: the big one --------------------------------------------
// Old `schedules.notes` is a JSON blob (`buildTripMeta`) carrying most of
// the real trip structure. This explodes one old row into: 1 new
// `schedules` row + N `schedule_sites` + N `schedule_crew` + N
// `schedule_divers` (+ their per-dive tank child rows, built by
// scheduleDivers() below, not here — this function only returns the
// schedules/sites/crew rows plus the parsed blob for the caller to pass
// through). See LIVE_DATA_MIGRATION_MAPPING.md's "Quick reference" table.

function parseScheduleBlob(notesText) {
  if (!notesText) return {};
  try {
    return JSON.parse(notesText) || {};
  } catch {
    return { notesText }; // not valid JSON — treat the raw string as free-text notes only
  }
}

function schedulesAndChildren(rows) {
  const schedules = [];
  const scheduleSites = [];
  const scheduleCrew = [];
  const skipped = [];

  for (const r of rows || []) {
    try {
      const meta = parseScheduleBlob(r.notes);
      const isJoiner = !!r.is_joiner;

      schedules.push({
        id: r.id,
        created_at: r.created_at,
        dive_center_id: r.dive_center_id,
        boat_id: isJoiner ? null : r.boat_id,
        schedule_date: r.schedule_date,
        departure_time: r.departure_time,
        is_joiner: isJoiner,
        joiner_boat_name: r.joiner_boat_name,
        fuel_consumed_liters: r.fuel_consumed_liters,
        closed: r.is_returned ?? false, // real signal — better than the blob's own `closed` copy, see LIVE_APP_SCHEMA_SNAPSHOT.md
        cancelled: false, // old app's cancel feature was always dead — see mapping doc
        notes: meta.notesText ?? null, // NOT the raw JSON blob — critical, see mapping doc
        created_by: null, // no old equivalent
        guest_divers_count: meta.joinerDivers ?? null,
        guest_dive_center_name: meta.joinerDC ?? null,
        guest_notes: meta.joinerNotes ?? null,
        captain: isJoiner ? null : meta.captain ?? null,
        trip_type_id: null, // needs a seeding pass, not part of this batch — see mapping doc
        // meta.joinDC / meta.owner (join/rental distinguishing text) have no
        // destination column — accepted, deliberate loss per this session's decision
      });

      if (!isJoiner) {
        (meta.crews || [])
          .map((c) => (c || "").trim())
          .filter(Boolean)
          .forEach((name, i) =>
            scheduleCrew.push({
              dive_center_id: r.dive_center_id,
              schedule_id: r.id,
              crew_name: name,
              sort_order: i,
            })
          );
      }

      (meta.sites || [])
        .filter(Boolean)
        .forEach((_siteName, i) => {
          // site name -> dive_sites.id resolution happens in etl.js, where
          // the batch's migrated dive_sites are already loaded into memory
          scheduleSites.push({
            dive_center_id: r.dive_center_id,
            schedule_id: r.id,
            site_name: meta.sites[i],
            sort_order: i,
          });
        });
    } catch (e) {
      skipped.push({ row: r, reason: e.message });
    }
  }

  return { schedules, scheduleSites, scheduleCrew, skipped };
}

// NOTE: an earlier version of this file had a `scheduleDivers(rows)`
// function here that built schedule_divers from the OLD relational
// `schedule_divers` table. Removed 2026-08-07 — confirmed via live
// investigation that table's rows are stale/orphaned in real data (0%
// matched any currently-existing schedule in the first real migration
// batch), which silently dropped every diver-schedule assignment until
// the user's own live comparison against the real app caught a missing
// diver. Do not resurrect this approach — see scheduleDiversFromBlob()
// below, and CLAUDE.md's retrospective entry for this session for the
// full account of why the blob, not the table, is the real source.

// schedule_divers, derived from the schedule's OWN notes blob
// (meta.staffGroups[].diverIds/nitrox/tank15l/is15l) — NOT from the old
// relational `schedule_divers` table. Confirmed via live investigation
// (2026-08-07): the old table's rows are stale/orphaned (0% match any
// currently-existing schedule in real data), while the current,
// authoritative diver-assignment data lives in each schedule's own
// blob, same place staffDiveTanks() already reads staff-level nitrox
// from. `staffIdByName` is a Map<"first last" lowercase, staff.id>
// built by the caller from the already-migrated staff batch.
function scheduleDiversFromBlob(scheduleRows, staffIdByName, experienceTypeByDiverId = new Map()) {
  const divers = [];
  const diveTanks = [];

  for (const r of scheduleRows || []) {
    const meta = parseScheduleBlob(r.notes);
    for (const g of meta.staffGroups || []) {
      const staffId = g.isFreelancer ? null : staffIdByName.get((g.name || "").trim().toLowerCase()) ?? null;
      const excluded = new Set(g.excludedDiverIds || []);
      for (const diverId of g.diverIds || []) {
        if (excluded.has(diverId)) continue;
        const newId = randomUUID();
        const nitroxIdx = g.nitrox?.[diverId] || [];
        const tank15lIdx = g.tank15l?.[diverId] || (g.is15l?.[diverId] ? [] : []);
        divers.push({
          id: newId,
          created_at: r.created_at,
          dive_center_id: r.dive_center_id,
          schedule_id: r.id,
          diver_id: diverId,
          staff_id: staffId,
          // no reliable old-schema source for this column (see mapping
          // doc) — best-effort backfill from the diver's own migrated
          // visits, defaulting to fun_diving (the overwhelmingly common
          // case, and required for Reports' "Leading Our Dives" query,
          // which filters on this exact column)
          experience_type: experienceTypeByDiverId.get(diverId) || "fun_diving",
          is_15l: !!(tank15lIdx.length || g.is15l?.[diverId]),
          is_diving_tomorrow: true,
          nitrox_requested: !!nitroxIdx.length,
          notes: null,
          source_clip_id: null,
          staff_name: g.name || null,
        });
        const seen = new Set();
        for (const i of nitroxIdx) {
          seen.add(i);
          diveTanks.push({ dive_center_id: r.dive_center_id, schedule_diver_id: newId, site_index: i, tank_type: "nitrox" });
        }
        for (const i of tank15lIdx) {
          if (seen.has(i)) continue;
          diveTanks.push({ dive_center_id: r.dive_center_id, schedule_diver_id: newId, site_index: i, tank_type: "air_15l" });
        }
      }
    }
  }

  return { divers, diveTanks };
}

// schedule_staff_dive_tanks — sourced from the schedule's own notes blob
// (meta.staffGroups[].staffNitrox), not from any real relational table.
function staffDiveTanks(scheduleRows) {
  const out = [];
  for (const r of scheduleRows || []) {
    const meta = parseScheduleBlob(r.notes);
    for (const g of meta.staffGroups || []) {
      for (const i of g.staffNitrox || []) {
        out.push({ dive_center_id: r.dive_center_id, schedule_id: r.id, staff_name: g.name || "Unassigned Staff", site_index: i }); // NOT NULL on target — found via preflight.js
      }
    }
  }
  return { rows: out, skipped: [] };
}

const scheduleTeamClips = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    updated_at: r.updated_at,
    dive_center_id: r.dive_center_id,
    schedule_date: r.schedule_date,
    staff_id: r.staff_id,
    staff_name: r.staff_name || "Unassigned Staff", // NOT NULL on target — found via preflight.js, not confirmed hit in real data yet
    is_freelancer: r.is_freelancer ?? false,
    source: r.source || "manual",
    created_by: r.created_by,
    carry_forward: r.carry_forward ?? true,
  }));

const scheduleTeamClipDivers = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    dive_center_id: r.dive_center_id,
    clip_id: r.clip_id,
    diver_id: r.diver_id,
    excluded_on_date: r.excluded_on_date ?? false,
  }));

const scheduleDayDiverExclusions = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    schedule_date: r.schedule_date,
    diver_id: r.diver_id,
    created_by: r.created_by,
  }));

const fuelLogs = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    schedule_id: r.schedule_id,
    boat_id: r.boat_id,
    fuel_type: r.fuel_type,
    liters_consumed: r.liters_consumed,
    diver_count: r.diver_count ?? 0,
    dive_count: r.dive_count ?? 0,
  }));

const manifests = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    dive_center_id: r.dive_center_id,
    schedule_id: r.schedule_id,
    district: r.district,
    port: r.port,
    last_edited_at: r.last_edited_at,
    // printed_at/locked/unlocked_at/unlocked_by exist on the OLD schema
    // (confirmed dead there too) but were never built into the rebuild's
    // manifests table at all — confirmed against the real target schema,
    // not just assumed from LIVE_APP_SCHEMA_SNAPSHOT.md
  }));

const expenses = (rows) =>
  mapDirect(rows, (r) => {
    // Money data — never silently drop a row over an unmapped category.
    // Real live data has surfaced at least one value (`"Food & Beverages"`)
    // not in the documented 13-value list — fall back to `other` and
    // preserve the original label in custom_category rather than skip.
    let category = EXPENSE_CATEGORY_MAP[r.category];
    let customCategory = r.custom_category;
    if (r.category && !category) {
      category = "other";
      customCategory = customCategory ? `${r.category} (${customCategory})` : r.category;
    }
    const notes = r.paid_by ? `Paid by: ${r.paid_by}${r.notes ? " — " + r.notes : ""}` : r.notes;
    return {
      id: r.id,
      created_at: r.created_at,
      dive_center_id: r.dive_center_id,
      date: r.date,
      category: category || "uncategorized",
      custom_category: customCategory,
      amount: r.amount,
      payment_method: null, // no old source, not reliably inferrable from paid_by — see mapping doc
      notes,
      created_by: r.created_by,
    };
  });

const govtFees = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    date: r.date,
    fee_type: r.fee_type,
    rate: r.rate ?? 0,
    divers: r.divers ?? 0,
    total: r.total ?? 0,
  }));

const joinRideStatements = (rows) =>
  mapDirect(rows, (r) => {
    const status = JOIN_RIDE_STATEMENT_STATUS_MAP[r.status] || "statement_printed";
    return {
      id: r.id,
      created_at: r.created_at,
      dive_center_id: r.dive_center_id,
      company: r.company,
      date_from: r.date_from,
      date_to: r.date_to,
      total_amount: r.total_amount ?? 0,
      status,
      prepared_by: r.prepared_by,
      printed_at: r.printed_at,
      updated_at: r.updated_at,
    };
  });

const joinRideRecords = (rows) =>
  mapDirect(rows, (r) => {
    const status = JOIN_RIDE_STATUS_MAP[r.status];
    if (r.status && !status) throw new Error(`unmapped join_ride_records.status: ${r.status}`);
    return {
      id: r.id,
      created_at: r.created_at,
      dive_center_id: r.dive_center_id,
      direction: r.direction,
      date: r.date,
      company: r.company,
      number_of_divers: r.number_of_divers ?? 0,
      number_of_dives: r.number_of_dives ?? 0,
      dive_sites: r.dive_sites,
      total_amount: r.total_amount ?? 0,
      status: status || null,
      balance: r.balance ?? 0,
      remarks: r.remarks,
      statement_id: r.statement_id,
      updated_at: r.updated_at,
    };
  });

const rentalGearRecords = (rows) =>
  mapDirect(rows, (r) => {
    const status = RENTAL_GEAR_STATUS_MAP[r.status];
    if (r.status && !status) throw new Error(`unmapped rental_gear_records.status: ${r.status}`);
    return {
      id: r.id,
      created_at: r.created_at,
      dive_center_id: r.dive_center_id,
      date: r.date,
      equipment: r.equipment,
      company: r.company,
      quantity: r.quantity ?? 0,
      rate: r.rate ?? 0,
      total_amount: r.total_amount ?? 0,
      status: status || null,
      balance: r.balance ?? 0,
      remarks: r.remarks,
      updated_at: r.updated_at,
    };
  });

// staff_commission_records: the two-step restructuring. `diversByName` is
// a Map<"first last" lowercase, new diver id> built by the caller from the
// already-migrated divers batch, used to resolve free-text diver_name.
const staffCommissionRecords = (rows, diversByName) =>
  mapDirect(rows, (r) => {
    const status = COMMISSION_STATUS_MAP[r.status];
    if (r.status && !status) throw new Error(`unmapped staff_commission_records.status: ${r.status}`);
    const diverId = r.diver_name
      ? diversByName.get(r.diver_name.trim().toLowerCase()) ?? null
      : null;
    return {
      id: r.id,
      created_at: r.created_at,
      dive_center_id: r.dive_center_id,
      activity_date: r.date, // renamed from `date`; period_month dropped entirely (purely derived old-side)
      staff_name: r.staff_name || "Unassigned Staff", // NOT NULL on target — found via preflight.js
      commission_group: r.commission_group,
      title: r.title,
      diver_id: diverId,
      quantity: r.quantity ?? 0,
      rate: r.rate ?? 0,
      commission_amount: r.commission_amount ?? 0,
      status: status || null,
      paid_at: r.paid_at,
      remarks: r.remarks,
      updated_at: r.updated_at,
      divers: 0, // no clean old source for diver *count* on this row — see mapping doc, needs manual review if it matters
      bonus_amount: r.additional_rate ?? 0,
      // total_amount has no destination column at all — recomputed at read time from rate + bonus_amount
    };
  });

const auditLogs = (rows) =>
  mapDirect(rows, (r) => ({
    id: r.id,
    created_at: r.created_at,
    dive_center_id: r.dive_center_id,
    action: r.action,
    performed_by: r.performed_by,
    target_type: r.target_type,
    target_id: r.target_id,
    notes: r.notes,
  }));

module.exports = {
  sanitizeWaiver,
  diveCenters,
  users,
  platformAdmins,
  authUsers,
  authIdentities,
  staff,
  boats,
  diveSites,
  courseRates,
  rateTiers,
  packages,
  otherCharges,
  equipmentRentalRates,
  paymentSurcharges,
  exchangeRates,
  medicalQuestions,
  tanks,
  equipment,
  groups,
  divers,
  diverRegistrations,
  synthesizeMissingRegistrations,
  diverStaffDefaults,
  visits,
  activities,
  payments,
  deposits,
  invoiceEmails,
  visitRateSelections,
  diverNotes,
  schedulesAndChildren,
  scheduleDiversFromBlob,
  staffDiveTanks,
  scheduleTeamClips,
  scheduleTeamClipDivers,
  scheduleDayDiverExclusions,
  fuelLogs,
  manifests,
  expenses,
  govtFees,
  joinRideStatements,
  joinRideRecords,
  rentalGearRecords,
  staffCommissionRecords,
  auditLogs,
};
