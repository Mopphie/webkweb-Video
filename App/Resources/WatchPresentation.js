(() => {
  "use strict";
  if (globalThis.__webkwebWatch || window.top !== window) return;
  const marker = "data-webkweb-watch";
  const styleID = "webkweb-watch-presentation";
  let enabled = true;
  const matches = value => {
    try {
      const url = new URL(value);
      return ["https:", "http:"].includes(url.protocol) && !url.username && !url.password &&
        (url.hostname === "youtube.com" || url.hostname.endsWith(".youtube.com")) &&
        url.pathname === "/watch" && /^[A-Za-z0-9_-]{11}$/.test(url.searchParams.get("v") || "");
    } catch (_) { return false; }
  };
  // Only the site's masthead/layout is adjusted. No replacement video,
  // playback-control overlay, title, channel, comments or recommendations.
  const css = `
html[${marker}] { background:#000; color-scheme:dark; }
html[${marker}],html[${marker}] ytm-app {
  --yt-spec-base-background:#0f0f0f; --yt-spec-raised-background:#212121;
  --yt-spec-menu-background:#282828; --yt-spec-text-primary:#f1f1f1; --yt-spec-text-secondary:#aaa;
}
html[${marker}] body { margin:0!important; background:#0f0f0f; }
html[${marker}] ytm-mobile-topbar-renderer,
html[${marker}] ytm-mobile-topbar-renderer.sticky,
html[${marker}] #masthead-container,
html[${marker}] ytd-masthead { display:none!important; }
html[${marker}] ytm-app { padding-top:0!important; }
html[${marker}] #page-manager { margin-top:0!important; }
html[${marker}] ytd-watch-flexy #columns { display:block!important; }
html[${marker}] ytd-watch-flexy #primary,
html[${marker}] ytd-watch-flexy #primary-inner { width:100%!important; max-width:none!important; margin:0!important; padding:0!important; }
html[${marker}] ytd-watch-flexy #secondary { width:auto!important; margin:0!important; }
html[${marker}] #player-container-id,
html[${marker}] #player-container-outer,
html[${marker}] ytm-player { width:100%!important; max-width:none!important; height:auto!important; aspect-ratio:16/9; margin:0!important; padding:0!important; }
html[${marker}] #player-container-id { top:0!important; }
html[${marker}] #player-container-id .html5-video-player:not(.ytp-fullscreen) { width:100%!important; height:100%!important; }
html[${marker}] #player-container-id video.html5-main-video { max-width:100%; object-fit:contain; }
html[${marker}] #player-container-id:fullscreen,
html[${marker}] #player-container-outer:fullscreen { aspect-ratio:auto; }
`;
  const update = () => {
    const html = document.documentElement;
    if (!html) return;
    if (!enabled || !matches(location.href)) {
      html.removeAttribute(marker);
      document.getElementById(styleID)?.remove();
      return;
    }
    html.setAttribute(marker, "");
    if (!document.getElementById(styleID) && document.head) {
      const style = document.createElement("style"); style.id = styleID; style.textContent = css;
      document.head.appendChild(style);
    }
  };
  globalThis.__webkwebWatch = {update, matches,
    setImmersive(value) { enabled = Boolean(value); update(); }
  };
  window.addEventListener("popstate", update);
  window.addEventListener("hashchange", update);
  window.addEventListener("pageshow", update);
  document.addEventListener("yt-navigate-finish", update);
  update();
})();
