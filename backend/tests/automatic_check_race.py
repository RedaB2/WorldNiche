#!/usr/bin/env python3
"""Concurrent moderation checks against the disposable database only."""
import argparse
import json
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--psql', default='psql')
parser.add_argument('--socket', required=True)
parser.add_argument('--port', default='55433')
a = parser.parse_args()
command = [a.psql, '-h', a.socket, '-p', a.port, '-d', 'postgres', '-Atq', '-v', 'ON_ERROR_STOP=1']
user_id = '00000000-0000-0000-0000-000000000001'
claims = """set role authenticated;
set request.jwt.claims='{"sub":"00000000-0000-0000-0000-000000000001","session_id":"10000000-0000-0000-0000-000000000001"}';
"""
worker = 'set role service_role;\n'

def run(sql):
    return subprocess.run(command, input=sql, text=True, capture_output=True, check=True, timeout=10).stdout.strip()

def held(sql):
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    process.stdin.write('begin;\n' + sql + "\nselect 'LOCK_HELD';\nselect pg_sleep(1);\ncommit;\n")
    process.stdin.close()
    results = []
    for line in process.stdout:
        if line.strip() == 'LOCK_HELD':
            return process, results
        if line.strip():
            results.append(line.strip())
    raise AssertionError(process.stderr.read())

def finish(process):
    if process.wait(timeout=10):
        raise AssertionError(process.stderr.read())

def claim():
    return json.loads(run(worker + f"select public.claim_profile_checks('{user_id}',2);"))

def decide(job):
    if run("select to_regprocedure('public.reserve_profile_check(uuid,text,uuid,uuid)') is not null;") == 't':
        run(worker + f"select public.reserve_profile_check('{user_id}','name','{job['revision']}','{job['claim_token']}');")
    return json.loads(run(worker + f"select public.finish_profile_check('{user_id}','name','{job['revision']}','{job['claim_token']}','approve');"))

run(claims + "select public.update_my_profile('Alice Initial','globe',false); select public.set_profile_check_consent(true);")
process, _ = held(claims + "select public.update_my_profile('Alice Fresh','globe',false);")
assert claim() == [], 'A worker must skip a revision being edited'
finish(process)
fresh = claim()[0]
assert fresh['text'] == 'Alice Fresh', fresh
assert decide(fresh)['applied'] is True

run(claims + "select public.update_my_profile('Alice Claimed','globe',false);")
process, output = held(worker + f"select public.claim_profile_checks('{user_id}',2);")
old = json.loads(output[0])[0]
run(claims + "select public.update_my_profile('Alice Latest','globe',false);")
finish(process)
assert old['text'] == 'Alice Claimed'
assert decide(old)['applied'] is False, 'A claimed snapshot cannot approve a later edit'
latest = claim()[0]
assert latest['text'] == 'Alice Latest' and latest['revision'] != old['revision']

process, _ = held(claims + 'select public.set_profile_check_consent(false);')
assert claim() == [], 'Workers must skip an in-progress consent change'
assert decide(latest)['applied'] is False, 'Revocation must invalidate in-flight approval'
finish(process)
assert claim() == []
run(f"delete from public.wn_profiles where id='{user_id}';")
print('PASS: moderation claims match locked revisions, concurrent edits invalidate stale approvals, and consent revocation wins.')
