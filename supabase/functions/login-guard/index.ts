// supabase/functions/login-guard/index.ts
//
// Per-ACCOUNT login lockout, complementing Supabase Auth's built-in
// per-IP rate limiting. Supabase throttles requests from a single IP;
// this function throttles attempts against a single account regardless
// of how many different IPs they come from.
//
// Deploy with --no-verify-jwt since this must be callable before the
// user has a session (the login page itself calls it pre-auth):
//   supabase functions deploy login-guard --no-verify-jwt
//
// Actions (POST body: { action, email }):
//   "check" — call before attempting sign-in / password reset.
//             Returns { allowed: boolean, retry_after_seconds? }
//   "fail"  — call after a failed sign-in attempt.
//             Returns { allowed, locked, retry_after_seconds, attempts_remaining }
//   "reset" — call after a successful sign-in.
//             Clears the failed-attempt counter.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;

// Confirmed against create-secretary (which already works in production):
// this project still has the legacy service_role key active, and that's
// what admin-level Edge Functions here use. The dashboard's "Deprecated"
// label is just Supabase's migration messaging — the key itself is live.
const SECRET_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const MAX_ATTEMPTS = 5;
const LOCKOUT_MINUTES = 30;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  let body: { action?: string; email?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  const { action, email } = body;
  if (!action || !email || typeof email !== 'string') {
    return json({ error: 'Missing action or email' }, 400);
  }
  if (!['check', 'fail', 'reset'].includes(action)) {
    return json({ error: 'Unknown action' }, 400);
  }

  const normalizedEmail = email.trim().toLowerCase();
  const admin = createClient(SUPABASE_URL, SECRET_KEY);

  try {
    const { data: user, error: fetchErr } = await admin
      .from('users')
      .select('id, failed_login_attempts, locked_until')
      .ilike('email', normalizedEmail)
      .maybeSingle();

    if (fetchErr) {
      console.error('login-guard fetch error:', fetchErr);
      // Fail open: don't block sign-in on our own infrastructure errors.
      // Supabase Auth's IP-based rate limit still applies regardless.
      return json({ allowed: true });
    }

    // Unknown email — respond exactly as we would for a known, unlocked
    // account. Otherwise this endpoint becomes an email-enumeration tool.
    if (!user) {
      return json({ allowed: true });
    }

    const now = Date.now();
    let attempts = user.failed_login_attempts || 0;
    let lockedUntilMs = user.locked_until ? new Date(user.locked_until).getTime() : 0;

    // Lock has naturally expired — clear it so the account gets a clean
    // slate rather than re-locking on the very next failure.
    if (lockedUntilMs && lockedUntilMs <= now) {
      attempts = 0;
      lockedUntilMs = 0;
      await admin
        .from('users')
        .update({ failed_login_attempts: 0, locked_until: null })
        .eq('id', user.id);
    }

    const isLocked = lockedUntilMs > now;

    if (action === 'check') {
      if (isLocked) {
        return json({ allowed: false, retry_after_seconds: Math.ceil((lockedUntilMs - now) / 1000) });
      }
      return json({ allowed: true });
    }

    if (action === 'fail') {
      if (isLocked) {
        return json({ allowed: false, locked: true, retry_after_seconds: Math.ceil((lockedUntilMs - now) / 1000) });
      }
      const newAttempts = attempts + 1;
      const update: Record<string, unknown> = { failed_login_attempts: newAttempts };
      let locked = false;
      let retryAfter = 0;

      if (newAttempts >= MAX_ATTEMPTS) {
        const until = new Date(now + LOCKOUT_MINUTES * 60 * 1000);
        update.locked_until = until.toISOString();
        locked = true;
        retryAfter = LOCKOUT_MINUTES * 60;
      }

      const { error: updErr } = await admin.from('users').update(update).eq('id', user.id);
      if (updErr) console.error('login-guard update error:', updErr);

      return json({
        allowed: !locked,
        locked,
        retry_after_seconds: retryAfter,
        attempts_remaining: Math.max(0, MAX_ATTEMPTS - newAttempts),
      });
    }

    // action === 'reset'
    const { error: resetErr } = await admin
      .from('users')
      .update({ failed_login_attempts: 0, locked_until: null })
      .eq('id', user.id);
    if (resetErr) console.error('login-guard reset error:', resetErr);

    return json({ ok: true });
  } catch (err) {
    console.error('login-guard unexpected error:', err);
    return json({ allowed: true }); // fail open
  }
});