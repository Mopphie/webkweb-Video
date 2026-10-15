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
 const nodes=initial,messages=[],documentEvents={},windowEvents={},shadowHosts=[]; let tick,mutation,clock=Date.now(),queries=0;
 const location=new URL(url);
 const document={title:'Video',baseURI:url,hidden:false,querySelector(){return null;},querySelectorAll(s){queries++;return s==='*'?shadowHosts:s==='video'?nodes.filter(n=>n.tagName==='VIDEO'):nodes;},addEventListener(n,h){documentEvents[n]=h;}};
 const sandbox={URL,Math,Number,Array,Boolean,Date:class extends Date {static now(){return clock;}},innerWidth:1000,innerHeight:1000,location,document,
  window:{webkit:{messageHandlers:{playback:{postMessage(v){messages.push(v);}}}},addEventListener(n,h){windowEvents[n]=h;}},
  setInterval(fn){tick=fn;return 1;},MutationObserver:class {constructor(fn){mutation=fn;}observe(){}}
 };
 vm.createContext(sandbox);vm.runInContext(source,sandbox);
 return {api:sandbox.__webkweb,nodes,messages,location,document,documentEvents,windowEvents,shadowHosts,
  tick(){clock+=1000;tick();},advance(ms){clock+=ms;},queries:()=>queries,add(v){nodes.push(v);mutation([{addedNodes:[v]}]);},state(){return messages.filter(m=>m.kind==='state').at(-1);}};
}
test('state includes document and media IDs without exporting direct media URLs',()=>{
 const h=harness();assert.ok(h.state().documentID);assert.ok(h.state().mediaID);assert.equal(h.state().hasMedia,true);
 assert.equal(h.state().source,undefined);assert.equal(h.state().contentType,undefined);
});
test('ordinary seek remains clamped to media duration',()=>{
 const h=harness();h.api.seek(-999);assert.equal(h.nodes[0].currentTime,0);h.api.seek(999);assert.equal(h.nodes[0].currentTime,100);
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
test('a replacement source receives a new media identity',()=>{
 const h=harness();const before=h.state().mediaID;
 h.nodes[0].currentSrc='https://cdn.example/replacement.mp4';h.tick();assert.notEqual(h.state().mediaID,before);
});
test('open shadow root media is detected',()=>{
 const h=harness([]),v=element();h.shadowHosts.push({shadowRoot:{querySelectorAll(s){return s==='*'?[]:[v];}}});h.advance(16000);h.tick();assert.equal(h.state().hasMedia,true);
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
test('pause-before-ended retains primary ID and reports video plus queue end',()=>{
 const main=element(),loop=element('VIDEO',{width:16,height:16,loop:true}),h=harness([main,loop]),id=h.state().mediaID;
 main.ended=true;main.paused=true;main.listeners.timeupdate();main.listeners.pause();
 assert.equal(h.state().mediaID,id);main.listeners.ended();
 assert.equal(h.messages.filter(m=>m.kind==='ended').length,1);assert.equal(h.messages.filter(m=>m.kind==='queueended').length,1);
 assert.equal(h.messages.find(m=>m.kind==='queueended').mediaID,id);
});
test('primary audio ending drives queue but never N-video counter',()=>{
 const audio=element('AUDIO'),h=harness([audio]);audio.end();
 assert.equal(h.messages.filter(m=>m.kind==='ended').length,0);assert.equal(h.messages.find(m=>m.kind==='queueended').mediaKind,'audio');
});
test('seek and restart preserve deliberate mute volume and rate',()=>{
 const v=element('VIDEO',{muted:true,volume:0.35,playbackRate:1.25}),h=harness([v]);h.api.seek(10);h.api.restart();
 assert.equal(v.muted,true);assert.equal(v.volume,0.35);assert.equal(v.playbackRate,1.25);
});
test('managed queue disables HTML loop for ended events and restores it on release',()=>{
 const v=element('VIDEO',{loop:true}),h=harness([v]);h.api.setQueueManaged(true);assert.equal(v.loop,false);h.api.setQueueManaged(false);assert.equal(v.loop,true);
});
test('managed queue restores original HTML loop after source changes',()=>{
 const v=element('VIDEO',{loop:true}),h=harness([v]);h.api.setQueueManaged(true);assert.equal(v.loop,false);
 v.currentSrc='https://cdn.example/other.mp4';h.tick();h.api.setQueueManaged(false);assert.equal(v.loop,true);
});
test('caption selection and off use exposed text tracks only',()=>{
 const textTracks=[{label:'Deutsch',language:'de',mode:'disabled'},{label:'English',language:'en',mode:'disabled'}],h=harness([element('VIDEO',{textTracks})]);
 h.api.setCaption(1);assert.equal(textTracks[1].mode,'showing');assert.equal(textTracks[0].mode,'disabled');
 h.api.setCaption(-1);assert.ok(textTracks.every(t=>t.mode==='disabled'));
});
test('original-audio preference selects only explicitly marked original and manual selection works',()=>{
 const audioTracks=[{label:'English dubbed',enabled:true},{label:'Original audio',enabled:false}],h=harness([element('VIDEO',{audioTracks})]);
 h.api.setOptions({preferOriginal:true});assert.equal(audioTracks[1].enabled,true);assert.equal(audioTracks[0].enabled,false);
 h.api.setAudio(0);assert.equal(audioTracks[0].enabled,true);h.api.setAudio(99);assert.equal(audioTracks[0].enabled,true);
});
test('unknown audio labels are not guessed to be original',()=>{
 const audioTracks=[{label:'English',enabled:true},{label:'Deutsch',enabled:false}],h=harness([element('VIDEO',{audioTracks})]);h.api.setOptions({preferOriginal:true});assert.equal(audioTracks[0].enabled,true);
});
test('rate limits reject invalid settings without changing volume',()=>{
 const v=element('VIDEO',{volume:0.4,playbackRate:1}),h=harness([v]);h.api.setRate(2);assert.equal(v.playbackRate,2);h.api.setRate(99);assert.equal(v.playbackRate,2);assert.equal(v.volume,0.4);
});
test('fullscreen and PiP are separate and auto-PiP respects pause and timer stop',()=>{
 let fullscreen=0,pip=0;const v=element('VIDEO',{webkitEnterFullscreen(){fullscreen++;},webkitSupportsPresentationMode:()=>true,webkitSetPresentationMode(){pip++;}}),h=harness([v]);
 h.api.fullscreen();assert.equal(fullscreen,1);assert.equal(pip,0);h.api.setOptions({autoPiP:true});h.api.autoPiP();assert.equal(pip,1);
 h.api.pause(true);h.api.autoPiP();assert.equal(pip,1);h.api.clearStop();h.api.autoPiP();assert.equal(pip,1);
});
test('waiting recovery respects timer latch and preserves mute',()=>{
 const v=element('VIDEO',{muted:true}),h=harness([v]);v.listeners.waiting();assert.equal(h.state().waiting,true);
 h.api.pause(true);h.api.recover();assert.equal(v.paused,true);h.api.clearStop();h.api.recover();assert.equal(v.paused,false);assert.equal(v.muted,true);
 v.listeners.playing();assert.equal(h.state().waiting,false);
});
test('foreground ticks avoid whole-DOM queries until sparse discovery',()=>{
 const h=harness(),before=h.queries();for(let i=0;i<10;i++)h.tick();assert.equal(h.queries(),before);
 h.advance(15000);h.tick();assert.ok(h.queries()>before);
});
test('background ticks reduce state traffic and skip discovery',()=>{
 const h=harness();h.api.setBackground(true);const before=h.messages.length,queries=h.queries();for(let i=0;i<10;i++)h.tick();
 assert.equal(h.messages.slice(before).filter(m=>m.kind==='state').length,2);assert.equal(h.queries(),queries);
});
test('Shorts opt-in rejects route on genuine YouTube only',()=>{
 const h=harness(undefined,'https://m.youtube.com/shorts/abcdefghijk');let redirected='';h.location.replace=url=>{redirected=url;};h.api.setOptions({hideShorts:true});assert.equal(redirected,'https://m.youtube.com/');
 const fake=harness(undefined,'https://youtube.com.evil.example/shorts/abcdefghijk');let fakeRedirect=false;fake.location.replace=()=>{fakeRedirect=true;};fake.api.setOptions({hideShorts:true});assert.equal(fakeRedirect,false);
});
test('repeat identifies the ended primary instead of restarting a surviving loop player',()=>{
 const main=element(),loop=element('VIDEO',{width:16,height:16,loop:true,currentTime:33}),h=harness([main,loop]),id=h.state().mediaID;
 main.end();h.api.restart(id);assert.equal(main.paused,false);assert.equal(main.currentTime,0);assert.equal(loop.currentTime,33);
});
test('stale repeat identity and timer stop never restart another source',()=>{
 const main=element(),h=harness([main]),id=h.state().mediaID;main.end();h.api.pause(true);h.api.restart(id);assert.equal(main.paused,true);
 h.api.clearStop();main.currentSrc='https://cdn.example/other.mp4';h.tick();h.api.restart(id);assert.equal(main.paused,true);
});
test('audio demand reports all active elements until every asynchronous pause is acknowledged',()=>{
 const main=element(),audio=element('AUDIO'),h=harness([main,audio]);main.pause();assert.equal(h.state().playing,false);assert.equal(h.state().anyPlaying,true);
 audio.pause();assert.equal(h.state().anyPlaying,false);
});
