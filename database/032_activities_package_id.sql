begin;

-- Purely a display-identity tag, not used for pricing. activities.dive_site
-- must stay the raw joined site combination ("Kimud, Kimud, Monad") — Reports
-- Overview's dive-site activity bars (reports/data.ts's splitDiveSites) split
-- it on commas to count real per-site visits, and Diver Form's Apply Charges
-- matches on it via normalizeSiteKey — both would silently misbehave if this
-- column held a package's display name instead. package_id lets Boat Return
-- and the manual package-select dropdown record *which* package a row
-- actually corresponds to (when known and unambiguous) so anything that
-- wants a friendly name (the invoice, for one) can look it up by a stable id
-- instead of trying to reverse a package's name out of the site-combo text.
alter table activities
  add column package_id uuid references packages(id) on delete set null;

commit;
