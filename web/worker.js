// Neon Pup download page (neonpup.bysa.app). The zip and art live in the private R2 bucket
// "neon-pup-downloads"; this Worker serves them. The app holds no credentials, so the page is public.
const FILES = {
  "/Neon-Pup.zip": { key: "Neon-Pup.zip", type: "application/zip", download: "Neon-Pup.zip", cache: "no-cache" },
  "/pup.png": { key: "pup.png", type: "image/png", cache: "public, max-age=86400" },
  "/backdrop.jpg": { key: "backdrop.jpg", type: "image/jpeg", cache: "public, max-age=86400" },
  "/icon.png": { key: "icon.png", type: "image/png", cache: "public, max-age=86400" },
  "/favicon.ico": { key: "icon.png", type: "image/png", cache: "public, max-age=86400" },
};

const HSTS = "max-age=31536000";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // Plain HTTP on Chinese networks can be rewritten in transit, so never serve anything over it.
    if (url.protocol === "http:") return Response.redirect("https://" + url.host + url.pathname, 301);
    const head = request.method === "HEAD";
    if (request.method !== "GET" && !head) {
      return new Response("", { status: 405, headers: { allow: "GET, HEAD", "strict-transport-security": HSTS } });
    }
    const file = FILES[url.pathname];
    if (file) return serveFile(request, env, file, head);
    if (url.pathname !== "/") {
      return new Response("Not found. Neon Pup lives at https://neonpup.bysa.app/\n", { status: 404, headers: {
        "content-type": "text/plain; charset=utf-8", "strict-transport-security": HSTS, "x-content-type-options": "nosniff",
      } });
    }
    return new Response(head ? null : PAGE, { headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
      "content-security-policy": "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
      "strict-transport-security": HSTS,
    } });
  },
};

async function serveFile(request, env, file, head) {
  const object = head
    ? await env.FILES.head(file.key)
    : await env.FILES.get(file.key, { range: request.headers, onlyIf: request.headers });
  if (!object) return new Response("Not found", { status: 404, headers: { "strict-transport-security": HSTS } });
  const headers = {
    "content-type": file.type, "cache-control": file.cache, "x-content-type-options": "nosniff",
    "strict-transport-security": HSTS, "accept-ranges": "bytes", etag: object.httpEtag,
    "last-modified": object.uploaded.toUTCString(),
  };
  if (file.download) headers["content-disposition"] = `attachment; filename="${file.download}"`;
  // A failed precondition comes back as metadata without a body.
  if (!head && !("body" in object)) {
    const conditionalGet = request.headers.has("if-none-match") || request.headers.has("if-modified-since");
    return new Response(null, { status: conditionalGet ? 304 : 412, headers });
  }
  const r = !head && object.range;
  if (r && request.headers.has("range")) {
    const offset = r.suffix !== undefined ? object.size - r.suffix : (r.offset ?? 0);
    const length = r.suffix !== undefined ? r.suffix : (r.length ?? object.size - offset);
    headers["content-range"] = `bytes ${offset}-${offset + length - 1}/${object.size}`;
    headers["content-length"] = String(length);
    return new Response(object.body, { status: 206, headers });
  }
  headers["content-length"] = String(object.size);
  return new Response(head ? null : object.body, { headers });
}

const PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Neon Pup</title>
<meta name="description" content="A tiny Mac menu bar helper for the internet in China. One button, a cute pup.">
<link rel="icon" href="/icon.png">
<style>
  :root {
    --night: #120f29; --raised: #211c42; --pink: #ff4fd8; --blush: #ffd6f5;
    --teal: #2ef2e0; --text: #f5f0ff; --dim: #b3abdb;
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--night); color: var(--text);
    font-family: ui-rounded, "SF Pro Rounded", system-ui, -apple-system, sans-serif; line-height: 1.5; }
  main { max-width: 560px; margin: 0 auto; padding: 24px 16px 48px; }
  .hero { position: relative; border-radius: 22px; overflow: hidden; aspect-ratio: 16 / 10;
    background: url("/backdrop.jpg") center / cover; box-shadow: 0 0 40px rgba(255, 79, 216, .25); }
  .hero img { position: absolute; left: 50%; bottom: 4%; transform: translateX(-50%); width: 46%;
    filter: drop-shadow(0 0 18px rgba(255, 79, 216, .55)); }
  h1 { font-size: 40px; margin: 22px 0 4px; color: var(--pink); text-shadow: 0 0 18px rgba(255, 79, 216, .45); }
  .tag { margin: 0 0 22px; color: var(--text); font-size: 18px; }
  .button { display: block; text-align: center; text-decoration: none; font-weight: 700; font-size: 20px;
    color: var(--night); padding: 16px; border-radius: 18px;
    background: linear-gradient(90deg, var(--pink), var(--blush)); box-shadow: 0 0 24px rgba(255, 79, 216, .5); }
  .button:focus-visible { outline: 3px solid var(--teal); outline-offset: 3px; }
  .small { color: var(--dim); font-size: 14px; text-align: center; margin: 10px 0 28px; }
  h2 { font-size: 20px; color: var(--teal); margin: 28px 0 10px; }
  ol, ul { padding-left: 22px; margin: 0; }
  li { margin: 6px 0; }
  .card { background: var(--raised); border-radius: 16px; padding: 16px 18px; }
  footer { margin-top: 36px; color: var(--dim); font-size: 13px; text-align: center; }
  a { color: var(--teal); }
  a:focus-visible { outline: 2px solid var(--teal); outline-offset: 2px; }
  .clone { display: block; background: none; padding: 0; overflow-wrap: anywhere; user-select: all; }
  code { background: var(--night); color: var(--blush); padding: 1px 6px; border-radius: 6px; font-size: 13px; }
</style>
</head>
<body>
<main>
  <div class="hero" role="img" aria-label="A lavender puppy with headphones in a neon city at night">
    <img src="/pup.png" alt="">
  </div>
  <h1>Neon Pup</h1>
  <p class="tag">A tiny Mac helper for the internet in China. One button, a cute pup.</p>
  <a class="button" href="/Neon-Pup.zip">Download for Mac</a>
  <p class="small">macOS 13 or newer. Apple silicon and Intel. About 45 MB. Notarized by Apple.</p>

  <h2>Set it up</h2>
  <div class="card"><ol>
    <li>Open the zip and drag Neon Pup into Applications.</li>
    <li>Open Neon Pup. Paste the links for your own server (<code>vless://</code> or <code>hysteria2://</code>), then press Save my servers.</li>
    <li>Click the butterfly in the menu bar and press Wake me up. The first time, your Mac asks you to allow Neon Pup once.</li>
  </ol></div>

  <h2>What it does</h2>
  <div class="card"><ul>
    <li>Sends everything through your own server while it's on. WeChat and Alipay go direct.</li>
    <li>Keeps Claude on the top server in your list, so your account doesn't hop between countries.</li>
    <li>China mode blocks the internet whenever the pup is asleep, so nothing slips out.</li>
    <li>A hotel Wi-Fi button opens login pages while Claude stays on your server, and closes once you're online.</li>
  </ul></div>

  <h2>You need your own server</h2>
  <p>Neon Pup doesn't come with one. It works with a VLESS Reality, Hysteria2 or WebSocket server you or a friend run, and asks only for the share links.</p>

  <h2>Source code</h2>
  <p>Neon Pup is open source (MIT). Read the code, check how it handles your links, or build it yourself:
    <a href="https://github.com/bysa-app/neon-pup">github.com/bysa-app/neon-pup</a></p>
  <div class="card"><code class="clone">git clone https://github.com/bysa-app/neon-pup.git</code></div>

  <footer>Made by Holinic. Your links stay in your Mac's Keychain and never leave your Mac.</footer>
</main>
</body>
</html>`;
