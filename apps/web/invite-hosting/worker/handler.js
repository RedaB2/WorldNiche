export const securityHeaders = {
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "permissions-policy": "camera=(), microphone=(), geolocation=()",
  "content-security-policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'; font-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
};

function matchesTag(value, tag) {
  return value?.split(",").some((candidate) => candidate.trim() === "*" || candidate.trim().replace(/^W\//, "") === tag);
}

function requestedRange(value, size) {
  const match = /^bytes=(\d*)-(\d*)$/.exec(value);
  if (!match || (!match[1] && !match[2]) || size === 0) return null;
  const first = match[1] ? Number(match[1]) : null;
  const last = match[2] ? Number(match[2]) : null;
  if ((first !== null && !Number.isSafeInteger(first)) || (last !== null && !Number.isSafeInteger(last))) return null;
  if (first === null) return last > 0 ? [Math.max(0, size - last), size - 1] : null;
  if (first >= size || (last !== null && last < first)) return null;
  return [first, last === null ? size - 1 : Math.min(last, size - 1)];
}

// Decode only the requested span. An iPhone video probe for bytes=0-1 must not
// decode the entire MP4 or keep the video in an isolate-wide decoded cache.
function decodeBytes(base64, start, end) {
  if (end < start) return new Uint8Array();
  const alignedStart = Math.floor(start / 3) * 4;
  const alignedEnd = Math.ceil((end + 1) / 3) * 4;
  const decoded = atob(base64.slice(alignedStart, alignedEnd));
  const offset = start % 3;
  const bytes = new Uint8Array(end - start + 1);
  for (let index = 0; index < bytes.length; index++) bytes[index] = decoded.charCodeAt(offset + index);
  return bytes;
}

function escapeHTML(text) {
  return text.replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
}

export function createHandler({ routes, blobs, association }, { invitationName = async () => null } = {}) {
  return {
    async fetch(request) {
      const url = new URL(request.url);
      const headers = new Headers(securityHeaders);
      if (request.method !== "GET" && request.method !== "HEAD") {
        headers.set("allow", "GET, HEAD");
        headers.set("cache-control", "no-store");
        return new Response("Method not allowed", { status: 405, headers });
      }

      let route;
      let invitationToken;
      if (url.pathname === "/.well-known/apple-app-site-association" || url.pathname === "/apple-app-site-association") {
        route = association;
      } else if (/^\/invite\/[0-9a-f]{64}$/.test(url.pathname) && !url.search) {
        route = routes["/invite-template"];
        invitationToken = url.pathname.slice("/invite/".length);
      } else if (url.pathname === "/" || url.pathname === "/index.html") {
        route = routes["/"];
      } else if (url.pathname !== "/invite-template") {
        route = routes[url.pathname];
      }
      if (!route) {
        headers.set("content-type", "text/html; charset=utf-8");
        headers.set("cache-control", "no-store");
        const body = "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Link unavailable · WorldNiche</title><h1>This link isn’t available</h1><p>Ask your friend for a new invitation.</p><a href=\"/\">WorldNiche home</a></html>";
        return new Response(request.method === "HEAD" ? null : body, { status: 404, headers });
      }
      const blob = blobs[route.blob];
      headers.set("content-type", route.type);
      headers.set("cache-control", route.cache);
      if (invitationToken) {
        let name;
        try { name = await invitationName(invitationToken); } catch { /* Keep invitations usable during a preview outage. */ }
        name = typeof name === "string" ? name.trim() : "";
        if (Array.from(name).length > 32 || /[\u0000-\u001f\u007f-\u009f]/u.test(name) || name.toLowerCase() === "explorer") name = "";
        const title = name ? `Share cultures with ${name}` : "Share cultures with a friend";
        const description = name ? `Add ${name} as a friend on WorldNiche and explore cultures together.`
          : "Open this personal link to become friends on WorldNiche and explore cultures together.";
        const template = new TextDecoder().decode(decodeBytes(blob.base64, 0, blob.size - 1));
        const body = template.replace(/__INVITATION_(TITLE|DESCRIPTION)__/g,
          (_, kind) => escapeHTML(kind === "TITLE" ? title : description));
        headers.set("cache-control", "no-store");
        headers.set("content-length", String(new TextEncoder().encode(body).length));
        return new Response(request.method === "HEAD" ? null : body, { headers });
      }
      headers.set("etag", blob.etag);
      headers.set("accept-ranges", "bytes");
      headers.set("content-length", String(blob.size));
      if (matchesTag(request.headers.get("if-none-match"), blob.etag)) {
        headers.delete("content-length");
        return new Response(null, { status: 304, headers });
      }
      const range = request.headers.get("range");
      const ifRange = request.headers.get("if-range");
      if (request.method === "GET" && range && (!ifRange || ifRange === blob.etag)) {
        const selected = requestedRange(range, blob.size);
        if (!selected) {
          headers.set("content-range", `bytes */${blob.size}`);
          headers.set("content-length", "0");
          return new Response(null, { status: 416, headers });
        }
        const [start, end] = selected;
        headers.set("content-range", `bytes ${start}-${end}/${blob.size}`);
        headers.set("content-length", String(end - start + 1));
        return new Response(decodeBytes(blob.base64, start, end), { status: 206, headers });
      }
      return new Response(request.method === "HEAD" ? null : decodeBytes(blob.base64, 0, blob.size - 1), { headers });
    },
  };
}
