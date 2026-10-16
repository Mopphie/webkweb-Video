(() => {
  "use strict";
  if (globalThis.__webkweb) return;
  const documentID = Math.random().toString(36).slice(2) + Date.now().toString(36);
  const attached = new WeakMap();
  const knownMedia = new Set(), observedRoots = new WeakSet();
  let background = false, autoPiP = false, preferOriginal = false, hideShorts = false, queueManaged = false;
  let lastDiscovery = 0, lastHeartbeat = 0, lastState = 0, lastSignature = "";
  let serial = 0;
  let lastAddress = "", stopped = Boolean(globalThis.__webkwebStartPaused), selected = null;
  let interactionAt = 0, lastPrimary = null;
  let playIntent = null;
  const hasPlayIntent = v => {
    const elapsed = playIntent ? Date.now() - playIntent.at : -1;
    return playIntent?.media === v && elapsed >= 0 && elapsed <= 1500;
  };
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
  function discover(root) {
    if (root?.tagName === "VIDEO" || root?.tagName === "AUDIO") knownMedia.add(root);
    root?.querySelectorAll?.("video,audio").forEach(v => knownMedia.add(v));
    root?.querySelectorAll?.("*").forEach(node => { if (node.shadowRoot) discover(node.shadowRoot); });
    if (root && (root === document || root.nodeType === 11) && !observedRoots.has(root) && typeof MutationObserver !== "undefined") {
      observedRoots.add(root);
      new MutationObserver(records => {
        if (!records) discover(root); // Also supports the small test DOM harness.
        else records.forEach(record => record.addedNodes?.forEach(node => discover(node)));
        attach();
      }).observe(root, {childList: true, subtree: true});
    }
  }
  function nodes() {
    knownMedia.forEach(v => { if (v.isConnected === false) { knownMedia.delete(v); if (v === selected) selected = null; } });
    return [...knownMedia];
  }
  const area = v => {
    const r = v.getBoundingClientRect?.();
    return r ? Math.max(0, Math.min(r.right, innerWidth) - Math.max(0, r.left)) *
      Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(0, r.top)) : (v.tagName === "VIDEO" ? 10000 : 0);
  };
  function media() {
    const all = nodes();
    // Browsers may fire pause/timeupdate before ended. Retain the old primary
    // until its ended event is acknowledged, rather than selecting a loop/ad.
    if (lastPrimary && all.includes(lastPrimary) && lastPrimary.ended && !entry(lastPrimary)?.ended) return lastPrimary;
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
    if (sourceKey !== e.sourceKey) {
      e.sourceKey = sourceKey; e.cycle++; e.ended = false; e.waiting = false;
      // Keep the page's pre-queue loop preference until queue management ends.
      if (!queueManaged) e.originalLoop = null;
    }
    return e;
  }
  const mediaID = v => { const e = entry(v); return e ? `${documentID}:${e.id}:${e.cycle}` : ""; };
  const tracks = (list, audio = false) => Array.from(list || []).slice(0, 100).map((track, id) => ({id,
    title: track.label || track.language || `Spur ${id + 1}`, selected: audio ? Boolean(track.enabled) : track.mode === "showing"}));
  const buffering = v => Boolean(v && !v.paused && !v.ended && entry(v)?.waiting &&
    (typeof v.readyState !== "number" || v.readyState < 3));
  const state = (force = true) => {
    const v = media(); lastPrimary = v;
    if (queueManaged && v) { const e = entry(v); if (e && e.originalLoop == null) e.originalLoop = Boolean(v.loop); v.loop = false; }
    const signature = [v?.currentSrc, v?.paused, v?.ended, v ? mediaID(v) : "", buffering(v), v?.readyState, v?.networkState, v?.error?.code, v?.playbackRate].join(":");
    const now = Date.now(), interval = background || document.hidden ? 5000 : 1000;
    if (!force && signature === lastSignature && now - lastState < interval) return;
    lastState = now; lastSignature = signature;
    post("state", {title: document.title, hasMedia: Boolean(v), playing: v ? !v.paused && !v.ended : false,
      anyPlaying: nodes().some(node => !node.paused && !node.ended),
      time: Number.isFinite(v?.currentTime) ? v.currentTime : 0, duration: Number.isFinite(v?.duration) ? v.duration : null,
      mediaID: v ? mediaID(v) : "", mediaKind: v?.tagName === "VIDEO" ? "video" : "audio",
      priority: v ? (v.tagName === "VIDEO" ? 1000000 : 0) + area(v) : 0,
      interactionAt,
      captions: tracks(v?.textTracks), audioTracks: tracks(v?.audioTracks, true),
      rate: v?.playbackRate || 1, width: v?.videoWidth || 0, height: v?.videoHeight || 0,
      muted: Boolean(v?.muted), waiting: buffering(v),
      paused: v ? Boolean(v.paused) : true, ended: Boolean(v?.ended), stopLatched: stopped,
      readyState: Number.isInteger(v?.readyState) ? v.readyState : null,
      networkState: Number.isInteger(v?.networkState) ? v.networkState : null,
      sourceKind: v?.currentSrc ? v.currentSrc.split(":", 1)[0] : "none",
      mediaError: v?.error ? `Medienfehler ${v.error.code}` : ""});
  };
  const seek = seconds => {
    const v = commandMedia();
    if (!v || !Number.isFinite(seconds)) return;
    let target = Math.max(0, v.currentTime + seconds);
    if (Number.isFinite(v.duration)) target = Math.min(target, v.duration);
    else if (v.seekable?.length) target = Math.min(Math.max(target, v.seekable.start(0)), v.seekable.end(v.seekable.length - 1));
    try { v.currentTime = target; } catch (_) {}
    state();
  };
  function attach() {
    nodes().forEach(v => {
      if (stopped && !v.paused && !hasPlayIntent(v)) v.pause();
      if (attached.has(v)) return;
      attached.set(v, {id: ++serial, cycle: 0, ended: false, sourceKey: null, waiting: false});
      entry(v);
      // A new element may already have started before its play listener exists.
      v.addEventListener("play", () => {
        if (stopped) {
          // A media `play` event is also trusted for script/autoplay. Only an
          // earlier real input on this player's controls may release the latch.
          if (!hasPlayIntent(v)) { v.pause(); return; }
          playIntent = null;
          stopped = false;
          post("userplay", {mediaID: mediaID(v)});
        }
        const e = entry(v); if (e.ended) { e.cycle++; e.ended = false; }
        state();
      });
      v.addEventListener("pause", () => { entry(v).waiting = false; state(); });
      v.addEventListener("loadedmetadata", () => { entry(v); applyOriginal(v); state(); });
      v.addEventListener("waiting", () => { entry(v).waiting = true; state(); });
      v.addEventListener("stalled", () => { entry(v).waiting = true; state(); });
      v.addEventListener("playing", () => { entry(v).waiting = false; state(); });
      v.addEventListener("canplay", state);
      v.addEventListener("error", state);
      v.addEventListener("ratechange", state);
      v.addEventListener("volumechange", state);
      v.textTracks?.addEventListener?.("change", state);
      v.audioTracks?.addEventListener?.("change", state);
      v.audioTracks?.addEventListener?.("addtrack", () => { applyOriginal(v); state(); });
      applyOriginal(v);
      v.addEventListener("timeupdate", () => state(false));
      v.addEventListener("ended", () => {
        const e = entry(v);
        if (e.ended || isAd() || v !== lastPrimary) return;
        const id = mediaID(v); e.ended = true;
        if (v.tagName === "VIDEO") post("ended", {eventID: id, mediaID: id, mediaKind: "video", primary: true});
        post("queueended", {eventID: id, mediaID: id, mediaKind: v.tagName === "VIDEO" ? "video" : "audio", primary: true}); state();
      });
    });
  }
  function commandMedia() {
    // User/timer commands must see media inserted into a newly opened shadow
    // root immediately. Periodic discovery remains sparse during playback.
    discover(document); attach();
    return media();
  }
  const choose = event => {
    const path = event.composedPath?.() || [event.target];
    let v = path.find(node => node?.tagName === "VIDEO" || node?.tagName === "AUDIO");
    if (!v && stopped && event.isTrusted) {
      const button = path.find(node => node?.tagName === "BUTTON" || node?.getAttribute?.("role") === "button" ||
        (node?.tagName === "INPUT" && ["button", "submit"].includes(node.type)));
      const name = button && [button.getAttribute?.("aria-label"), button.getAttribute?.("title"), button.textContent, button.value].filter(Boolean).join(" ");
      if (/\b(play|resume|abspielen|fortsetzen|wiedergeben|wiedergabe)\b/i.test(name || "")) {
        // Associate semantic controls with the closest player container. This
        // works for open shadow roots without relying on provider internals.
        for (const ancestor of path.slice(path.indexOf(button) + 1)) {
          const candidates = Array.from(ancestor?.querySelectorAll?.("video,audio") || []);
          if (candidates.length) { v = candidates.includes(media()) ? media() : candidates[0]; break; }
        }
      }
    }
    if (v) { knownMedia.add(v); attach(); selected = v; interactionAt = Date.now(); state(); }
    if (v && stopped && event.isTrusted) playIntent = {media: v, at: Date.now()};
  };
  document.addEventListener("pointerdown", choose, true);
  document.addEventListener("click", choose, true);
  document.addEventListener("keydown", event => {
    if (event.key === " " || event.key === "Enter") choose(event);
  }, true);
  function applyOriginal(v) {
    if (!preferOriginal || !v.audioTracks) return;
    const list = Array.from(v.audioTracks), original = list.find(t => /\boriginal(?:ton| audio)?\b/i.test(t.label || ""));
    if (original) list.forEach(t => { t.enabled = t === original; });
  }
  function shortsPolicy() {
    const youtube = /(^|\.)youtube\.com$/.test(location.hostname);
    let style = document.getElementById?.("webkweb-shorts-policy");
    if (hideShorts && youtube && !style && document.createElement && document.head) {
      style = document.createElement("style"); style.id = "webkweb-shorts-policy";
      style.textContent = 'ytd-reel-shelf-renderer,ytd-reel-video-renderer,ytm-reel-shelf-renderer,a[href^="/shorts/"],a[href*="youtube.com/shorts/"]{display:none!important}';
      document.head.appendChild(style);
    } else if (!hideShorts || !youtube) style?.remove();
    if (hideShorts && youtube && location.pathname.startsWith("/shorts/")) {
      post("notice", {text: "Shorts sind ausgeschaltet."}); location.replace?.("https://m.youtube.com/");
    }
  }
  globalThis.__webkweb = {
    pause(blockAutoplay = false) { stopped = Boolean(blockAutoplay); playIntent = null; commandMedia(); nodes().forEach(v => v.pause()); state(); },
    clearStop() { stopped = false; playIntent = null; },
    resume() { stopped = false; playIntent = null; const v = commandMedia(); if (v) v.play().catch(() => post("notice", {text: "Bitte auf den Webseitenplayer tippen."})); },
    toggle() { const v = commandMedia(); if (v) v.paused ? this.resume() : this.pause(); },
    noteHostTouch(point = {}) {
      // WebKit's own media controls may consume all DOM input events. The
      // native host calls this isolated-world method on an actual UIKit touch.
      // Do not substitute navigator.userActivation: it can remain set for 5s.
      if (!stopped || !Number.isFinite(point.x) || !Number.isFinite(point.y) ||
          point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1) return;
      commandMedia();
      const viewport = globalThis.visualViewport;
      const x = (viewport?.offsetLeft || 0) + point.x * (viewport?.width || innerWidth);
      const y = (viewport?.offsetTop || 0) + point.y * (viewport?.height || innerHeight);
      const v = nodes().filter(node => {
        const r = node.getBoundingClientRect?.();
        return r && r.right > r.left && r.bottom > r.top && x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
      }).sort((a, b) => area(a) - area(b))[0];
      if (v) { selected = v; interactionAt = Date.now(); playIntent = {media: v, at: Date.now()}; }
    },
    seek,
    setOptions(options = {}) {
      autoPiP = Boolean(options.autoPiP); preferOriginal = Boolean(options.preferOriginal); hideShorts = Boolean(options.hideShorts);
      nodes().forEach(applyOriginal); shortsPolicy();
    },
    setBackground(value) { background = Boolean(value); },
    setQueueManaged(value) {
      queueManaged = Boolean(value);
      if (queueManaged) { const v = media(), e = v && entry(v); if (e && e.originalLoop == null) e.originalLoop = Boolean(v.loop); if (v) v.loop = false; }
      else nodes().forEach(v => { const e = entry(v); if (e?.originalLoop != null) { v.loop = e.originalLoop; e.originalLoop = null; } });
    },
    restart(id) {
      if (stopped) return;
      commandMedia();
      const v = typeof id === "string" ? nodes().find(node => mediaID(node) === id) : media();
      if (v) { selected = v; v.currentTime = 0; v.play().catch(() => post("notice", {text: "Bitte auf den Webseitenplayer tippen."})); }
    },
    setRate(value) { const v = commandMedia(); if (v && Number.isFinite(value) && value >= 0.25 && value <= 3) { v.playbackRate = value; state(); } },
    setCaption(id) { const v = commandMedia(); if (!v) return; Array.from(v.textTracks || []).forEach((t, index) => { t.mode = index === id ? "showing" : "disabled"; }); state(); },
    setAudio(id) {
      const v = commandMedia(), list = Array.from(v?.audioTracks || []);
      if (!list.some((_, index) => index === id)) return;
      list.forEach((t, index) => { t.enabled = index === id; }); state();
    },
    recover() { const v = commandMedia(); if (!v) return; if (stopped) return post("notice", {text: "Wiedergabe ist gestoppt. Tippe auf Play."}); this.resume(); },
    fullscreen() {
      const v = commandMedia(); if (!v || v.tagName !== "VIDEO") return;
      try {
        if (v.webkitEnterFullscreen) v.webkitEnterFullscreen();
        else if (v.requestFullscreen) v.requestFullscreen().catch(() => post("notice", {text: "Vollbild ist hier nicht verfügbar."}));
        else post("notice", {text: "Dieser Player unterstützt kein Vollbild."});
      } catch (_) { post("notice", {text: "Tippe für Vollbild auf den Webseitenplayer."}); }
    },
    autoPiP() {
      if (!autoPiP || stopped) return;
      const v = commandMedia();
      if (!v || v.paused || v.ended || v.tagName !== "VIDEO" || v.webkitPresentationMode === "picture-in-picture") return;
      try { this.pip(); } catch (_) {} // User gesture / background timing remains iOS-dependent.
    },
    pip() {
      const v = commandMedia(); if (!v || v.tagName !== "VIDEO") return post("notice", {text: "Kein Videoplayer verfügbar."});
      try {
        if (v.webkitSupportsPresentationMode?.("picture-in-picture")) v.webkitSetPresentationMode("picture-in-picture");
        else if (v.requestPictureInPicture) v.requestPictureInPicture().catch(() => post("notice", {text: "Bild-in-Bild ist hier nicht verfügbar."}));
        else post("notice", {text: "Dieser Player unterstützt kein Bild-in-Bild."});
      } catch (_) { post("notice", {text: "Tippe für Bild-in-Bild auf den Webseitenplayer."}); }
    },
    airplay() { const v = commandMedia(); if (v?.webkitShowPlaybackTargetPicker) v.webkitShowPlaybackTargetPicker(); else post("notice", {text: "Nutze AirPlay im Kontrollzentrum."}); },
    state
  };
  const tick = () => {
    const now = Date.now(), hidden = background || document.hidden;
    if (hidden && now - lastHeartbeat < 5000) return;
    lastHeartbeat = now;
    if (lastAddress !== location.href) {
      lastAddress = location.href;
      post("navigation");
      shortsPolicy();
    }
    if (!hidden && now - lastDiscovery >= 15000) { discover(document); lastDiscovery = now; }
    attach();
    if (stopped) nodes().forEach(v => { if (!v.paused && !hasPlayIntent(v)) v.pause(); });
    state(false);
  };
  discover(document); lastDiscovery = Date.now(); post("ready"); tick();
  setInterval(tick, 1000);
  window.addEventListener?.("pagehide", () => post("dispose"));
  window.addEventListener?.("pageshow", event => { if (event.persisted) { lastHeartbeat = 0; lastState = 0; post("ready"); tick(); } });
  document.addEventListener("visibilitychange", () => { lastHeartbeat = 0; lastState = 0; if (document.hidden) globalThis.__webkweb.autoPiP(); tick(); });
  document.addEventListener("yt-navigate-finish", tick);
})();
