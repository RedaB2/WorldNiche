import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const landing = new URL('../../landing-site/', import.meta.url);

test('public account help describes Apple sign-in without removed email recovery', async () => {
  const support = await readFile(new URL('support.html', landing), 'utf8');
  const security = await readFile(new URL('security.html', landing), 'utf8');
  assert.match(support, /I can’t sign in with Apple/);
  assert.match(support, /Apple Account in iPhone Settings/);
  assert.match(security, /WorldNiche uses Sign in with Apple/);
  for (const content of [support, security]) {
    assert.doesNotMatch(content, /email code|recover access with a one-time code|resend option|six-digit sign-in code/i);
    assert.match(content, /boutayeb\.reda@icloud\.com/);
  }
});

test('privacy copy retains account and deletion disclosures without promising email recovery', async () => {
  const privacy = await readFile(new URL('privacy.html', landing), 'utf8');
  assert.match(privacy, /Sign in with Apple may provide a private relay email/);
  assert.match(privacy, /account deletion/i);
  assert.doesNotMatch(privacy, /delivers recovery codes for existing email accounts/i);
});
