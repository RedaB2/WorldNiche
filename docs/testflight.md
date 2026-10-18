# Public beta

Use an external TestFlight group called **WorldNiche Public Beta**, with a public signup link. Start with 100 places so feedback and profile reviews stay manageable. Do not replace this with an internal or invite-only group. Apple's external beta review must approve the build before people can install it.

## Beta description

A little more world, every day. Spin the globe, find a song, catch up on local news, and discover small details about cultures around the world. Save places you're curious about and see what your friends have explored.

## What to test

- Explore Morocco, spin to another country, search the Atlas, and save a place.
- Refresh music, news, and local discoveries independently. Tell us when a source fails or a discovery repeats too often.
- Try Sign in with Apple or the six-digit email code. Close and reopen the app to check that you stay signed in.
- Choose a profile symbol or submit a name/photo for review. Friends should see only approved content.
- Share a friend invitation, open it from Messages, and check that it connects both accounts. Try exploration sharing, removing a friend, reporting, and blocking.
- If you create a disposable account specifically for testing, try data export and account deletion. Deletion is permanent, so use an account you intend to remove.

Send feedback through TestFlight or the contact at [worldniche.app/support](https://worldniche.app/support). Do not include passwords, sign-in codes, or invitation tokens in public bug reports.

## Review notes

Exploration works without an account. Sign-in is optional for friends and cloud sharing. The app supports native Sign in with Apple and email OTP; there are no passwords, purchases, ads, or tracking SDKs. Exploration sharing starts off. Names and photos require operator review before sharing. Settings contains the privacy policy, support, community guidelines, export, device clear, and account deletion.

Provide any private reviewer access details only in App Store Connect. Do not commit credentials or a real user's friend invitation. Keep the hosted service, SMTP delivery, moderation queue, and support inbox available during review.

## Current state

October 18, 2026: Release archive 1.0 (1) builds with the configured service and passes static configuration checks. The warm/cold invitation simulator test passes. App Store Connect still blocks app creation and API access with an agreement error, although the Developer account shows the agreement accepted today. The App Store provisioning profile is prepared using the existing distribution certificate. No build has been uploaded or submitted to external beta review, and no public TestFlight link exists yet.
