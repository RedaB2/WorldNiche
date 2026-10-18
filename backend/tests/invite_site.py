#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest

script=Path(__file__).resolve().parents[1]/'scripts/build_invite_site.py'
spec=importlib.util.spec_from_file_location('invite_builder',script)
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
class InvitationSiteTests(unittest.TestCase):
 def test_rejects_unowned_placeholder_and_injection_hosts(self):
  for host in ['friends.example.com','localhost','friends.test','https://host.invalid/a','bad-host/attack','a..com','a.-b.com']:
   with self.subTest(host=host), tempfile.TemporaryDirectory() as d:
    with self.assertRaises(ValueError):builder.build(host,'ABCDEFGHIJ','io.worldniche.app','https://apps.apple.com/app/id123',Path(d))
 def test_source_has_no_remote_calls_or_token_storage(self):
  js=(script.parents[2]/'apps/web/invite-site/invite.js').read_text()
  for forbidden in ['fetch(', 'localStorage', 'document.cookie', 'sendBeacon', 'eval(']:self.assertNotIn(forbidden,js)
 def test_source_defines_no_fictional_deployed_association(self):
  self.assertFalse((script.parents[2]/'apps/web/invite-site/.well-known/apple-app-site-association').exists())
if __name__=='__main__':unittest.main()
