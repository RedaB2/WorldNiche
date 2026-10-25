import {createHandler} from "./handler.ts";

// Deploy with gateway JWT verification disabled: the scheduled worker uses a
// scoped secret. User calls are authenticated by the session-checking RPC.
Deno.serve(createHandler({
  supabaseURL: Deno.env.get("SUPABASE_URL"),
  publicKey: Deno.env.get("SUPABASE_ANON_KEY"),
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  openaiKey: Deno.env.get("OPENAI_API_KEY"),
  workerSecret: Deno.env.get("WORLDNICHE_MODERATION_WORKER_SECRET"),
}));
