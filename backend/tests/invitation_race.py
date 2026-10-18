#!/usr/bin/env python3
"""Invitation races in the disposable local database, never the hosted project."""
import argparse
import json
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--psql', required=True)
parser.add_argument('--socket', required=True)
parser.add_argument('--port', default='55433')
args = parser.parse_args()
command = [args.psql, '-h', args.socket, '-p', args.port, '-d', 'postgres', '-Atq', '-v', 'ON_ERROR_STOP=1']


def claims(person):
    return f"""set role authenticated;
set request.jwt.claims='{{"sub":"00000000-0000-0000-0000-{person:012d}","session_id":"10000000-0000-0000-0000-{person:012d}"}}';
"""


def run(sql):
    return subprocess.run(command, input=sql, text=True, capture_output=True, check=True, timeout=10).stdout.strip()


def race(first, second):
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    process.stdin.write("begin;\n" + first + "\nselect 'LOCK_HELD';\nselect pg_sleep(0.3);\ncommit;\n")
    process.stdin.close()
    for line in process.stdout:
        if line.strip() == 'LOCK_HELD':
            break
    else:
        raise AssertionError(process.stderr.read())
    result = run(second)
    if process.wait(timeout=10):
        raise AssertionError(process.stderr.read())
    return result


alice = '00000000-0000-0000-0000-000000000001'
bob = '00000000-0000-0000-0000-000000000002'
run(claims(1) + "select public.update_my_profile('Alice','globe',false);")
run(claims(2) + "select public.update_my_profile('Bob','sun',false);")
token = json.loads(run(claims(1) + 'select public.create_invite();'))['token']
accept = claims(2) + f"select public.accept_invite('{token}');"

# A second launch/phone request waits for the first commit and observes exactly
# the same relationship, including when the first response was lost to the app.
assert json.loads(race(accept, accept))['status'] == 'already_friends'
assert run('select count(*) from public.wn_friendships;') == '1'
assert len(json.loads(run(claims(1) + 'select public.list_friends();'))) == 1
assert len(json.loads(run(claims(2) + 'select public.list_friends();'))) == 1

# Blocking is final in either transaction order; a raced invite cannot undo it.
block = claims(1) + f"select public.block_user('{bob}');"
race(accept, block)
assert run('select count(*) from public.wn_friendships;') == '0'
run('delete from public.wn_blocks;')
assert json.loads(race(block, accept))['status'] == 'unavailable'
assert run('select count(*) from public.wn_friendships;') == '0'
run('delete from public.wn_blocks;')

# Revoking the link before a waiting acceptance commits prevents redemption.
revoke = claims(1) + 'select public.revoke_invites();'
assert json.loads(race(revoke, accept))['status'] == 'unavailable'
assert run('select count(*) from public.wn_friendships;') == '0'

# The wrapper is volatile, so PostgREST does not expose it as a safe GET RPC.
assert run("select provolatile from pg_proc where oid='public.accept_invite(text)'::regprocedure;") == 'v'
print('PASS: concurrent invitation replay, reciprocal friendship, both block orders, revocation race, and POST-only RPC volatility.')
