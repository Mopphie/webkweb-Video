(() => {
  "use strict";
  if (globalThis.__webkweb) return;
  let sponsorEnabled = false, segmentID = null, segments = [], lastAddress = "", stopped = false;
  const pageID = Math.random().toString(36).slice(2);
  const attached = new WeakSet(), cycles = new WeakMap(), encrypted = new WeakSet();
  let serial = 0;
  const post = (kind, value = {}) => {
    try { window.webkit.messageHandlers.playback.postMessage({ kind, ...value }); } catch (_) {}
  };
  const videoID = () => {
    if (!/(^|\.)youtube\.com$/.test(location.hostname)) return null;
    const url = new URL(location.href);
    const id = url.pathname === "/watch" ? url.searchParams.get("v") :
      url.pathname.match(/^\/(?:shorts|embed|live)\/([\w-]+)/)?.[1];
    return /^[\w-]{11}$/.test(id || "") ? id : null;
  };
  const isAd = () => Boolean(document.querySelector(".ad-showing, .ad-interrupting"));
  const media = () => {
    const all = [...document.querySelectorAll("video,audio")];
    return all.find(v => !v.paused && !v.ended) || all.find(v => v.currentSrc && !v.ended) || all[0];
  };
  const state = () => {
    const v = media();
    const source = v?.querySelector("source");
    post("state", { title: document.title, hasMedia: Boolean(v), playing: v ? !v.paused && !v.ended : false,
      time: Number.isFinite(v?.currentTime) ? v.currentTime : 0,
      duration: Number.isFinite(v?.duration) ? v.duration : null,
      source: v?.currentSrc || "", contentType: source?.type || "",
      encrypted: v ? encrypted.has(v) || Boolean(v.mediaKeys) : false });
  };
  const seek = seconds => {
    const v = media();
    if (!v || !Number.isFinite(seconds) || !Number.isFinite(v.currentTime)) return;
    const target = v.currentTime + seconds;
    try { v.currentTime = Math.max(0, Number.isFinite(v.duration) ? Math.min(target, v.duration) : target); } catch (_) {}
    state();
  };
  function attach() {
    document.querySelectorAll("video,audio").forEach(v => {
      if (attached.has(v)) return;
      attached.add(v);
      const entry = { id: ++serial, cycle: 0, ended: false };
      cycles.set(v, entry);
      v.addEventListener("encrypted", () => { encrypted.add(v); state(); });
      v.addEventListener("play", () => {
        if (stopped) { v.pause(); return; }
        if (entry.ended) { entry.cycle++; entry.ended = false; }
        state();
      });
      v.addEventListener("pause", state);
      v.addEventListener("loadedmetadata", state);
      v.addEventListener("timeupdate", () => {
        if (!sponsorEnabled || segmentID !== videoID() || v !== media() || v.paused || v.seeking || isAd()) return;
        const match = segments.find(s => v.currentTime >= s.segment[0] && v.currentTime < s.segment[1]);
        if (match) {
          try { v.currentTime = Math.min(match.segment[1], Number.isFinite(v.duration) ? v.duration : match.segment[1]); } catch (_) {}
        }
      });
      v.addEventListener("ended", () => {
        if (entry.ended || isAd()) return;
        // Ignore small incidental elements where the page has another primary player.
        const videos = [...document.querySelectorAll("video")];
        if (v.tagName === "VIDEO" && videos.some(other => other !== v && !other.paused && !other.ended)) return;
        entry.ended = true;
        post("ended", { eventID: `${pageID}:${entry.id}:${entry.cycle}` });
        state();
      });
    });
  }
  globalThis.__webkweb = {
    setSponsorBlock(enabled) { sponsorEnabled = Boolean(enabled); if (!sponsorEnabled) { segments = []; segmentID = null; } },
    setSegments(id, value) {
      if (id !== videoID() || !Array.isArray(value)) return;
      segmentID = id;
      segments = value.filter(s => ["sponsor", "intro", "outro", "selfpromo"].includes(s.category) &&
        Array.isArray(s.segment) && s.segment.length === 2 && s.segment.every(Number.isFinite) &&
        s.segment[0] >= 0 && s.segment[1] > s.segment[0]);
    },
    pause(blockAutoplay = false) {
      stopped = Boolean(blockAutoplay);
      document.querySelectorAll("video,audio").forEach(v => v.pause());
      state();
    },
    resume() { stopped = false; const v = media(); if (v) v.play().catch(() => post("notice", { text: "Diese Seite verlangt einen Tipp auf den Videoplayer." })); },
    toggle() { const v = media(); if (!v) return; v.paused ? this.resume() : this.pause(); },
    seek,
    pip() {
      const v = media();
      if (!v || v.tagName !== "VIDEO") return post("notice", { text: "Auf dieser Seite ist kein Video verfügbar." });
      if (v.webkitSupportsPresentationMode?.("picture-in-picture")) v.webkitSetPresentationMode("picture-in-picture");
      else if (v.requestPictureInPicture) v.requestPictureInPicture().catch(() => post("notice", { text: "Die Seite oder iOS erlaubt hier kein Bild-in-Bild." }));
      else post("notice", { text: "Dieser Player unterstützt kein Bild-in-Bild." });
    },
    airplay() {
      const v = media();
      if (v?.webkitShowPlaybackTargetPicker) v.webkitShowPlaybackTargetPicker();
      else post("notice", { text: "Nutze die AirPlay-Auswahl im Kontrollzentrum oder im Videoplayer." });
    },
    state
  };
  const tick = () => {
    if (lastAddress !== location.href) {
      lastAddress = location.href; segments = []; segmentID = null;
      post("navigation", { address: location.href });
    }
    attach(); state();
  };
  post("ready");
  setInterval(tick, 1000);
  document.addEventListener("visibilitychange", tick);
  document.addEventListener("yt-navigate-finish", tick);
  tick();
})();
