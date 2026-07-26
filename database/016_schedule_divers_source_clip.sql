-- AquaDesk Rebuild — Scheduling's phase-based rebuild (mirroring
-- scheduling.html's Prepare/Build/Complete flow) needs to trace a trip's
-- placed team back to the shared "clip" (schedule_team_clips) it came
-- from, so an edit made at the trip level can optionally be synced back
-- to the shared clip. The live app tracks this in-memory only
-- (sourceClipId, part of the schedules.notes JSON blob it uses as its
-- source of truth) — this rebuild uses real relational columns for trip
-- structure instead (schedules.closed/cancelled are already real columns,
-- not a JSON flag), so the equivalent needs a real column here too.

begin;

alter table public.schedule_divers
  add column source_clip_id uuid references public.schedule_team_clips(id) on delete set null;

commit;
