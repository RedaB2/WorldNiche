# WorldNiche Staging

The internal TestFlight app uses bundle ID `io.worldniche.app.staging` and App Store Connect app `6839009941`. It can be installed alongside WorldNiche. Its Supabase project is `uprskkelpwqrhorwdudp` in RedaB2, US East. Keep staging accounts, push tokens, Apple keys, worker secrets and test invitations in staging. Both apps read the public country content catalog.

## Build

1. Use the same checkout and commit as the candidate. Keep the staging client settings in the ignored `WorldNiche/Resources/SocialConfiguration.staging.local.json` under `apps/ios`. Use the staging project URL and publishable key, enable Apple sign-in and use the staging project hostname for the invitation host.
2. Pass `-xcconfig apps/ios/Staging/Staging.xcconfig` to the regular WorldNiche build or archive. The override selects the staging identifier, display name, entitlements and private client resource. Staging invitations use the `worldniche-staging` URL scheme and open another installed staging app directly.
3. For an archive, use Release, the Apple Distribution identity and the `WorldNiche Staging TestFlight 2026` profile. Export for `app-store-connect` with `testFlightInternalTestingOnly` enabled and the staging identifier mapped to that profile. Check the signed application identifier, production APNs entitlement and embedded service URL in both the archive and IPA. The staging IPA must exclude `SocialConfiguration.local.json`. The production IPA must exclude `SocialConfiguration.staging.local.json`.
4. Upload to the staging app and assign the processed build to its internal **Staging Release Checks** group.

## Backend

Apply repository migrations to staging first. Select the staging project explicitly for every CLI command. Verify that `supabase db push --dry-run --remote=uprskkelpwqrhorwdudp --workdir backend` reports an up-to-date schema after deployment. Staging Auth accepts the staging bundle ID for native Sign in with Apple. Apple account deletion uses its own staging revocation key.

Follow the quiz reminder deployment instructions in [the deployment guide](../../../docs/deployment.md#daily-country-quiz-and-apple-push-reminders). Set `APNS_TOPIC` to the staging bundle ID. Use its topic-specific sandbox key for development and its topic-specific production key for TestFlight. Keep the matching worker secret in staging Edge secrets and staging Vault. The hosted clock determines the quiz day in UTC and the reminder hour in the device’s time zone.

For release acceptance, opt a staging device in, leave its quiz unfinished, open the received reminder, then check suppression after answering and removal after opting out. Use a consenting disposable account for live Apple authorization or deletion. Staging moderation requires a separate provider credential to perform automated reviews. Content that requires moderation stays pending until approved.

Promote the tested source to production through the existing website, backend and iOS release procedures. Production has a different Apple identifier, Supabase project, signing profile and APNs topic. Build the production archive from the verified commit using the production configuration, then check the signed IPA and perform a production device smoke test before App Review.
