#!/usr/bin/env python3
"""Exercise provider budgets and upload churn against disposable PostgreSQL only."""
import argparse
import concurrent.futures
import json
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--psql', default='psql')
parser.add_argument('--socket', required=True)
parser.add_argument('--port', default='55433')
a = parser.parse_args()
command = [a.psql, '-h', a.socket, '-p', a.port, '-d', 'postgres', '-Atq', '-v', 'ON_ERROR_STOP=1']
alice = '00000000-0000-0000-0000-000000000001'
bob = '00000000-0000-0000-0000-000000000002'
checks = 0


def run(sql, *, role=None, user=None, denied=False):
    prefix = f'set role {role};\n' if role else ''
    if user:
        prefix = 'set role authenticated;\n'
        prefix += "set request.jwt.claims='" + json.dumps({'sub': user, 'session_id': '1' + user[1:]}) + "';\n"
    result = subprocess.run(command, input=prefix + sql, text=True, capture_output=True, timeout=15)
    if denied:
        assert result.returncode != 0, f'Unexpected authorization: {sql}'
        return result.stderr
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def expect(condition, message):
    global checks
    assert condition, message
    checks += 1


def scalar(sql):
    return run('select ' + sql + ';')


def reset():
    run("delete from public.wn_profiles; delete from storage.objects; delete from wn_private.rate_events; "
        "truncate wn_private.profile_check_reservations; "
        "update wn_private.profile_check_limits set enabled=true,user_per_minute=4,user_per_hour=12,user_per_day=30,"
        "global_per_minute=30,global_per_hour=300,global_per_day=1000,max_revision_attempts=5;")


def fixture(user=alice, name='Initial Name'):
    run(f"insert into auth.users(id,email,email_confirmed_at) values('{user}','fixture@example.test',now()) on conflict do nothing; "
        f"insert into auth.sessions(id,user_id) values('{'1' + user[1:]}','{user}') on conflict do nothing;")
    run(f"select public.update_my_profile('{name}','globe',false); select public.set_profile_check_consent(true);", user=user)


def edit(name, user=alice):
    run(f"select public.update_my_profile('{name}','globe',false);", user=user)


def claim(user=alice):
    return json.loads(run(f"select public.claim_profile_checks('{user}',2);", role='service_role'))


def reserve(job):
    return json.loads(run(f"select public.reserve_profile_check('{job['user_id']}','{job['kind']}','{job['revision']}','{job['claim_token']}');", role='service_role'))


def finish(job, outcome='retry'):
    return json.loads(run(f"select public.finish_profile_check('{job['user_id']}','{job['kind']}','{job['revision']}','{job['claim_token']}','{outcome}');", role='service_role'))


def due(user=alice):
    run(f"update wn_private.profile_check_jobs set available_at=now()-interval '1 second' where user_id='{user}';")


def count():
    return int(scalar('count(*) from wn_private.profile_check_reservations'))


def held(sql):
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    process.stdin.write('begin;\n' + sql + "\nselect 'LOCK_HELD';\nselect pg_sleep(1);\ncommit;\n")
    process.stdin.close()
    for line in process.stdout:
        if line.strip() == 'LOCK_HELD':
            return process
    raise AssertionError(process.stderr.read())


reset()
fixture()
for role in ('anon', 'authenticated'):
    for sql in (
        f"select public.reserve_profile_check('{alice}','name',gen_random_uuid(),gen_random_uuid());",
        f"select wn_private.reserve_profile_check('{alice}','name',gen_random_uuid(),gen_random_uuid());",
        'select * from wn_private.profile_check_limits;',
        'update wn_private.profile_check_limits set enabled=false;',
        'select * from wn_private.profile_check_reservations;',
        'select wn_private.prune_profile_check_reservations();',
    ):
        expect('permission denied' in run(sql, role=role, denied=True), f'{role} cannot access operator controls')
run('update wn_private.profile_check_limits set enabled=true;', role='service_role')
job = claim()[0]
expect(finish(job, 'approve') == {'applied': False}, 'No provider reservation means no approval')
expect(reserve(job) == {'allowed': True, 'reason': 'allowed'}, 'First reservation is allowed')
expect(reserve(job) == {'allowed': False, 'reason': 'reserved'}, 'A claim is single use')
expect(count() == 1, 'Replay cannot charge or call provider twice')
expect(finish(job, 'approve') == {'applied': True}, 'Reserved approval publishes')
expect(scalar(f"display_name from public.wn_profiles where id='{alice}'") == 'Initial Name', 'Approved name is immediately visible')

# Storage failures and invalid images can retry or hold before external disclosure.
for outcome in ('retry', 'review'):
    edit('Preprovider ' + outcome)
    job = claim()[0]
    expect(finish(job, outcome) == {'applied': True}, 'Pre-provider failures may finish without reservation')
expect(count() == 1, 'Pre-provider failures consume no provider budget')

# Every current-state gate is rechecked at the external-call boundary.
for change in ('consent', 'revision', 'restricted', 'deleting', 'lease', 'version'):
    reset()
    fixture()
    job = claim()[0]
    if change == 'consent':
        run('select public.set_profile_check_consent(false);', user=alice)
    elif change == 'revision':
        edit('Newer Revision')
    elif change == 'restricted':
        run(f"update wn_private.profile_moderation set restricted_at=now() where user_id='{alice}';")
    elif change == 'deleting':
        run(f"update public.wn_profiles set deleting_at=now() where id='{alice}';")
    elif change == 'lease':
        run("update wn_private.profile_check_jobs set lease_until=now()-interval '1 second';")
    else:
        run("update wn_private.profile_moderation set automatic_checks_consent_version='old';")
    expect(reserve(job) == {'allowed': False, 'reason': 'stale'}, f'{change} invalidates disclosure')
    expect(count() == 0, f'{change} consumes no provider budget')

# The lease can also expire while a reservation waits for the shared budget lock.
reset()
fixture()
job = claim()[0]
run("update wn_private.profile_check_jobs set lease_until=clock_timestamp()+interval '500 milliseconds';")
process = held('select * from wn_private.profile_check_limits for update;')
expect(reserve(job)['reason'] == 'stale', 'Lease rechecked after acquiring shared lock')
expect(process.wait(timeout=10) == 0 and count() == 0, 'Expired lock wait never charges')

# All six ceilings are rolling windows. Expiry is computed, not a fixed reset.
for scope in ('user', 'global'):
    for window, seconds in (('minute', 60), ('hour', 3600), ('day', 86400)):
        reset()
        fixture()
        if scope == 'global':
            fixture(bob, 'Bob Initial')
        run('update wn_private.profile_check_limits set user_per_minute=100,user_per_hour=100,user_per_day=100,'
            'global_per_minute=100,global_per_hour=100,global_per_day=100; '
            f'update wn_private.profile_check_limits set {scope}_per_{window}=1;')
        job = claim()[0]
        expect(reserve(job)['allowed'], f'{scope} {window}: first request allowed')
        finish(job)
        due()
        candidate = claim(bob if scope == 'global' else alice)[0]
        result = reserve(candidate)
        expect(result['reason'] == 'budget' and not result['allowed'], f'{scope} {window} cap enforced')
        expect(count() == 1, 'Denied reservation adds no charge')
        expect(scalar(f"state='retry' and claim_token is null and lease_until is null and available_at>now() from wn_private.profile_check_jobs where user_id='{candidate['user_id']}'") == 't', 'Cooldown durably releases the claim')
        expect(claim(candidate['user_id']) == [], 'Cron cannot reclaim before allowance')
        run(f"update wn_private.profile_check_reservations set happened_at=now()-interval '{seconds + 1} seconds';")
        due(candidate['user_id'])
        expect(reserve(claim(candidate['user_id'])[0])['allowed'], f'{scope} {window} automatically resumes after expiry')

# Retrying failures is charged and bounded. Consent toggles do not reset attempts.
reset()
fixture()
run('update wn_private.profile_check_limits set user_per_minute=10;')
for attempt in range(5):
    due()
    job = claim()[0]
    expect(reserve(job)['allowed'], 'Each retry gets its own charged reservation')
    expect(finish(job)['applied'], 'Retry result persists')
expect(count() == 5, 'All failed attempts are charged')
expect(scalar("state='review' and review_reason='attempts' and provider_attempts=5 from wn_private.profile_check_jobs") == 't', 'Fifth failed request holds for human review')
run('select public.set_profile_check_consent(false); select public.set_profile_check_consent(true);', user=alice)
expect(claim() == [], 'Consent toggling cannot escape exhausted human review')
run("update wn_private.profile_check_jobs set state='queued',available_at=now();")
expect(reserve(claim()[0])['reason'] == 'attempts', 'Reservation also enforces attempt cap independently')
edit('A New Revision')
expect(scalar('provider_attempts from wn_private.profile_check_jobs') == '0' and count() == 5, 'New revision resets only its own attempts')

# A lost response and expired lease are charged too; reacquiring cannot refund.
job = claim()[0]
expect(reserve(job)['allowed'], 'First claim before simulated worker crash')
run("update wn_private.profile_check_jobs set lease_until=now()-interval '1 second';")
replacement = claim()[0]
expect(replacement['claim_token'] != job['claim_token'], 'Expired lease gets a new claim')
expect(reserve(replacement)['allowed'] and count() == 7, 'Abandoned provider request remains charged')

# Latest accepted edit is the only revision that can publish after cooldown.
reset()
fixture()
job = claim()[0]
reserve(job)
finish(job, 'approve')
run('update wn_private.profile_check_limits set user_per_minute=1;')
edit('Throttled Older Name')
older = claim()[0]
expect(reserve(older)['reason'] == 'budget', 'New edit waits for cooldown')
edit('Latest Pending Name')
latest = claim()[0]
expect(reserve(latest)['reason'] == 'budget' and count() == 1, 'Replacement does not reset account budget')
expect(scalar(f"display_name from public.wn_profiles where id='{alice}'") == 'Initial Name', 'Cooldown preserves approved profile')
run("update wn_private.profile_check_reservations set happened_at=now()-interval '61 seconds';")
due()
resumed = claim()[0]
expect(resumed['revision'] == latest['revision'] and resumed['text'] == 'Latest Pending Name', 'Cron resumes newest pending revision')
expect(reserve(resumed)['allowed'] and finish(resumed, 'approve')['applied'], 'Latest revision publishes after automatic retry')
expect(not finish(older, 'approve')['applied'], 'Older revision never publishes later')

# Photo replacements follow the same automatic cooldown, using the latest file.
reset()
fixture()
job = claim()[0]
reserve(job)
finish(job, 'approve')
run('update wn_private.profile_check_limits set user_per_minute=1;')
photo_jobs = []
for _ in range(2):
    path = f'{alice}/{uuid.uuid4()}.jpg'
    run(f"insert into storage.objects(bucket_id,name,metadata) values('profile-photos','{path}','{{\"size\":1234,\"mimetype\":\"image/jpeg\"}}'); select public.set_profile_avatar('{path}');", user=alice)
    photo_jobs.append(claim()[0])
    expect(reserve(photo_jobs[-1])['reason'] == 'budget', 'Changing photo cannot reset provider budget')
expect(scalar(f"avatar_path is null from public.wn_profiles where id='{alice}'") == 't', 'Throttled photo remains private')
run("update wn_private.profile_check_reservations set happened_at=now()-interval '61 seconds';")
due()
resumed = claim()[0]
expect(resumed['kind'] == 'photo' and resumed['revision'] == photo_jobs[-1]['revision'] and resumed['photo_path'] == path, 'Only newest photo resumes after cooldown')
expect(reserve(resumed)['allowed'] and finish(resumed, 'approve')['applied'], 'Newest photo can publish after automatic retry')
expect(scalar(f"avatar_path from public.wn_profiles where id='{alice}'") == path and not finish(photo_jobs[0], 'approve')['applied'], 'Old photo response cannot overwrite newest approved photo')

# The kill switch defers without billing; re-enabling resumes through the queue.
reset()
fixture()
job = claim()[0]
run('update wn_private.profile_check_limits set enabled=false;', role='service_role')
expect(reserve(job)['reason'] == 'disabled' and count() == 0, 'Global kill switch prevents provider traffic')
expect(claim() == [], 'Disabled request is durably deferred')
run('update wn_private.profile_check_limits set enabled=true;', role='service_role')
due()
expect(reserve(claim()[0])['allowed'], 'Re-enabled checks resume')

# Removing an account does not free its global quota, including recreation.
run('update wn_private.profile_check_limits set global_per_minute=1;')
run(f"delete from auth.users where id='{alice}';")
expect(count() == 1 and scalar('user_id is null from wn_private.profile_check_reservations') == 't', 'Deleted account leaves only anonymous global charge')
fixture()
expect(reserve(claim()[0])['reason'] == 'budget', 'Delete and recreate cannot bypass shared budget')
run("insert into wn_private.profile_check_reservations(happened_at) values(now()-interval '26 hours'),(now()-interval '24 hours 30 minutes');")
expect(run('select wn_private.prune_profile_check_reservations();', role='service_role') == '1', 'Housekeeping removes only expired history older than 25 hours')
expect(count() == 2, 'Housekeeping retains current budget and safety margin')

# Parallel calls must serialize both per-claim and cross-account decisions.
reset()
fixture()
job = claim()[0]
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
    results = list(pool.map(reserve, [job] * 10))
expect(sum(result['allowed'] for result in results) == 1 and count() == 1, 'Ten parallel copies of a claim issue one provider request')
expect(all(result['reason'] in ('allowed', 'reserved') for result in results), 'Parallel duplicates are explicit replays')
reset()
fixture()
fixture(bob, 'Bob Concurrent')
run('update wn_private.profile_check_limits set global_per_minute=1;')
jobs = [claim()[0], claim(bob)[0]]
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(reserve, jobs))
expect(sorted(result['reason'] for result in results) == ['allowed', 'budget'] and count() == 1, 'Two accounts cannot overshoot global budget concurrently')

# Name and photo claims for the same account share the same provider budget.
reset()
fixture()
path = f'{alice}/{uuid.uuid4()}.jpg'
run(f"insert into storage.objects(bucket_id,name,metadata) values('profile-photos','{path}','{{\"size\":1234,\"mimetype\":\"image/jpeg\"}}'); select public.set_profile_avatar('{path}');", user=alice)
run('update wn_private.profile_check_limits set user_per_minute=1;')
jobs = claim()
expect(len(jobs) == 2, 'Both content kinds have independent jobs')
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(reserve, jobs))
expect(sorted(result['reason'] for result in results) == ['allowed', 'budget'] and count() == 1, 'Parallel name and photo checks cannot overshoot account budget')

# Actual INSERT and DELETE churn proves object count is not an upload budget.
reset()
fixture()
for _ in range(6):
    path = f'{alice}/{uuid.uuid4()}.jpg'
    run(f"insert into storage.objects(bucket_id,name,metadata) values('profile-photos','{path}','{{\"size\":1234,\"mimetype\":\"image/jpeg\"}}'); delete from storage.objects where name='{path}';", user=alice)
expect(scalar('count(*) from storage.objects') == '0', 'Repeated uploads were deleted')
expect(scalar("count(*) from wn_private.rate_events where action like 'avatar_upload_%'") == '18', 'Delete never refunds upload counters')
upload = f"insert into storage.objects(bucket_id,name,metadata) values('profile-photos','{alice}/{uuid.uuid4()}.jpg','{{\"size\":1234,\"mimetype\":\"image/jpeg\"}}');"
expect('Please wait before trying again.' in run(upload, user=alice, denied=True), 'Seventh upload within minute is denied')
expect('PT429' in run('\\set VERBOSITY verbose\n' + upload, user=alice, denied=True), 'Storage exposes a distinct quota error code')
run('select count(*) from storage.objects;', user=alice)
expect(scalar("count(*) from wn_private.rate_events where action like 'avatar_upload_%'") == '18', 'Reads and rejected uploads consume no upload quota')
for window, cap, age in (('hour', 20, '5 minutes'), ('day', 40, '2 hours')):
    run("delete from wn_private.rate_events where action like 'avatar_upload_%'; "
        f"insert into wn_private.rate_events(user_id,action,happened_at) select '{alice}','avatar_upload_{window}',now()-interval '{age}' from generate_series(1,{cap});")
    expect('Please wait before trying again.' in run(upload, user=alice, denied=True), f'Rolling upload {window} ceiling enforced')
run("update wn_private.rate_events set happened_at=now()-interval '25 hours';")
run(upload, user=alice)
expect(scalar('count(*) from storage.objects') == '1', 'Upload resumes after rolling allowance expires')
for restricted in ('restricted', 'deleting'):
    run("delete from wn_private.rate_events where action like 'avatar_upload_%';")
    if restricted == 'restricted':
        run(f"update wn_private.profile_moderation set restricted_at=now() where user_id='{alice}';")
    else:
        run(f"update wn_private.profile_moderation set restricted_at=null where user_id='{alice}'; update public.wn_profiles set deleting_at=now() where id='{alice}';")
    forbidden_upload = f"insert into storage.objects(bucket_id,name) values('profile-photos','{alice}/{uuid.uuid4()}.jpg');"
    expect('row-level security' in run(forbidden_upload, user=alice, denied=True), f'{restricted} accounts cannot upload')
run(f"update public.wn_profiles set deleting_at=null where id='{alice}'; delete from storage.objects; "
    f"insert into storage.objects(bucket_id,name) select 'profile-photos','{alice}/'||gen_random_uuid()||'.jpg' from generate_series(1,20);")
expect('row-level security' in run(upload, user=alice, denied=True), 'Existing 20-object quota remains enforced')
reset()
print(f'PASS: {checks} moderation abuse assertions, including concurrent reservations, rolling budgets, newest revision retry, finite attempts, deletion, roles, and upload churn.')
