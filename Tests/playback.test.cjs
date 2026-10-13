"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const source = fs.readFileSync(require("node:path").join(__dirname, "../App/Resources/Playback.js"), "utf8");

function harness(address = "https://m.youtube.com/watch?v=abcdefghijk") {
  const handlers = {}, messages = [], listeners = {};
  const video = {
    tagName: "VIDEO", currentTime: 0, duration: 100, paused: false, ended: false, seeking: false,
    currentSrc: "https://cdn.example.com/video.mp4", mediaKeys: null,
    addEventListener(name, handler) { handlers[name] = handler; },
    querySelector() { return { type: "video/mp4" }; },
    pause() { this.paused = true; },
    play() { this.paused = false; handlers.play?.(); return Promise.resolve(); }
  };
  let tick;
  const location = new URL(address);
  const context = {
    URL, location, Math, Number, Array, Boolean,
    window: { webkit: { messageHandlers: { playback: { postMessage(value) { messages.push(value); } } } } },
    document: { title: "Example video", querySelector() { return null; },
      querySelectorAll() { return [video]; }, addEventListener(name, handler) { listeners[name] = handler; } },
    setInterval(handler) { tick = handler; return 1; }
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  return { api: context.__webkweb, handlers, messages, video, tick: () => tick(), location, listeners };
}

test("isolated bridge observes playback and leaves SponsorBlock off initially", () => {
  const h = harness();
  assert.ok(h.messages.some(m => m.kind === "ready"));
  assert.ok(h.messages.some(m => m.kind === "navigation"));
  assert.equal(h.messages.find(m => m.kind === "state").source, h.video.currentSrc);
  h.api.setSegments("abcdefghijk", [{ category: "sponsor", segment: [2, 8] }]);
  h.video.currentTime = 4; h.handlers.timeupdate();
  assert.equal(h.video.currentTime, 4);
});

test("matching YouTube segment skips and stale SPA segments are cleared", () => {
  const h = harness();
  h.api.setSponsorBlock(true);
  h.api.setSegments("abcdefghijk", [{ category: "intro", segment: [2, 8] }]);
  h.video.currentTime = 4; h.handlers.timeupdate();
  assert.equal(h.video.currentTime, 8);
  h.location.href = "https://m.youtube.com/watch?v=12345678901";
  h.tick(); h.video.currentTime = 4; h.handlers.timeupdate();
  assert.equal(h.video.currentTime, 4);
  h.api.setSegments("abcdefghijk", [{ category: "intro", segment: [2, 8] }]);
  h.handlers.timeupdate(); assert.equal(h.video.currentTime, 4);
});

test("spoofed host cannot use SponsorBlock segments", () => {
  const h = harness("https://youtube.com.evil.example/watch?v=abcdefghijk");
  h.api.setSponsorBlock(true); h.api.setSegments("abcdefghijk", [{ category: "sponsor", segment: [2, 8] }]);
  h.video.currentTime = 4; h.handlers.timeupdate(); assert.equal(h.video.currentTime, 4);
});

test("invalid segments do not seek and seeks stay inside media duration", () => {
  const h = harness(); h.api.setSponsorBlock(true);
  h.api.setSegments("abcdefghijk", [{ category: "intro", segment: [-2, 8] },
    { category: "sponsor", segment: [8, 2] }, { category: "invalid", segment: [2, 8] }]);
  h.video.currentTime = 4; h.handlers.timeupdate(); assert.equal(h.video.currentTime, 4);
  h.api.seek(-999); assert.equal(h.video.currentTime, 0);
  h.api.seek(999); assert.equal(h.video.currentTime, 100);
});

test("timer pause suppresses autoplay until native resume", () => {
  const h = harness(); h.api.pause(true); assert.equal(h.video.paused, true);
  h.video.paused = false; h.handlers.play(); assert.equal(h.video.paused, true);
  h.api.resume(); assert.equal(h.video.paused, false);
});

test("ended events are deduplicated and replay starts a new cycle", () => {
  const h = harness(); h.video.ended = true; h.handlers.ended(); h.handlers.ended();
  assert.equal(h.messages.filter(m => m.kind === "ended").length, 1);
  h.video.ended = false; h.handlers.play(); h.handlers.ended();
  const events = h.messages.filter(m => m.kind === "ended");
  assert.equal(events.length, 2); assert.notEqual(events[0].eventID, events[1].eventID);
});

test("encrypted event is reported so Cast refuses DRM", () => {
  const h = harness(); h.handlers.encrypted();
  assert.equal(h.messages.filter(m => m.kind === "state").at(-1).encrypted, true);
});
