// Server-side operator tool. Never ship the service key with the app or website.
import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
const [command,...args]=process.argv.slice(2);
const help='Commands: queue | review USER name|photo REVISION approve|reject [NOTE] | action USER remove_name|remove_photo|remove_content|restrict|restore|dismiss_report [REPORT_ID|-] [NOTE] | photo USER PATH OUTPUT';
const origin=process.env.WORLDNICHE_SERVICE_URL;
const key=process.env.WORLDNICHE_SERVICE_KEY;
if(!origin || !key || !command) { console.error(help+'\nSet WORLDNICHE_SERVICE_URL and WORLDNICHE_SERVICE_KEY in your local session.'); process.exit(1); }
assert(/^https:\/\/[a-z]{20}\.supabase\.co$/.test(origin),'Use the exact hosted project HTTPS URL.');
const uuid=x=>assert(/^[a-f0-9-]{36}$/i.test(x),'Expected a UUID.');
async function rpc(name,body) {
 const r=await fetch(`${origin}/rest/v1/rpc/${name}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(body)});
 if(!r.ok) {console.error(`Moderation request failed (HTTP ${r.status}). Refresh the queue before retrying a decision.`);process.exitCode=1;return;}
 console.log(JSON.stringify(await r.json(),null,2));
}
if(command==='queue') await rpc('moderation_queue',{p_limit:200});
else if(command==='review') {
 const [user,kind,revision,decision,note='']=args; uuid(user);uuid(revision);
 assert(['name','photo'].includes(kind)&&['approve','reject'].includes(decision)&&note.length<=500,help);
 await rpc('review_profile_content',{p_user_id:user,p_kind:kind,p_revision:revision,p_decision:decision,p_note:note});
} else if(command==='action') {
 const [user,action,report='-',note='']=args;uuid(user);if(report!=='-')uuid(report);
 assert(['remove_name','remove_photo','remove_content','restrict','restore','dismiss_report'].includes(action)&&note.length<=500,help);
 await rpc('moderate_user',{p_user_id:user,p_action:action,p_report_id:report==='-'?null:report,p_note:note});
} else if(command==='photo') {
 const [user,path,out]=args;uuid(user);
 assert(path.startsWith(user+'/') && /^[a-f0-9-]{36}\/[a-f0-9-]{36}\.jpg$/i.test(path) && out,help);
 const r=await fetch(`${origin}/storage/v1/object/authenticated/profile-photos/${path}`,{redirect:'error',signal:AbortSignal.timeout(15000),headers:{apikey:key,Authorization:`Bearer ${key}`}});
 assert(r.ok,`Photo request failed: HTTP ${r.status}`);
 assert(r.headers.get('content-type')?.startsWith('image/jpeg'),'Unexpected photo type');
 const bytes=Buffer.from(await r.arrayBuffer());assert(bytes.length<=300000,'Unexpected photo size');
 await writeFile(out,bytes,{mode:0o600,flag:'wx'});console.log('Private review image saved. Remove the local copy after review.');
} else throw Error(help);
