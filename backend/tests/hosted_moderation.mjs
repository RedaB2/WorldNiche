// Explicit live checks only. Creates run-scoped disposable identities without
// email delivery, and never sends real users' content to the provider.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';

const scenarios = [
  'safe opted-in name and JPEG publish automatically to a connected friend',
  'unconsented content stays private and cannot be claimed',
  'synthetic threatening name waits for human review without friend exposure',
  'optional cooldown preserves the newest accepted edit until scheduled retry',
  'all run-tagged disposable identities and their photos are deleted',
];
if (process.argv.includes('--dry-run')) {
  assert(!process.argv.includes('--live'), 'Choose dry run or live, never both.');
  console.log('Dry validation only. No network requests or credentials used.');
  for (const scenario of scenarios) console.log(`PLAN ${scenario}`);
  process.exit(0);
}
const refIndex = process.argv.indexOf('--project-ref');
const ref = refIndex >= 0 ? process.argv[refIndex + 1] : undefined;
assert(process.argv.includes('--live') && /^[a-z]{20}$/.test(ref ?? ''), 'Pass --live --project-ref <explicit project>.');
const base = `https://${ref}.supabase.co`;
const key = process.env.WORLDNICHE_SERVICE_KEY;
const pub = process.env.WORLDNICHE_PUBLIC_KEY;
assert(key && pub, 'Server and public keys must be supplied in process memory.');
assert(process.env.WORLDNICHE_TEST_PHOTO, 'Provide a harmless JPEG fixture through WORLDNICHE_TEST_PHOTO.');
const photo = await readFile(process.env.WORLDNICHE_TEST_PHOTO);
assert(photo.length >= 4 && photo.length <= 300000 && photo[0] === 0xff && photo[1] === 0xd8 &&
  photo.at(-2) === 0xff && photo.at(-1) === 0xd9, 'Fixture must be a valid bounded JPEG.');
const run = randomUUID();
const accounts = [];
let checks = 0;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const pass = message => {checks++; console.log(`PASS ${message}`);};

async function request(path, method = 'GET', body, identity, raw = false) {
  const imageRead = path.startsWith('/storage/v1/object/authenticated/') && method === 'GET';
  const requestPath = imageRead ? `${path}?cacheNonce=${randomUUID()}` : path;
  const response = await fetch(base + requestPath, {
    method, redirect: 'error', signal: AbortSignal.timeout(45000),
    headers: {
      apikey: identity?.token ? pub : key,
      Authorization: `Bearer ${identity?.token ?? key}`,
      'Cache-Control': 'no-store',
      ...(body !== undefined ? {'Content-Type': raw ? 'image/jpeg' : 'application/json'} : {}),
    },
    body: body !== undefined ? (raw ? body : JSON.stringify(body)) : undefined,
  });
  if (imageRead && response.ok) {
    return {status: response.status, ok: true, value: Buffer.from(await response.arrayBuffer())};
  }
  const text = await response.text();
  let value;
  try {value = JSON.parse(text);} catch {value = null;}
  return {status: response.status, ok: response.ok, value};
}
async function ok(path, method, body, identity, raw) {
  const response = await request(path, method, body, identity, raw);
  assert(response.ok, `${method ?? 'GET'} ${path.replace(/[0-9a-f-]{36}/g, '<id>')}: HTTP ${response.status}`);
  return response.value;
}
const rpc = (name, body = {}, identity) => ok(`/rest/v1/rpc/${name}`, 'POST', body, identity);
const profile = account => rpc('get_my_profile', {}, account);
const kick = account => ok('/functions/v1/moderate-profile', 'POST', {}, account);
const editName = (account, name) => rpc('update_my_profile', {
  p_display_name: name, p_avatar: 'globe', p_share_exploration: false,
}, account);

async function newAccount(index) {
  const email = `worldniche-moderation-qa-${run}-${index}@integration.invalid`;
  const user = await ok('/auth/v1/admin/users', 'POST', {
    email, email_confirm: true, app_metadata: {worldniche_test_run: run},
  });
  assert(user?.id, 'Created test identity must have an ID.');
  const account = {id: user.id, email, token: null};
  accounts.push(account);
  assert.equal(user.email, email);
  const link = await ok('/auth/v1/admin/generate_link', 'POST', {type: 'magiclink', email});
  assert(link.hashed_token, 'Admin-generated test link needs a hash.');
  const response = await fetch(base + '/auth/v1/verify', {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(20000),
    headers: {apikey: pub, 'Content-Type': 'application/json'},
    body: JSON.stringify({token_hash: link.hashed_token, type: 'magiclink'}),
  });
  assert(response.ok, `Disposable session verification: HTTP ${response.status}`);
  const session = await response.json();
  assert.equal(session.user.id, account.id);
  assert(session.access_token);
  account.token = session.access_token;
  return account;
}

async function upload(account) {
  const path = `${account.id}/${randomUUID()}.jpg`;
  await ok(`/storage/v1/object/profile-photos/${path}`, 'POST', photo, account, true);
  await rpc('set_profile_avatar', {p_path: path}, account);
  return path;
}

async function waitFor(account, predicate, description, timeout = 180000) {
  const deadline = Date.now() + timeout;
  do {
    const current = await profile(account);
    if (predicate(current)) return current;
    assert(!current.community_restricted, 'Disposable account was unexpectedly restricted.');
    await sleep(2500);
  } while (Date.now() < deadline);
  assert.fail(`Timed out waiting for ${description}.`);
}

async function friendProfile(viewer, subject) {
  const friends = await rpc('list_friends', {}, viewer);
  const found = friends.find(friend => friend.id === subject.id);
  assert(found, 'Expected disposable friendship is missing.');
  return found;
}

try {
  const a = await newAccount(1), b = await newAccount(2), c = await newAccount(3);
  const initialName = 'QA Garden Explorer';
  await editName(a, initialName);
  await editName(b, 'QA Friend Explorer');
  await editName(c, 'QA Private Explorer');
  const path = await upload(a);
  const privatePath = await upload(c);
  const invite = await rpc('create_invite', {}, a);
  assert.equal((await rpc('accept_invite', {p_token: invite.token}, b)).status, 'accepted');
  assert.equal((await friendProfile(b, a)).display_name, 'Explorer');
  assert(!(await request(`/storage/v1/object/authenticated/profile-photos/${path}`, 'GET', undefined, b)).ok);
  pass('disposable confirmed sessions and friendship created without email delivery; pending content is hidden');

  const unconsented = await kick(c);
  assert.equal(unconsented.automatic_profile_checks_enabled, false);
  assert.equal(unconsented.name_moderation_status, 'pending');
  assert.equal(unconsented.photo_moderation_status, 'pending');
  assert.equal(unconsented.avatar_path, null);
  assert.equal(unconsented.pending_avatar_path, privatePath);
  assert.deepEqual(await rpc('claim_profile_checks', {p_user_id: c.id, p_limit: 2}), []);
  assert(!(await request(`/storage/v1/object/authenticated/profile-photos/${privatePath}`, 'GET', undefined, a)).ok);
  pass('foreground requests cannot process unconsented content or expose its photo');

  await rpc('set_profile_check_consent', {p_enabled: true}, a);
  await kick(a);
  const approved = await waitFor(a, value => value.name_moderation_status === 'approved' &&
    value.photo_moderation_status === 'approved', 'automatic name and photo approval');
  assert.equal(approved.display_name, initialName);
  assert.equal(approved.avatar_path, path);
  let friend = await friendProfile(b, a);
  assert.equal(friend.display_name, initialName);
  assert.equal(friend.avatar_path, path);
  const image = await ok(`/storage/v1/object/authenticated/profile-photos/${path}`, 'GET', undefined, b);
  assert.deepEqual(image, photo);
  assert(!(await request(`/storage/v1/object/authenticated/profile-photos/${path}`, 'GET', undefined, c)).ok);
  pass('OpenAI approved the opted-in name and JPEG; the friend sees the same name, photo path, and image bytes');

  const nextName = 'QA Meadow Explorer';
  await editName(a, nextName);
  await kick(a);
  await waitFor(a, value => value.display_name === nextName && value.name_moderation_status === 'approved', 'updated name approval');
  assert.equal((await friendProfile(b, a)).display_name, nextName);
  pass('a subsequent approved profile edit is immediately visible in friend access');

  // Synthetic policy fixture, never addressed to a real person or sent to users.
  const flaggedName = 'I will murder you';
  await editName(a, flaggedName);
  await kick(a);
  const held = await waitFor(a, value => {
    assert.notEqual(value.display_name, flaggedName, 'Threat fixture must never be published.');
    return value.name_check_state === 'review';
  }, 'synthetic threatening name to enter human review');
  assert.equal(held.name_moderation_status, 'pending');
  assert.equal(held.pending_display_name, flaggedName);
  assert.equal(held.display_name, nextName);
  friend = await friendProfile(b, a);
  assert.equal(friend.display_name, nextName);
  assert.equal(friend.avatar_path, path);
  assert.deepEqual(await rpc('claim_profile_checks', {p_user_id: a.id, p_limit: 2}), []);
  pass('synthetic threatening name is held for review and cannot replace the approved friend profile');

  if (process.argv.includes('--cooldown')) {
    const d = await newAccount(4);
    await editName(d, 'QA First Cooldown');
    await upload(d);
    const started = Date.now();
    await rpc('set_profile_check_consent', {p_enabled: true}, d);
    await kick(d);
    await waitFor(d, value => value.name_moderation_status === 'approved' && value.photo_moderation_status === 'approved', 'first cooldown pair');
    await editName(d, 'QA Second Cooldown');
    await upload(d);
    await kick(d);
    await waitFor(d, value => value.display_name === 'QA Second Cooldown' && value.photo_moderation_status === 'approved', 'second cooldown pair');
    // Four genuine provider checks fit the default per-account minute allowance.
    // If the provider was slow, do not manufacture exhaustion by editing limits.
    if (Date.now() - started >= 45000) {
      console.log('SKIP cooldown: four genuine checks took too long to reliably fill one rolling minute.');
    } else {
      await editName(d, 'QA Older Cooldown');
      await kick(d);
      // The edit trigger can claim first, so the foreground response may still
      // say checking while that worker atomically defers the same revision.
      await waitFor(d, value => {
        assert.equal(value.display_name, 'QA Second Cooldown', 'Cooldown must preserve the previous approved name.');
        assert.equal(value.pending_display_name, 'QA Older Cooldown');
        return value.name_check_state === 'retry';
      }, 'initial account cooldown to persist', 30000);
      await editName(d, 'QA Latest Cooldown');
      await kick(d);
      await waitFor(d, value => {
        assert.notEqual(value.display_name, 'QA Older Cooldown', 'Replaced revision must never publish.');
        assert.equal(value.display_name, 'QA Second Cooldown', 'Replacement must retain the approved name during cooldown.');
        assert.equal(value.pending_display_name, 'QA Latest Cooldown');
        return value.name_check_state === 'retry';
      }, 'replacement cooldown to persist', 30000);
      // Read-only polling from here proves the scheduled worker retries the job.
      const resumed = await waitFor(d, value => {
        assert.notEqual(value.display_name, 'QA Older Cooldown', 'An older revision must not publish after replacement.');
        return value.display_name === 'QA Latest Cooldown' && value.name_moderation_status === 'approved';
      }, 'scheduled retry of the newest accepted revision', 180000);
      assert.equal(resumed.pending_display_name, null);
      pass('the actual account cooldown retained the newest edit and scheduled retry approved it without changing limits');
    }
  }

  const stillPrivate = await profile(c);
  assert.equal(stillPrivate.automatic_profile_checks_enabled, false);
  assert.equal(stillPrivate.name_moderation_status, 'pending');
  assert.equal(stillPrivate.photo_moderation_status, 'pending');
  pass('unconsented content remained private throughout automatic worker activity');

  const deletion = await ok('/functions/v1/delete-account', 'POST', {}, a);
  assert.equal(deletion.deleted, true);
  assert.equal((await request(`/auth/v1/admin/users/${a.id}`)).status, 404);
  assert.deepEqual(await rpc('list_friends', {}, b), []);
  assert(!(await request(`/storage/v1/object/authenticated/profile-photos/${path}`, 'GET', undefined, b)).ok);
  assert.deepEqual(await ok('/storage/v1/object/list/profile-photos', 'POST', {prefix: `${a.id}/`, limit: 100}), []);
  pass('account deletion removes approved photos, held content, Auth identity, and friend access');
} finally {
  let failed = false;
  for (const account of accounts) {
    try {
      const current = await request(`/auth/v1/admin/users/${account.id}`);
      if (current.status === 404) {
        assert.deepEqual(await ok('/storage/v1/object/list/profile-photos', 'POST', {prefix: `${account.id}/`, limit: 1000}), [], 'Deleted identity must leave no photos.');
        continue;
      }
      assert(current.ok && current.value.email === account.email &&
        current.value.app_metadata?.worldniche_test_run === run, 'Cleanup identity guard');
      if (account.token) {
        const deletion = await request('/functions/v1/delete-account', 'POST', {}, account);
        if (deletion.ok && deletion.value.deleted === true) {
          assert.equal((await request(`/auth/v1/admin/users/${account.id}`)).status, 404);
          assert.deepEqual(await ok('/storage/v1/object/list/profile-photos', 'POST', {prefix: `${account.id}/`, limit: 1000}), [], 'Deleted identity must leave no photos.');
          continue;
        }
      }
      const objects = await ok('/storage/v1/object/list/profile-photos', 'POST', {prefix: `${account.id}/`, limit: 1000});
      assert(Array.isArray(objects) && objects.length < 1000, 'Cleanup object listing must be complete.');
      for (const object of objects) assert(/^[0-9a-f-]{36}\.jpg$/.test(object.name), 'Cleanup object must be run-owned JPEG.');
      if (objects.length) await ok('/storage/v1/object/profile-photos', 'DELETE', {
        prefixes: objects.map(object => `${account.id}/${object.name}`),
      });
      await ok(`/auth/v1/admin/users/${account.id}`, 'DELETE', {should_soft_delete: false});
      assert.equal((await request(`/auth/v1/admin/users/${account.id}`)).status, 404);
      assert.deepEqual(await ok('/storage/v1/object/list/profile-photos', 'POST', {prefix: `${account.id}/`, limit: 1000}), [], 'Fallback cleanup must leave no photos.');
    } catch {
      failed = true;
      console.error(`Cleanup required for disposable test account ${account.id}`);
    }
  }
  assert(!failed, 'Disposable cleanup requires attention.');
  console.log(`Cleanup confirmed for ${accounts.length} disposable accounts. ${checks} hosted moderation groups passed.`);
}
