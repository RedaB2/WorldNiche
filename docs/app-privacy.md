# App Privacy

Reconciled on October 29, 2026 for build 7. All twelve categories were published in App Store Connect on October 29, 2026 and verified in the browser as published by Reda Boutayeb.

All twelve categories use **App Functionality**, are **linked to the user**, and are **not used for tracking**. Optional account features still count as collection. Operational records can be correlated with authenticated requests, so they are not declared anonymous.

| Apple category | What WorldNiche or its providers process |
| --- | --- |
| Name | Chosen display name and a name shared by Sign in with Apple |
| Email Address | Apple sign-in address or private relay address; support correspondence |
| Coarse Location | Approximate country or region derived from an IP address in infrastructure logs, not GPS |
| Contacts | The in-app friend graph, invitations and blocks, not the device address book |
| Photos or Videos | Optional profile photos and moderation submissions |
| Customer Support | Help requests, reports and related correspondence |
| Other User Content | Private journal notes and optional report details |
| User ID | Authentication, profile and social account identifiers |
| Device ID | Journal sync identifier used to reconcile edits across devices |
| Product Interaction | Explored countries, bookmarks, exploration dates and service activity |
| Performance Data | Infrastructure request duration and operational performance records |
| Other Diagnostic Data | Authentication/API errors and related service diagnostics |

The release privacy manifest declares the same twelve categories. It also declares the app's own UserDefaults use under reason CA92.1. There are no tracking domains, advertising identifiers or analytics SDKs. Guest journals and on-device companion conversations are not uploaded by WorldNiche. Signed-in notes and bookmarks sync privately regardless of friend-sharing preference.

The [public privacy policy](https://worldniche.app/privacy) describes account collection, moderation consent, provider requests, IP-derived approximate location, operational logs and deletion limits. Site version 15 was published and checked live. The app's About and Settings text names Global Voices as the replacement news provider. Earlier betas still use the previous source until updated.

Sources used for the classification: [Apple's App Privacy definitions](https://developer.apple.com/app-store/app-privacy-details/), [Supabase log documentation](https://supabase.com/docs/guides/platform/logs), and [Supabase log field reference](https://supabase.com/docs/guides/observability/log-field-reference). Revisit these answers whenever collection, providers or purposes change. Published labels do not replace the remaining release checks in [App Store readiness](app-store-readiness.md).
