// Server-only, read-only metadata. Never use a service-role key for link previews.
export function createInvitationLookup({ serviceURL, publicAPIKey }, fetcher = fetch) {
  let endpoint;
  try {
    const url = new URL(serviceURL);
    if (url.protocol !== "https:" || url.username || url.password || url.pathname !== "/" || url.search || url.hash) return async () => null;
    const isPublishable = /^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(publicAPIKey ?? "");
    let isAnon = false;
    if (!isPublishable && publicAPIKey?.split(".").length === 3) {
      isAnon = JSON.parse(Buffer.from(publicAPIKey.split(".")[1], "base64url").toString()).role === "anon";
    }
    if (!isPublishable && !isAnon) return async () => null;
    endpoint = new URL("/rest/v1/rpc/invitation_link_metadata", url);
  } catch { return async () => null; }
  return async token => {
    if (!/^[0-9a-f]{64}$/.test(token)) return null;
    try {
      const response = await fetcher(endpoint, {
        method: "POST", headers: { apikey: publicAPIKey, "content-type": "application/json" },
        body: JSON.stringify({ p_token: token }), signal: AbortSignal.timeout(1500), redirect: "error",
      });
      if (!response.ok) return null;
      return (await response.json())?.display_name ?? null;
    } catch { return null; }
  };
}
