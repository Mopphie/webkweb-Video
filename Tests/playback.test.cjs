'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,'../App/Resources/Playback.js'),'utf8');
function element(tag='VIDEO', options={}) {
 const listeners = {}, sources = options.sources || [{src:'https://cdn.example/video.mp4',type:'video/mp4'}];
 return Object.assign({tagName:tag,currentSrc:sources[0]?.src || '',currentTime:0,duration:100,paused:false,ended:false,seeking:false,mediaKeys:null,listeners,
  addEventListener(n,h){listeners[n]=h;},getAttribute(){return null;},querySelectorAll(s){return s==='source'?sources:[];},
  getBoundingClientRect(){const width=options.width||640,height=options.height||360;return {left:0,top:0,right:width,bottom:height};},
  pause(){this.paused=true;listeners.pause?.();},play(){this.paused=false;this.ended=false;listeners.play?.();return Promise.resolve();},
  end(){this.ended=true;this.paused=true;listeners.ended?.();}
 },options);
}
function harness(initial=[element()],url='https://m.youtube.com/watch?v=abcdefghijk') {
 const nodes=initial,messages=[],documentEvents={},windowEvents={},shadowHosts=[]; let tick,mutation;
 const location=new URL(url);
 const document={title:'Video',baseURI:url,querySelector(){return null;},querySelectorAll(s){return s==='*'?shadowHosts:s==='video'?nodes.filter(n=>n.tagName==='VIDEO'):nodes;},addEventListener(n,h){documentEvents[n]=h;}};
 const sandbox={URL,Math,Number,Array,Boolean,Date,innerWidth:1000,innerHeight:1000,location,document,
  window:{webkit:{messageHandlers:{playback:{postMessage(v){messages.push(v);}}}},addEventListener(n,h){windowEvents[n]=h;}},
  setInterval(fn){tick=fn;return 1;},MutationObserver:class {constructor(fn){mutation=fn;}observe(){}}
 };
 vm.createContext(sandbox);vm.runInContext(source,sandbox);
 return {api:sandbox.__webkweb,nodes,messages,location,documentEvents,windowEvents,shadowHosts,
  tick:()=>tick(),add(v){nodes.push(v);mutation();},state(){return messages.filter(m=>m.kind==='state').at(-1);}};
}
const segments=[{category:'intro',segment:[2,8]}];
test('SponsorBlock defaults off; state includes valid source and document/media IDs',()=>{
 const h=harness();assert.ok(h.state().documentID);assert.ok(h.state().mediaID);assert.equal(h.state().source,h.nodes[0].currentSrc);
 h.api.setSegments('abcdefghijk',segments);h.nodes[0].currentTime=4;h.nodes[0].listeners.timeupdate();assert.equal(h.nodes[0].currentTime,4);
});
test('selected category skips a matching segment',()=>{
 const h=harness();h.api.setSponsorBlock(true,['intro']);h.api.setSegments('abcdefghijk',segments);
 h.nodes[0].currentTime=4;h.nodes[0].listeners.timeupdate();assert.equal(h.nodes[0].currentTime,8);
});
test('category exclusions leave playback unchanged',()=>{
 const h=harness();h.api.setSponsorBlock(true,['sponsor']);h.api.setSegments('abcdefghijk',segments);
 h.nodes[0].currentTime=4;h.nodes[0].listeners.timeupdate();assert.equal(h.nodes[0].currentTime,4);
});
test('SPA clears stale segments and accepts refreshed new-video segments',()=>{
 const h=harness();h.api.setSponsorBlock(true);h.api.setSegments('abcdefghijk',segments);
 h.location.href='https://m.youtube.com/watch?v=12345678901';h.tick();h.nodes[0].currentTime=4;h.nodes[0].listeners.timeupdate();assert.equal(h.nodes[0].currentTime,4);
 h.api.setSegments('abcdefghijk',segments);h.nodes[0].listeners.timeupdate();assert.equal(h.nodes[0].currentTime,4);
 h.api.setSegments('12345678901',segments);h.nodes[0].listeners.timeupdate();assert.equal(h.nodes[0].currentTime,8);
});
test('spoofed YouTube host cannot use segments',()=>{
 const h=harness(undefined,'https://youtube.com.evil.example/watch?v=abcdefghijk');h.api.setSponsorBlock(true);h.api.setSegments('abcdefghijk',segments);
 h.nodes[0].currentTime=4;h.nodes[0].listeners.timeupdate();assert.equal(h.nodes[0].currentTime,4);
});
test('invalid bounds/categories are rejected and seek is clamped',()=>{
 const h=harness();h.api.setSponsorBlock(true);h.api.setSegments('abcdefghijk',[{category:'intro',segment:[-2,8]},{category:'sponsor',segment:[8,2]},{category:'unknown',segment:[2,8]}]);
 h.nodes[0].currentTime=4;h.nodes[0].listeners.timeupdate();assert.equal(h.nodes[0].currentTime,4);
 h.api.seek(-999);assert.equal(h.nodes[0].currentTime,0);h.api.seek(999);assert.equal(h.nodes[0].currentTime,100);
});
test('live seek stays in seekable range',()=>{
 const h=harness([element('VIDEO',{duration:Infinity,currentTime:150,seekable:{length:1,start:()=>100,end:()=>200}})]);
 h.api.seek(-999);assert.equal(h.nodes[0].currentTime,100);h.api.seek(999);assert.equal(h.nodes[0].currentTime,200);
});
test('timer pause prevents original autoplay until explicit native resume',()=>{
 const h=harness();h.api.pause(true);h.nodes[0].play();assert.equal(h.nodes[0].paused,true);
 h.api.resume();assert.equal(h.nodes[0].paused,false);
});
test('new already-playing autoplay video is paused immediately after insertion',()=>{
 const h=harness();h.api.pause(true);const next=element();h.add(next);assert.equal(next.paused,true);
});
test('clearStop cancels latch without starting paused media',()=>{
 const h=harness();h.api.pause(true);h.api.clearStop();assert.equal(h.nodes[0].paused,true);
 h.nodes[0].play();assert.equal(h.nodes[0].paused,false);
});
test('audio end never counts as a video while primary video plays',()=>{
 const video=element(),audio=element('AUDIO',{currentSrc:'https://cdn.example/sound.mp3'});const h=harness([video,audio]);audio.end();
 assert.equal(h.messages.filter(m=>m.kind==='ended').length,0);
});
test('large primary video end counts despite a playing incidental loop video',()=>{
 const main=element(),small=element('VIDEO',{width:16,height:16,loop:true});const h=harness([main,small]);main.end();
 const events=h.messages.filter(m=>m.kind==='ended');assert.equal(events.length,1);assert.equal(events[0].mediaKind,'video');assert.equal(events[0].primary,true);
});
test('incidental video end is ignored while primary video plays',()=>{
 const main=element(),small=element('VIDEO',{width:16,height:16});const h=harness([main,small]);small.end();assert.equal(h.messages.filter(m=>m.kind==='ended').length,0);
});
test('end deduplication and replay produce distinct IDs',()=>{
 const h=harness();h.nodes[0].end();h.nodes[0].listeners.ended();assert.equal(h.messages.filter(m=>m.kind==='ended').length,1);
 h.nodes[0].play();h.nodes[0].end();const events=h.messages.filter(m=>m.kind==='ended');assert.equal(events.length,2);assert.notEqual(events[0].eventID,events[1].eventID);
});
test('same-location iframe documents have distinct identities',()=>{
 const a=harness(),b=harness();assert.notEqual(a.state().documentID,b.state().documentID);
});
test('source MIME matches currentSrc rather than first source',()=>{
 const sources=[{src:'https://cdn.example/first',type:'video/mp4'},{src:'https://cdn.example/chosen',type:'application/vnd.apple.mpegurl'}];
 const h=harness([element('VIDEO',{sources,currentSrc:sources[1].src})]);assert.equal(h.state().contentType,'application/vnd.apple.mpegurl');
});
test('DRM state resets for a new unencrypted source and media ID changes',()=>{
 const h=harness();h.nodes[0].listeners.encrypted();assert.equal(h.state().encrypted,true);const before=h.state().mediaID;
 h.nodes[0].currentSrc='https://cdn.example/clear.mp4';h.tick();assert.equal(h.state().encrypted,false);assert.notEqual(h.state().mediaID,before);
});
test('open shadow root media is detected',()=>{
 const h=harness([]),v=element();h.shadowHosts.push({shadowRoot:{querySelectorAll(s){return s==='*'?[]:[v];}}});h.tick();assert.equal(h.state().hasMedia,true);
});
test('manual skip and undo restore position without immediately reskipping',()=>{
 const h=harness();h.api.setSponsorBlock(true);h.api.setSegments('abcdefghijk',segments);h.nodes[0].currentTime=4;
 h.api.skip();assert.equal(h.nodes[0].currentTime,8);assert.equal(h.state().canUndo,true);
 h.api.undoSkip();assert.equal(h.nodes[0].currentTime,4);h.nodes[0].listeners.timeupdate();assert.equal(h.nodes[0].currentTime,4);
});
test('pagehide sends disposal for precisely the same document',()=>{
 const h=harness();const id=h.state().documentID;h.windowEvents.pagehide();const disposal=h.messages.at(-1);assert.equal(disposal.kind,'dispose');assert.equal(disposal.documentID,id);
});
test('back-forward cache restore registers the same document again and publishes state',()=>{
 const h=harness();const id=h.state().documentID;h.windowEvents.pagehide();const start=h.messages.length;
 h.windowEvents.pageshow({persisted:true});const restored=h.messages.slice(start);
 assert.equal(restored[0].kind,'ready');assert.equal(restored[0].documentID,id);assert.ok(restored.some(m=>m.kind==='state'&&m.hasMedia));
});
test('explicit user selection steers seek to that video',()=>{
 const main=element(),small=element('VIDEO',{width:16,height:16});const h=harness([main,small]);
 h.documentEvents.pointerdown({composedPath:()=>[small]});h.api.seek(10);assert.equal(small.currentTime,10);assert.equal(main.currentTime,0);
});
