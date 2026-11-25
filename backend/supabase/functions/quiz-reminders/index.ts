import { createHandler } from "./sender.ts";

Deno.serve(createHandler({
  url: Deno.env.get("SUPABASE_URL"), service: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  secret: Deno.env.get("QUIZ_WORKER_SECRET"), team: Deno.env.get("APNS_TEAM_ID"),
  topic: Deno.env.get("APNS_TOPIC"),
  sandboxKeyId: Deno.env.get("APNS_SANDBOX_KEY_ID"), sandboxPem: Deno.env.get("APNS_SANDBOX_PRIVATE_KEY"),
  keyId: Deno.env.get("APNS_KEY_ID"), pem: Deno.env.get("APNS_PRIVATE_KEY"),
}));
