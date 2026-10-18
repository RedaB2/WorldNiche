// Runs the actual Edge handler with real JWT signatures and local Auth/Apple HTTP fixtures.
// Requires Node 24+ and jose 6.1.3. No Apple or Supabase account is contacted.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const josePath = process.env.WORLDNICHE_JOSE_MODULE || path.join(root, 'node_modules/jose/dist/webapi/index.js');
const joseURL = pathToFileURL(josePath).href;
const {generateKeyPair, exportJWK, exportPKCS8, jwtVerify, SignJWT} = await import(joseURL);
const {privateKey, publicKey} = await generateKeyPair('ES256');
const jwk = {...await exportJWK(publicKey), kid: 'integration', use: 'sig', alg: 'ES256'};
const applePair = await generateKeyPair('RS256');
const appleJWK = {...await exportJWK(applePair.publicKey), kid: 'apple-integration', use:'sig', alg:'RS256'};
const clientPair = await generateKeyPair('ES256', {extractable:true});
const userID = '00000000-0000-0000-0000-000000000001';
const sessionID = '10000000-0000-0000-0000-000000000001';
const nonce = '0123456789abcdef0123456789abcdef';
const appleID = 'verified-apple-user';
const clientID = 'io.worldniche.app';
const teamID = 'TEAMTEST01';
const keyID = 'KEYTEST001';
const defaults = () => ({exists:true, deletes:0, adminCalls:0, failRead:false, allowed:true, loseResponse:false,
  apple:false, appleExchanges:0, appleRevokes:0, exchangeStatus:200, revokeStatus:200,
  exchangeError:'invalid_grant', malformedExchangeError:false,
  appleSubject:appleID, appleNonce:createHash('sha256').update(nonce).digest('hex'), appleIssuer:null,
  appleAudience:clientID, appleExpiry:'5m', badAppleSignature:false, missingAppleClaims:false,
  missingAppleSubject:false, failDelete:false, storageObjects:[], failStorage:false, storageDeletes:0, events:[]});
let state = defaults();
let fixtureError;
const server = createServer(async (req, res) => {
  try {
    const send = (status, body) => {res.writeHead(status, {'content-type':'application/json'});res.end(JSON.stringify(body));};
    if (req.url === '/auth/v1/.well-known/jwks.json') return send(200,{keys:[jwk]});
    if (req.url === '/apple/auth/keys') return send(200,{keys:[appleJWK]});
    if (req.url === '/apple/auth/token' || req.url === '/apple/auth/revoke') {
      assert.equal(req.method,'POST');
      assert.equal(req.headers['content-type'],'application/x-www-form-urlencoded');
      const chunks=[];for await(const chunk of req)chunks.push(chunk);
      const input = new URLSearchParams(Buffer.concat(chunks).toString());
      assert.equal(input.get('client_id'),clientID);
      const {payload,protectedHeader} = await jwtVerify(input.get('client_secret'), clientPair.publicKey,
        {issuer:teamID,audience:`${base}/apple`,subject:clientID,algorithms:['ES256']});
      assert.equal(protectedHeader.kid,keyID);assert.ok(payload.exp-payload.iat<=300);
      assert.equal(input.has('redirect_uri'),false,'Native authorization does not invent a web redirect');
      if (req.url.endsWith('/token')) {
        state.appleExchanges++;state.events.push('exchange');
        assert.equal(input.get('grant_type'),'authorization_code');
        assert.equal(input.get('code'),'fresh-apple-code');
        if(state.exchangeStatus!==200){
          if(state.malformedExchangeError){res.writeHead(state.exchangeStatus,{'content-type':'application/json'});res.end('not json');return;}
          return send(state.exchangeStatus,{error:state.exchangeError});
        }
        let jwt = new SignJWT({nonce:state.appleNonce}).setProtectedHeader({alg:'RS256',kid:'apple-integration'})
          .setSubject(state.appleSubject).setIssuer(state.appleIssuer??`${base}/apple`).setAudience(state.appleAudience);
        if(!state.missingAppleClaims) jwt=jwt.setIssuedAt().setExpirationTime(state.appleExpiry);
        const signing = state.badAppleSignature ? (await generateKeyPair('RS256')).privateKey : applePair.privateKey;
        return send(200,{id_token:await jwt.sign(signing),refresh_token:'ephemeral-apple-refresh'});
      }
      state.appleRevokes++;state.events.push('revoke');
      assert.equal(input.get('token'),'ephemeral-apple-refresh');
      assert.equal(input.get('token_type_hint'),'refresh_token');
      return send(state.revokeStatus,{});
    }
    if (req.url === '/rest/v1/rpc/authorize_deletion') {
      state.events.push('authorize');
      return send(state.allowed?200:401,{allowed:state.allowed});
    }
    assert.equal(req.headers.apikey,'test-service-key');
    assert.equal(req.headers.authorization,'Bearer test-service-key');
    if (req.url === '/storage/v1/object/list/profile-photos') {
      assert.equal(req.method, 'POST');
      const chunks=[]; for await(const chunk of req) chunks.push(chunk);
      const input=JSON.parse(Buffer.concat(chunks).toString());
      assert.equal(input.prefix, `${userID}/`);
      if(state.failStorage) return send(503,{error:'temporary'});
      return send(200,state.storageObjects.map(name=>({name,id:name})));
    }
    if (req.url === '/storage/v1/object/profile-photos') {
      assert.equal(req.method, 'DELETE');
      const chunks=[]; for await(const chunk of req) chunks.push(chunk);
      const input=JSON.parse(Buffer.concat(chunks).toString());
      assert.deepEqual(input.prefixes,state.storageObjects.map(name=>`${userID}/${name}`));
      state.storageDeletes+=input.prefixes.length; state.storageObjects=[];
      return send(200,[]);
    }
    assert.equal(req.url,`/auth/v1/admin/users/${userID}`);
    state.adminCalls++;
    if(req.method==='DELETE'){
      state.events.push('delete');
      if(state.failDelete)return send(503,{error:'temporary'});
      assert.equal(state.storageObjects.length,0,'Photos must be erased before Auth deletion');
      state.deletes++;state.exists=false;
      if(state.loseResponse){state.loseResponse=false;req.socket.destroy();return;}
      return send(200,{});
    }
    if(state.failRead)return send(500,{error:'temporary'});
    return send(state.exists?200:404,state.exists?{id:userID,identities:state.apple?
      [{provider:'apple',identity_data:state.missingAppleSubject?{}:{sub:appleID}}]:[{provider:'email'}]}:{error:'not_found'});
  } catch(error){fixtureError=error;res.writeHead(500);res.end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const base=`http://127.0.0.1:${server.address().port}`;
const env={SUPABASE_URL:base,SUPABASE_ANON_KEY:'test-public-key',SUPABASE_SERVICE_ROLE_KEY:'test-service-key',
  APPLE_CLIENT_ID:clientID,APPLE_TEAM_ID:teamID,APPLE_KEY_ID:keyID,APPLE_PRIVATE_KEY:await exportPKCS8(clientPair.privateKey)};
let handler;
globalThis.Deno={env:{get:key=>env[key]},serve:fn=>{handler=fn;}};
const source=(await readFile(path.join(root,'supabase/functions/delete-account/index.ts'),'utf8'))
  .replace('npm:jose@6.1.3',joseURL)
  .replace('const appleOrigin = "https://appleid.apple.com";',`const appleOrigin = ${JSON.stringify(`${base}/apple`)};`);
const scratch=path.join(root,'work/social-edge-tests');await mkdir(scratch,{recursive:true});
const file=path.join(scratch,'delete-account-under-test.mts');await writeFile(file,source);
await import(pathToFileURL(file).href);
const token=async(overrides={})=>new SignJWT({session_id:sessionID}).setProtectedHeader({alg:'ES256',kid:'integration'})
  .setSubject(userID).setIssuer(overrides.issuer??`${base}/auth/v1`).setAudience(overrides.audience??'authenticated')
  .setExpirationTime(overrides.expiry??'5m').sign(privateKey);
const invoke=async(value,body={})=>{
  const response=await handler(new Request(`${base}/functions/v1/delete-account`,{method:'POST',
    headers:{Authorization:`Bearer ${value}`,'Content-Type':'application/json'},body:JSON.stringify(body)}));
  if(fixtureError)throw fixtureError;
  return response;
};
const codeBody={apple_authorization_code:'fresh-apple-code',apple_nonce:nonce};
let cases=0;
const test=async(name,run)=>{state=defaults();await run();cases++;console.log(`PASS ${name}`);};
try{
  const valid=await token();
  await test('email-only deletion and repeat confirmation',async()=>{
    let response=await invoke(valid);assert.equal(response.status,200);
    assert.deepEqual(await response.json(),{deleted:true,apple_revocation:'not_required'});
    response=await invoke(valid);assert.equal(response.status,200);assert.deepEqual(await response.json(),{deleted:true});
    assert.equal(state.deletes,1);assert.equal(state.appleExchanges,0);
  });
  await test('profile photos are erased before account deletion',async()=>{
    state.storageObjects=['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg'];
    assert.equal((await invoke(valid)).status,200);assert.equal(state.storageDeletes,2);assert.equal(state.deletes,1);
  });
  await test('photo cleanup failure preserves account for a safe retry',async()=>{
    state.storageObjects=['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg'];state.failStorage=true;
    assert.equal((await invoke(valid)).status,503);assert.equal(state.deletes,0);assert.equal(state.exists,true);
    state.failStorage=false;assert.equal((await invoke(valid)).status,200);assert.equal(state.storageDeletes,1);
  });
  await test('lost response retries also remove orphaned profile photos',async()=>{
    state.exists=false;state.storageObjects=['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg'];
    assert.equal((await invoke(valid)).status,200);assert.equal(state.storageDeletes,1);assert.equal(state.deletes,0);
  });
  await test('invalid Supabase tokens never reach admin API',async()=>{
    assert.equal((await invoke('not-a-signed-token')).status,401);
    assert.equal((await invoke(await token({issuer:'https://attacker.invalid/auth/v1'}))).status,401);
    assert.equal((await invoke(await token({audience:'service_role'}))).status,401);
    assert.equal((await invoke(await token({expiry:'-1m'}))).status,401);
    const other=await generateKeyPair('ES256');
    const forged=await new SignJWT({session_id:sessionID}).setProtectedHeader({alg:'ES256',kid:'integration'})
      .setSubject(userID).setIssuer(`${base}/auth/v1`).setAudience('authenticated').setExpirationTime('5m').sign(other.privateKey);
    assert.equal((await invoke(forged)).status,401);assert.equal(state.adminCalls,0);
  });
  await test('unavailable identity and revoked session never delete',async()=>{
    state.failRead=true;assert.equal((await invoke(valid)).status,503);
    state.failRead=false;state.allowed=false;assert.equal((await invoke(valid)).status,401);assert.equal(state.deletes,0);
  });
  await test('lost deletion response safely confirms on retry',async()=>{
    state.loseResponse=true;assert.equal((await invoke(valid)).status,503);assert.equal(state.exists,false);
    assert.equal((await invoke(valid)).status,200);assert.equal(state.deletes,1);
  });
  await test('Apple account requires reauthorization and explicit manual alternative',async()=>{
    state.apple=true;let response=await invoke(valid);assert.equal(response.status,409);
    assert.deepEqual(await response.json(),{error:'apple_reauthentication_required'});assert.equal(state.deletes,0);
    response=await invoke(valid,{apple_manual_revocation:true});assert.equal(response.status,200);
    assert.deepEqual(await response.json(),{deleted:true,apple_revocation:'manual_required'});assert.equal(state.appleExchanges,0);
  });
  await test('manual alternative does not require Apple keys',async()=>{
    state.apple=true;const key=env.APPLE_PRIVATE_KEY;delete env.APPLE_PRIVATE_KEY;
    try{assert.equal((await invoke(valid,{apple_manual_revocation:true})).status,200);}finally{env.APPLE_PRIVATE_KEY=key;}
  });
  await test('signed Apple identity and nonce verified before revoke and delete',async()=>{
    state.apple=true;const response=await invoke(valid,codeBody);assert.equal(response.status,200);
    assert.deepEqual(await response.json(),{deleted:true,apple_revocation:'revoked'});
    assert.deepEqual(state.events,['authorize','exchange','revoke','delete']);
  });
  for(const [field,value] of [['appleSubject','other-person'],['appleNonce','wrong-nonce'],
    ['appleIssuer','https://attacker.invalid'],['appleAudience','another.app'],['appleExpiry','-1m'],
    ['badAppleSignature',true],['missingAppleClaims',true]]){
    await test(`Apple ${field} mismatch cannot revoke or delete`,async()=>{
      state.apple=true;state[field]=value;const response=await invoke(valid,codeBody);
      assert.equal(response.status,403);assert.deepEqual(await response.json(),{error:'apple_identity_mismatch'});
      assert.equal(state.deletes,0);assert.equal(state.appleRevokes,0);
    });
  }
  await test('Apple authorization code is re-requested when already consumed',async()=>{
    state.apple=true;state.exchangeStatus=400;const response=await invoke(valid,codeBody);
    assert.equal(response.status,409);assert.deepEqual(await response.json(),{error:'apple_reauthentication_required'});
    assert.equal(state.deletes,0);
  });
  await test('Apple client/configuration errors do not request another authorization',async()=>{
    state.apple=true;state.exchangeStatus=400;
    for(const code of ['invalid_client','unauthorized_client','invalid_request','unsupported_grant_type','invalid_scope','unknown_error',undefined]){
      state.exchangeError=code;const response=await invoke(valid,codeBody);
      assert.equal(response.status,503,`Apple ${code} is a service/configuration failure`);
      assert.deepEqual(await response.json(),{error:'apple_revocation_unavailable'});
    }
    assert.equal(state.deletes,0);assert.equal(state.appleRevokes,0);
  });
  await test('malformed Apple exchange error remains unavailable without deleting',async()=>{
    state.apple=true;state.exchangeStatus=400;state.malformedExchangeError=true;
    const response=await invoke(valid,codeBody);assert.equal(response.status,503);
    assert.deepEqual(await response.json(),{error:'apple_revocation_unavailable'});
    assert.equal(state.deletes,0);assert.equal(state.appleRevokes,0);
  });
  await test('Apple service failure remains pending with manual alternative available',async()=>{
    state.apple=true;state.revokeStatus=503;const response=await invoke(valid,codeBody);
    assert.equal(response.status,503);assert.deepEqual(await response.json(),{error:'apple_revocation_unavailable'});
    assert.equal(state.deletes,0);assert.equal((await invoke(valid,{apple_manual_revocation:true})).status,200);
  });
  await test('Apple-linked lost response is idempotent without another code exchange',async()=>{
    state.apple=true;state.loseResponse=true;assert.equal((await invoke(valid,codeBody)).status,503);
    assert.equal((await invoke(valid,codeBody)).status,200);assert.equal(state.appleExchanges,1);assert.equal(state.deletes,1);
  });
  await test('revoked session cannot call Apple even with a fresh code',async()=>{
    state.apple=true;state.allowed=false;assert.equal((await invoke(valid,codeBody)).status,401);
    assert.equal(state.appleExchanges,0);assert.equal(state.deletes,0);
  });
  await test('email-only account cannot revoke an unrelated Apple identity',async()=>{
    assert.equal((await invoke(valid,codeBody)).status,400);assert.equal(state.appleExchanges,0);assert.equal(state.deletes,0);
  });
  await test('malformed body, nonce, conflicting intent, and oversized input rejected',async()=>{
    for(const body of [[],null,{user_id:userID},{apple_nonce:nonce},{apple_authorization_code:'fresh-apple-code'},
      {...codeBody,apple_nonce:'short'},{...codeBody,apple_manual_revocation:true},
      {apple_manual_revocation:'true'},{apple_authorization_code:'a'.repeat(10000),apple_nonce:nonce}]){
      assert.equal((await invoke(valid,body)).status,400);
    }
    assert.equal(state.deletes,0);assert.equal(state.appleExchanges,0);
  });
  await test('missing trusted Apple subject is not inferred from request',async()=>{
    state.apple=true;state.missingAppleSubject=true;assert.equal((await invoke(valid,codeBody)).status,503);
    assert.equal(state.appleExchanges,0);assert.equal(state.deletes,0);
  });
  console.log(`PASS: ${cases} deletion security scenarios; actual handler, real ES256/RS256 signatures, local HTTP services only.`);
}finally{await new Promise(resolve=>server.close(resolve));}
