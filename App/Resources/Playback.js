(() => {
  "use strict";
  if (globalThis.__webkweb) return;
  const documentID = Math.random().toString(36).slice(2) + Date.now().toString(36);
  const attached = new WeakMap();
  let serial = 0, sponsorEnabled = false, categories = ["sponsor", "intro", "outro", "selfpromo"];
  let segmentID = null, segments = [], lastAddress = "", stopped = false, selected = null;
  let interactionAt = 0, lastPrimary = null, undo = null, ignoredSegment = null;
  const post = (kind, value = {}) => {
    try { window.webkit.messageHandlers.playback.postMessage({kind, documentID, address: location.href, ...value}); } catch (_) {}
  };
  const videoID = () => {
    if (!/(^|\.)youtube\.com$/.test(location.hostname)) return null;
    const url = new URL(location.href);
    const id = url.pathname === "/watch" ? url.searchParams.get("v") : url.pathname.match(/^\/(?:shorts|embed|live)\/([\w-]+)/)?.[1];
    return /^[\w-]{11}$/.test(id || "") ? id : null;
  };
  const isAd = () => Boolean(document.querySelector(".ad-showing,.ad-interrupting"));
  function nodes() {
    const result = [];
    const scan = root => {
      root.querySelectorAll("video,audio").forEach(v => result.push(v));
      // Open shadow roots are accessible; closed roots remain a platform boundary.
      root.querySelectorAll("*").forEach(node => { if (node.shadowRoot) scan(node.shadowRoot); });
    };
    scan(document);
    return result;
  }
  const area = v => {
    const r = v.getBoundingClientRect?.();
    return r ? Math.max(0, Math.min(r.right, innerWidth) - Math.max(0, r.left)) *
      Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(0, r.top)) : (v.tagName === "VIDEO" ? 10000 : 0);
  };
  function media() {
    const all = nodes();
    if (selected && all.includes(selected) && selected.currentSrc && !selected.ended) return selected;
    const videos = all.filter(v => v.tagName === "VIDEO" && v.currentSrc);
    const playable = videos.filter(v => !v.ended);
    const candidates = playable.length ? playable : videos.length ? videos : all;
    return candidates.slice().sort((a,b) => area(b) - area(a) || Number(a.paused) - Number(b.paused))[0];
  }
  function entry(v) {
    const e = attached.get(v);
    if (!e) return null;
    const sourceKey = (v.currentSrc || "") + ":" + (videoID() || "");
    if (sourceKey !== e.sourceKey) { e.sourceKey = sourceKey; e.cycle++; e.ended = false; e.encrypted = false; }
    return e;
  }
  const mediaID = v => { const e = entry(v); return e ? `${documentID}:${e.id}:${e.cycle}` : ""; };
  const state = () => {
    const v = media(); lastPrimary = v;
    let mime = "";
    if (v) {
      const match = [...v.querySelectorAll("source")].find(s => {
        try { return new URL(s.src || s.getAttribute("src"), document.baseURI || location.href).href === v.currentSrc; } catch (_) { return false; }
      });
      mime = match?.type || v.getAttribute?.("type") || "";
    }
    post("state", {title: document.title, hasMedia: Boolean(v), playing: v ? !v.paused && !v.ended : false,
      time: Number.isFinite(v?.currentTime) ? v.currentTime : 0, duration: Number.isFinite(v?.duration) ? v.duration : null,
      source: v?.currentSrc || "", contentType: mime, encrypted: v ? Boolean(entry(v)?.encrypted || v.mediaKeys) : false,
      mediaID: v ? mediaID(v) : "", mediaKind: v?.tagName === "VIDEO" ? "video" : "audio",
      priority: v ? (v.tagName === "VIDEO" ? 1000000 : 0) + area(v) : 0,
      interactionAt, videoID: videoID() || "", canUndo: Boolean(undo)});
  };
  const seek = seconds => {
    const v = media();
    if (!v || !Number.isFinite(seconds)) return;
    let target = Math.max(0, v.currentTime + seconds);
    if (Number.isFinite(v.duration)) target = Math.min(target, v.duration);
    else if (v.seekable?.length) target = Math.min(Math.max(target, v.seekable.start(0)), v.seekable.end(v.seekable.length - 1));
    try { v.currentTime = target; } catch (_) {}
    state();
  };
  const skipTo = (v, segment) => {
    undo = {id: mediaID(v), videoID: videoID(), time: v.currentTime, segment};
    try { v.currentTime = Math.min(segment.segment[1], Number.isFinite(v.duration) ? v.duration : segment.segment[1]); } catch (_) {}
    state();
  };
  function attach() {
    nodes().forEach(v => {
      if (attached.has(v)) return;
      attached.set(v, {id: ++serial, cycle: 0, ended: false, sourceKey: null, encrypted: false});
      entry(v);
      // A new element may already have started before its play listener exists.
      if (stopped && !v.paused) v.pause();
      v.addEventListener("encrypted", () => { entry(v).encrypted = true; state(); });
      v.addEventListener("play", () => {
        if (stopped) { v.pause(); return; }
        const e = entry(v); if (e.ended) { e.cycle++; e.ended = false; }
        state();
      });
      v.addEventListener("pause", state);
      v.addEventListener("loadedmetadata", () => { entry(v); state(); });
      v.addEventListener("timeupdate", () => {
        if (!sponsorEnabled || segmentID !== videoID() || v !== media() || v.tagName !== "VIDEO" || v.paused || v.seeking || isAd()) return;
        if (ignoredSegment && v.currentTime >= ignoredSegment.segment[1]) ignoredSegment = null;
        const match = segments.find(s => s !== ignoredSegment && v.currentTime >= s.segment[0] && v.currentTime < s.segment[1]);
        if (match) skipTo(v, match);
      });
      v.addEventListener("ended", () => {
        const e = entry(v);
        if (e.ended || isAd() || v.tagName !== "VIDEO" || v !== lastPrimary) return;
        const id = mediaID(v); e.ended = true;
        post("ended", {eventID: id, mediaID: id, mediaKind: "video", primary: true}); state();
      });
    });
  }
  const choose = event => {
    const path = event.composedPath?.() || [event.target];
    const v = path.find(node => node?.tagName === "VIDEO" || node?.tagName === "AUDIO");
    if (v) { selected = v; interactionAt = Date.now(); state(); }
  };
  document.addEventListener("pointerdown", choose, true);
  globalThis.__webkweb = {
    setSponsorBlock(enabled, chosenCategories = categories) {
      sponsorEnabled = Boolean(enabled); categories = chosenCategories;
      if (!sponsorEnabled) { segments = []; segmentID = null; }
    },
    setSegments(id, value) {
      if (id !== videoID() || !Array.isArray(value)) return;
      segmentID = id;
      segments = value.filter(s => categories.includes(s.category) && Array.isArray(s.segment) && s.segment.length === 2 &&
        s.segment.every(Number.isFinite) && s.segment[0] >= 0 && s.segment[1] > s.segment[0]);
    },
    pause(blockAutoplay = false) { stopped = Boolean(blockAutoplay); nodes().forEach(v => v.pause()); state(); },
    clearStop() { stopped = false; },
    resume() { stopped = false; const v = media(); if (v) v.play().catch(() => post("notice", {text: "Bitte auf den Webseitenplayer tippen."})); },
    toggle() { const v = media(); if (v) v.paused ? this.resume() : this.pause(); },
    seek,
    skip() {
      const v = media(); if (!v || isAd()) return;
      const match = segments.find(s => s.segment[1] > v.currentTime);
      if (match) skipTo(v, match);
    },
    undoSkip() {
      const v = media(); if (!v || !undo || undo.id !== mediaID(v) || undo.videoID !== videoID()) return;
      ignoredSegment = undo.segment; v.currentTime = undo.time; undo = null; state();
    },
    pip() {
      const v = media(); if (!v || v.tagName !== "VIDEO") return post("notice", {text: "Kein Videoplayer verfügbar."});
      if (v.webkitSupportsPresentationMode?.("picture-in-picture")) v.webkitSetPresentationMode("picture-in-picture");
      else if (v.requestPictureInPicture) v.requestPictureInPicture().catch(() => post("notice", {text: "Bild-in-Bild ist hier nicht verfügbar."}));
      else post("notice", {text: "Dieser Player unterstützt kein Bild-in-Bild."});
    },
    airplay() { const v = media(); if (v?.webkitShowPlaybackTargetPicker) v.webkitShowPlaybackTargetPicker(); else post("notice", {text: "Nutze AirPlay im Kontrollzentrum."}); },
    state
  };
  const tick = () => {
    if (lastAddress !== location.href) {
      const oldID = lastAddress ? (() => { try { const u = new URL(lastAddress); return u.searchParams.get("v") || u.pathname.split("/").at(-1); } catch (_) { return null; } })() : null;
      lastAddress = location.href;
      if (segmentID !== videoID() || oldID !== videoID()) { segments = []; segmentID = null; undo = null; ignoredSegment = null; }
      post("navigation", {videoID: videoID() || ""});
    }
    attach();
    if (stopped) nodes().forEach(v => { if (!v.paused) v.pause(); });
    state();
  };
  post("ready"); tick();
  setInterval(tick, 1000);
  if (typeof MutationObserver !== "undefined") new MutationObserver(attach).observe(document, {childList: true, subtree: true});
  window.addEventListener?.("pagehide", () => post("dispose"));
  window.addEventListener?.("pageshow", event => { if (event.persisted) { post("ready"); tick(); } });
  document.addEventListener("visibilitychange", tick);
  document.addEventListener("yt-navigate-finish", tick);
})();
