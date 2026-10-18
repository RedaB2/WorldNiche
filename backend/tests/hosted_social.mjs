// Opt-in hosted checks. Creates only run-scoped disposable accounts, sends no mail,
// and removes only the exact identities created by this process.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
const ref = process.argv[process.argv.indexOf('--project-ref') + 1];
assert(process.argv.includes('--live') && /^[a-z]{20}$/.test(ref), 'Pass --live --project-ref <explicit project>.');
const base = `https://${ref}.supabase.co`;
const key = process.env.WORLDNICHE_SERVICE_KEY;
const pub = process.env.WORLDNICHE_PUBLIC_KEY;
assert(key && pub, 'Server and public keys must be provided in process memory.');
const photo = await readFile(process.env.WORLDNICHE_TEST_PHOTO);
const run = randomUUID();
const accounts = [];
let checks = 0;
async function request(path, method='GET', body, identity, raw=false) {
  // Match native photo reads: every request must reach current RLS, even if a
  // CDN retains a previously authorized response for the same immutable object.
  const requestPath = path.startsWith('/storage/v1/object/authenticated/') && method==='GET'
    ? `${path}?cacheNonce=${randomUUID()}` : path;
  const response = await fetch(base+requestPath, {method, redirect:'error', signal:AbortSignal.timeout(20000),
    headers:{apikey:identity?.token ? pub : key, Authorization:`Bearer ${identity?.token ?? key}`, 'Cache-Control':raw?'max-age=0, no-store':'no-store',
      ...(body ? {'Content-Type':raw?'image/jpeg':'application/json'} : {})},
    body:body ? (raw ? body : JSON.stringify(body)) : undefined});
  const text=await response.text(); let value; try {value=JSON.parse(text);} catch {value=text;}
  return {status:response.status, ok:response.ok, value};
}
async function ok(path,method,body,identity,raw) {
  const r=await request(path,method,body,identity,raw);
  assert(r.ok, `${method} ${path.replace(/[0-9a-f-]{36}/g,'<id>')}: HTTP ${r.status}`);
  return r.value;
}
const rpc=(name,body={},identity)=>ok(`/rest/v1/rpc/${name}`,'POST',body,identity);
const pass=message=>{checks++; console.log(`PASS ${message}`);};
async function newAccount(index) {
  const email=`worldniche-qa-${run}-${index}@integration.invalid`;
  const user=await ok('/auth/v1/admin/users','POST',{email,email_confirm:true,app_metadata:{worldniche_test_run:run}});
  assert(user.id && user.email===email);
  const account={id:user.id,email,token:null}; accounts.push(account);
  const link=await ok('/auth/v1/admin/generate_link','POST',{type:'magiclink',email});
  assert(link.hashed_token, 'Admin-generated test link missing hash');
  const response=await fetch(base+'/auth/v1/verify',{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),
    headers:{apikey:pub,'Content-Type':'application/json'},body:JSON.stringify({token_hash:link.hashed_token,type:'magiclink'})});
  assert(response.ok,`Test session verification: HTTP ${response.status}`);
  const session=await response.json(); assert.equal(session.user.id,account.id); account.token=session.access_token;
  return account;
}
async function approve(account,kind) {
  const q=await rpc('moderation_queue'); const row=q.profiles.find(x=>x.user_id===account.id);
  assert(row,'Test submission must be queued');
  await rpc('review_profile_content',{p_user_id:account.id,p_kind:kind,p_revision:row[kind==='name'?'name_revision':'photo_revision'],p_decision:'approve',p_note:'Disposable integration fixture'});
}
try {
  const a=await newAccount(1), b=await newAccount(2), c=await newAccount(3);
  for(const [i,u] of accounts.entries()) await rpc('update_my_profile',{p_display_name:`QA Explorer ${i+1}`,p_avatar:'globe',p_share_exploration:true},u);
  pass('three confirmed disposable identities and real sessions, without email delivery');
  const path=`${a.id}/${randomUUID()}.jpg`;
  await ok(`/storage/v1/object/profile-photos/${path}`,'POST',photo,a,true);
  let profile=await rpc('set_profile_avatar',{p_path:path},a);
  assert.equal(profile.avatar_path,null); assert.equal(profile.pending_avatar_path,path);
  assert.equal(profile.photo_moderation_status,'pending');
  let denied=await request(`/storage/v1/object/authenticated/profile-photos/${path}`,'GET',null,c);
  assert(!denied.ok); assert.deepEqual(await ok(`/rest/v1/wn_profiles?id=eq.${a.id}&select=id`,'GET',null,c),[]);
  const invite=await rpc('create_invite',{},a);
  assert.equal((await rpc('preview_invite',{p_token:invite.token},b)).display_name,'Explorer');
  assert.equal((await rpc('accept_invite',{p_token:invite.token},b)).status,'accepted');
  assert.equal((await rpc('accept_invite',{p_token:invite.token},b)).status,'already_friends');
  denied=await request(`/storage/v1/object/authenticated/profile-photos/${path}`,'GET',null,b); assert(!denied.ok);
  assert.equal((await rpc('list_friends',{},a)).length,1); assert.equal((await rpc('list_friends',{},b)).length,1);
  pass('nonfriend isolation, quarantined photos, approved-only previews and idempotent mutual friendship');
  assert(!(await request('/rest/v1/rpc/moderation_queue','POST',{},a)).ok);
  await approve(a,'name'); await approve(a,'photo');
  assert.equal((await rpc('list_friends',{},b))[0].display_name,'QA Explorer 1');
  assert((await request(`/storage/v1/object/authenticated/profile-photos/${path}`,'GET',null,b)).ok);
  await request('/storage/v1/object/profile-photos','DELETE',{prefixes:[path]},a);
  assert((await request(`/storage/v1/object/authenticated/profile-photos/${path}`,'GET',null,b)).ok);
  assert(!(await request(`/storage/v1/object/profile-photos/${path}`,'POST',photo,a,true)).ok);
  pass('privileged review publishes content and approved image bytes cannot be replaced');
  await rpc('sync_explorations',{p_country_ids:['MA','JP']},a);
  assert.equal((await rpc('list_friends',{},b))[0].explored_count,2);
  await rpc('update_my_profile',{p_display_name:'QA Explorer 1',p_avatar:'globe',p_share_exploration:false},a);
  assert.equal((await rpc('list_friends',{},b))[0].explored_count,0);
  await rpc('report_user',{p_user_id:a.id,p_reason:'inappropriate_photo',p_details:'Disposable test report'},b);
  const q=await rpc('moderation_queue'); const report=q.reports.find(x=>x.subject_id===a.id && x.reporter_id===b.id); assert(report);
  assert.equal((await rpc('export_my_data',{},a)).reports.length,0);
  await rpc('moderate_user',{p_user_id:a.id,p_action:'dismiss_report',p_report_id:report.id,p_note:'Integration fixture only'});
  pass('sharing consent removes cloud exploration and reports reach the private review queue');
  await rpc('block_user',{p_user_id:a.id},b);
  assert.deepEqual(await rpc('list_friends',{},a),[]); assert.deepEqual(await rpc('list_friends',{},b),[]);
  const blockedPhoto=await request(`/storage/v1/object/authenticated/profile-photos/${path}`,'GET',null,b);
  assert(!blockedPhoto.ok);
  assert.equal((await rpc('accept_invite',{p_token:invite.token},b)).status,'unavailable');
  await rpc('revoke_invites',{},a);
  assert.equal((await rpc('accept_invite',{p_token:invite.token},c)).status,'unavailable');
  pass('blocking immediately removes friend/photo access and revoked invitations cannot connect');
  const next=await rpc('create_invite',{},a); await rpc('accept_invite',{p_token:next.token},c);
  const deletion=await ok('/functions/v1/delete-account','POST',{},a);
  assert.equal(deletion.deleted,true); assert.equal(deletion.apple_revocation,'not_required');
  assert.equal((await ok('/functions/v1/delete-account','POST',{},a)).deleted,true);
  assert.equal((await request(`/auth/v1/admin/users/${a.id}`)).status,404);
  assert.deepEqual(await ok('/storage/v1/object/list/profile-photos','POST',{prefix:`${a.id}/`,limit:100}),[]);
  assert.deepEqual(await ok(`/rest/v1/wn_profiles?id=eq.${a.id}&select=id`),[]);
  assert.deepEqual(await rpc('list_friends',{},c),[]);
  assert(!(await request('/rest/v1/rpc/update_my_profile','POST',{p_display_name:'Recreated',p_avatar:'globe',p_share_exploration:false},a)).ok);
  const after=await rpc('moderation_queue'); assert(!after.profiles.some(x=>x.user_id===a.id)); assert(!after.reports.some(x=>x.subject_id===a.id));
  pass('live email account deletion erases photos, Auth, profiles and friend access; retry is safe and stale session fails');
} finally {
  let failed=false;
  for(const u of accounts) {
    try {
      const current=await request(`/auth/v1/admin/users/${u.id}`);
      if(current.status===404) continue;
      assert(current.ok && current.value.email===u.email && current.value.app_metadata?.worldniche_test_run===run,'Cleanup identity guard');
      if(u.token) {
        const deleted=await request('/functions/v1/delete-account','POST',{},u);
        if(deleted.ok && deleted.value.deleted===true) continue;
      }
      const objects=await ok('/storage/v1/object/list/profile-photos','POST',{prefix:`${u.id}/`,limit:1000});
      if(objects.length) await ok('/storage/v1/object/profile-photos','DELETE',{prefixes:objects.map(x=>`${u.id}/${x.name}`)});
      await ok(`/auth/v1/admin/users/${u.id}`,'DELETE',{should_soft_delete:false});
      assert.equal((await request(`/auth/v1/admin/users/${u.id}`)).status,404);
    } catch {failed=true; console.error(`Cleanup required for test account ${u.id}`);}
  }
  assert(!failed,'Disposable test cleanup needs attention.');
  console.log(`Cleanup confirmed for ${accounts.length} disposable accounts. ${checks} hosted test groups passed.`);
}
