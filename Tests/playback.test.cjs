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
function harness(initial=[element()],url='https://m.youtube.com/watch?v=abcdefghijk',startPaused=false) {
 const nodes=initial,messages=[],documentEvents={},windowEvents={},shadowHosts=[],inputTasks=[]; let tick,mutation,clock=Date.now(),queries=0;
 const location=new URL(url);
 const document={title:'Video',baseURI:url,hidden:false,querySelector(){return null;},querySelectorAll(s){queries++;return s==='*'?shadowHosts:s==='video'?nodes.filter(n=>n.tagName==='VIDEO'):nodes;},addEventListener(n,h){documentEvents[n]=h;}};
 const sandbox={__webkwebStartPaused:startPaused,URL,Math,Number,Array,Boolean,Date:class extends Date {static now(){return clock;}},innerWidth:1000,innerHeight:1000,location,document,
  window:{webkit:{messageHandlers:{playback:{postMessage(v){messages.push(v);}}}},addEventListener(n,h){windowEvents[n]=h;}},
  setInterval(fn){tick=fn;return 1;},setTimeout(fn){inputTasks.push(fn);return 1;},MutationObserver:class {constructor(fn){mutation=fn;}observe(){}}
 };
 vm.createContext(sandbox);vm.runInContext(source,sandbox);
 return {api:sandbox.__webkweb,nodes,messages,location,document,documentEvents,windowEvents,shadowHosts,
  tick(){clock+=1000;tick();},stepInputTask(){inputTasks.shift()?.();},flushInputTasks(){while(inputTasks.length)inputTasks.shift()();},advance(ms){clock+=ms;},queries:()=>queries,add(v){nodes.push(v);mutation([{addedNodes:[v]}]);},state(){return messages.filter(m=>m.kind==='state').at(-1);}};
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
test('trusted semantic website Play releases stop and acknowledges native state',()=>{
 const v=element(),h=harness([v]),button={tagName:'BUTTON',textContent:'Play'},container={querySelectorAll:()=>[v]};h.api.pause(true);
 h.documentEvents.click({isTrusted:true,composedPath:()=>[button,container]});v.play();
 assert.equal(v.paused,false);assert.equal(h.state().playing,true);assert.equal(h.messages.filter(m=>m.kind==='userplay').length,1);
 assert.equal(h.messages.find(m=>m.kind==='userplay').mediaID,h.state().mediaID);
});
test('synthetic website clicks and programmatic autoplay cannot release stop',()=>{
 const v=element(),h=harness([v]),button={tagName:'BUTTON',textContent:'Play'},container={querySelectorAll:()=>[v]};h.api.pause(true);
 h.documentEvents.click({isTrusted:false,composedPath:()=>[button,container]});v.play();
 assert.equal(v.paused,true);assert.equal(h.messages.filter(m=>m.kind==='userplay').length,0);
});
test('trusted native video controls can resume but old input expires',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);h.documentEvents.pointerdown({isTrusted:true,composedPath:()=>[v]});
 h.advance(1501);v.play();assert.equal(v.paused,true);
 h.documentEvents.pointerdown({isTrusted:true,composedPath:()=>[v]});v.play();assert.equal(v.paused,false);
});
test('play intent only authorizes its own player and ignores unrelated buttons',()=>{
 const main=element(),small=element('VIDEO',{width:16,height:16}),h=harness([main,small]);h.api.pause(true);
 const other={tagName:'BUTTON',textContent:'Subscribe'},container={querySelectorAll:()=>[main]};
 h.documentEvents.click({isTrusted:true,composedPath:()=>[other,container]});main.play();assert.equal(main.paused,true);
 h.documentEvents.pointerdown({isTrusted:true,composedPath:()=>[main]});small.play();assert.equal(small.paused,true);
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,0);
 main.play();assert.equal(main.paused,false);assert.equal(h.messages.filter(m=>m.kind==='userplay').length,1);
});
test('keyboard Play and quiet restore bootstrap use the same explicit intent boundary',()=>{
 const v=element(),h=harness([v],'https://example.com/player',true);assert.equal(v.paused,true);v.play();assert.equal(v.paused,true);
 const button={tagName:'BUTTON',textContent:'Abspielen'},container={querySelectorAll:()=>[v]};
 h.documentEvents.keydown({key:'Enter',isTrusted:true,composedPath:()=>[button,container]});v.play();assert.equal(v.paused,false);
});
test('isolated host touch only arms media at its rectangle and never starts playback itself',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 h.api.noteHostTouch({x:0.9,y:0.9});v.play();assert.equal(v.paused,true);
 h.api.noteHostTouch({x:0.1,y:0.1});assert.equal(v.paused,true);v.play();assert.equal(v.paused,false);
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,1);
});
test('trusted overlay input arms its video before a delayed UIKit observation',()=>{
 const v=element(),h=harness([v]),button={tagName:'BUTTON',textContent:'Start'};h.api.pause(true);
 h.documentEvents.click({type:'click',isTrusted:true,clientX:110,clientY:72,composedPath:()=>[button]});
 assert.equal(v.paused,true);v.play();assert.equal(v.paused,false);
 // The later isolated host observation must not pause or restart playback.
 h.api.noteHostTouch({x:0.11,y:0.072});assert.equal(v.paused,false);
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,1);
});
test('synthetic, off-video and keyboard coordinates cannot authorize an overlay play',()=>{
 const v=element(),h=harness([v]),button={tagName:'BUTTON',textContent:'Start'};h.api.pause(true);
 for(const input of [{type:'click',isTrusted:false,clientX:100,clientY:100},
  {type:'click',isTrusted:true,clientX:950,clientY:950},
  {type:'keydown',key:'Enter',isTrusted:true,clientX:100,clientY:100}]){
  const event={...input,composedPath:()=>[button]};
  h.documentEvents[input.type](event);v.play();assert.equal(v.paused,true);
 }
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,0);
});
test('invalid or stale host touches do not release timer stop',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 for(const point of [{x:-1,y:0},{x:NaN,y:0},{x:0,y:Infinity},{x:2,y:0}]){h.api.noteHostTouch(point);v.play();assert.equal(v.paused,true);}
 h.api.noteHostTouch({x:0.1,y:0.1});h.advance(1501);v.play();assert.equal(v.paused,true);
});
test('timer tick between synchronous play and its queued event preserves fresh explicit intent',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 h.documentEvents.pointerdown({isTrusted:true,composedPath:()=>[v]});
 // HTMLMediaElement.play sets paused=false before dispatching its play event.
 v.paused=false;h.tick();assert.equal(v.paused,false);
 v.listeners.play();assert.equal(v.paused,false);assert.equal(h.messages.filter(m=>m.kind==='userplay').length,1);
});
test('trusted input acknowledges requested play even when WebKit dispatches play six seconds later',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 h.documentEvents.click({isTrusted:true,composedPath:()=>[v]});
 // HTMLMediaElement.play() changes paused before its queued play event. Model
 // the 5.759s event delay measured in the real unmuted iOS UI failure.
 v.paused=false;h.flushInputTasks();
 assert.equal(h.state().stopLatched,false);
 h.advance(6000);v.listeners.play();
 assert.equal(v.paused,false);assert.equal(h.state().playing,true);
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,1);
});
test('input task does not start media or authorize a later autoplay',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 h.documentEvents.click({isTrusted:true,composedPath:()=>[v]});h.flushInputTasks();
 assert.equal(v.paused,true);assert.equal(h.messages.filter(m=>m.kind==='userplay').length,0);
 h.advance(1501);v.play();assert.equal(v.paused,true);
});
test('requested play can become active after the first input task before its delayed play event',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 h.documentEvents.click({isTrusted:true,composedPath:()=>[v]});h.stepInputTask();
 // The first cross-world task still sees paused. The website's real request
 // becomes observable shortly afterwards; only its play event is six seconds late.
 h.advance(80);v.paused=false;h.flushInputTasks();
 assert.equal(h.state().stopLatched,false);
 h.advance(6000);v.listeners.play();assert.equal(v.paused,false);
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,1);
});
test('bounded pending input sampling cannot survive a newer Stop',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 h.api.noteHostTouch({x:0.1,y:0.1});h.stepInputTask();h.api.pause(true);
 h.advance(80);v.paused=false;h.flushInputTasks();v.listeners.play();
 assert.equal(v.paused,true);assert.equal(h.state().stopLatched,true);
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,0);
});
test('a still-dispatching trusted Play input is not confused with later autoplay after audio startup blocks',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 const event={isTrusted:true,eventPhase:1,composedPath:()=>[v]};
 h.documentEvents.click(event);const originalInputAt=h.state().interactionAt;
 h.advance(6000);event.eventPhase=2;v.paused=false;
 v.listeners.play();event.eventPhase=0;
 assert.equal(v.paused,false);assert.equal(h.state().stopLatched,false);
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,1);
 assert.equal(h.messages.find(m=>m.kind==='userplay').inputAt,originalInputAt);
});
test('a completed trusted event does not authorize later script playback',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 const event={isTrusted:true,eventPhase:1,composedPath:()=>[v]};
 h.documentEvents.click(event);event.eventPhase=0;h.advance(6000);v.play();
 assert.equal(v.paused,true);assert.equal(h.state().stopLatched,true);
});
test('a pathological trusted handler cannot keep play authorization indefinitely',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 const event={isTrusted:true,eventPhase:1,composedPath:()=>[v]};
 h.documentEvents.click(event);event.eventPhase=2;h.advance(15001);v.play();
 assert.equal(v.paused,true);assert.equal(h.state().stopLatched,true);
});
test('isolated real host touch acknowledges an already requested native-control play',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);v.paused=false;
 h.api.noteHostTouch({x:0.1,y:0.1});h.flushInputTasks();
 assert.equal(h.state().stopLatched,false);
 h.advance(6000);v.listeners.play();assert.equal(v.paused,false);
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,1);
});
test('a new Stop invalidates a queued input acknowledgement',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 h.documentEvents.click({isTrusted:true,composedPath:()=>[v]});v.paused=false;
 h.api.pause(true);h.flushInputTasks();h.advance(6000);v.play();
 assert.equal(v.paused,true);assert.equal(h.state().stopLatched,true);
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,0);
});
test('a delayed input task never extends the 1.5-second intent deadline',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);
 h.documentEvents.click({isTrusted:true,composedPath:()=>[v]});v.paused=false;
 h.advance(1501);h.flushInputTasks();v.listeners.play();
 assert.equal(v.paused,true);assert.equal(h.state().stopLatched,true);
 assert.equal(h.messages.filter(m=>m.kind==='userplay').length,0);
});
test('new already-playing autoplay video is paused immediately after insertion',()=>{
 const h=harness();h.api.pause(true);const next=element();h.add(next);assert.equal(next.paused,true);
});
test('clearStop cancels latch without starting paused media',()=>{
 const h=harness();h.api.pause(true);h.api.clearStop();assert.equal(h.nodes[0].paused,true);
 h.nodes[0].play();assert.equal(h.nodes[0].paused,false);
});
test('visibility changes report background pause without resuming website media',()=>{
 const v=element(),h=harness([v]);v.pause();const before=h.messages.length;
 h.document.hidden=true;h.documentEvents.visibilitychange();
 assert.equal(v.paused,true);assert.equal(h.state().hidden,true);
 h.document.hidden=false;h.documentEvents.visibilitychange();
 assert.equal(v.paused,true);assert.equal(h.state().hidden,false);
 assert.deepEqual(h.messages.slice(before).filter(m=>m.kind==='mediaevent').map(m=>m.event),['hidden','visible']);
 assert.equal(h.messages.slice(before).some(m=>m.kind==='started'),false);
});
test('diagnostics distinguish observed pause from app stop rejection without media URLs',()=>{
 const v=element(),h=harness([v]);h.api.pause(true);v.play();
 const events=h.messages.filter(m=>m.kind==='mediaevent');
 assert.ok(events.some(m=>m.event==='pause'));assert.ok(events.some(m=>m.event==='stop-rejected'));
 assert.ok(events.every(m=>m.source===undefined&&m.currentSrc===undefined&&m.title===undefined));
});
test('presentation state is observed without requesting website PiP or fullscreen',()=>{
 const v=element('VIDEO',{webkitPresentationMode:'inline'}),h=harness([v]);
 assert.equal(h.state().presentationMode,'inline');
 v.webkitPresentationMode='picture-in-picture';h.api.state();
 assert.equal(h.state().presentationMode,'picture-in-picture');
 v.webkitPresentationMode='unexpected';h.api.state();assert.equal(h.state().presentationMode,'unknown');
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
test('manual audio selection uses exposed tracks without inferring an original language',()=>{
 const audioTracks=[{label:'English',enabled:true},{label:'Deutsch Original',enabled:false}],h=harness([element('VIDEO',{audioTracks})]);
 assert.equal(audioTracks[0].enabled,true);assert.equal(audioTracks[1].enabled,false);assert.equal(h.api.setOptions,undefined);
 h.api.setAudio(1);assert.equal(audioTracks[0].enabled,false);assert.equal(audioTracks[1].enabled,true);
});
test('rate limits reject invalid settings without changing volume',()=>{
 const v=element('VIDEO',{volume:0.4,playbackRate:1}),h=harness([v]);h.api.setRate(2);assert.equal(v.playbackRate,2);h.api.setRate(99);assert.equal(v.playbackRate,2);assert.equal(v.volume,0.4);
});
test('website fullscreen remains public while forced website PiP and AirPlay are absent',()=>{
 let fullscreen=0;const h=harness([element('VIDEO',{webkitEnterFullscreen(){fullscreen++;}})]);
 h.api.fullscreen();assert.equal(fullscreen,1);
 for(const key of ['pip','autoPiP','airplay','setOptions'])assert.equal(h.api[key],undefined);
});
test('waiting recovery respects timer latch and preserves mute',()=>{
 const v=element('VIDEO',{muted:true}),h=harness([v]);v.listeners.waiting();assert.equal(h.state().waiting,true);
 h.api.pause(true);h.api.recover();assert.equal(v.paused,true);h.api.clearStop();h.api.recover();assert.equal(v.paused,false);assert.equal(v.muted,true);
 v.listeners.playing();assert.equal(h.state().waiting,false);
});
test('paused or ended players never retain a stale buffering indicator',()=>{
 const v=element('VIDEO',{readyState:2}),h=harness([v]);v.listeners.waiting();assert.equal(h.state().waiting,true);
 v.pause();assert.equal(h.state().waiting,false);
 v.play();v.listeners.waiting();v.end();assert.equal(h.state().waiting,false);
});
test('stalled network event does not mark an already buffered playing video as loading',()=>{
 const v=element('VIDEO',{readyState:4}),h=harness([v]);v.listeners.stalled();
 assert.equal(h.state().waiting,false);assert.equal(h.state().playing,true);
});
test('foreground ticks avoid whole-DOM queries until sparse discovery',()=>{
 const h=harness(),before=h.queries();for(let i=0;i<10;i++)h.tick();assert.equal(h.queries(),before);
 h.advance(15000);h.tick();assert.ok(h.queries()>before);
});
test('background ticks reduce state traffic and skip discovery',()=>{
 const h=harness();h.api.setBackground(true);const before=h.messages.length,queries=h.queries();for(let i=0;i<10;i++)h.tick();
 assert.equal(h.messages.slice(before).filter(m=>m.kind==='state').length,2);assert.equal(h.queries(),queries);
});
test('YouTube Shorts navigation is left unchanged without hidden route rewriting',()=>{
 const h=harness(undefined,'https://m.youtube.com/shorts/abcdefghijk');let redirected=false;h.location.replace=()=>{redirected=true;};h.tick();
 assert.equal(redirected,false);assert.equal(h.location.pathname,'/shorts/abcdefghijk');assert.equal(h.api.setOptions,undefined);
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

test('timer pause immediately finds a player added to an existing open shadow root',()=>{
 const h=harness([]),video=element();
 h.shadowHosts.push({shadowRoot:{querySelectorAll(selector){return selector==='*'?[]:[video];}}});
 h.api.pause(true);assert.equal(video.paused,true);
});
test('explicit resume and fullscreen find late open-shadow media without waiting for discovery tick',()=>{
 let fullscreen=0;const h=harness([]),video=element('VIDEO',{paused:true,webkitEnterFullscreen(){fullscreen++;}});
 h.shadowHosts.push({shadowRoot:{querySelectorAll(selector){return selector==='*'?[]:[video];}}});
 h.api.resume();assert.equal(video.paused,false);h.api.fullscreen();assert.equal(fullscreen,1);
});
test('pointer selection registers newly exposed shadow media before controlling it',()=>{
 const main=element(),shadow=element('VIDEO',{width:32,height:32}),h=harness([main]);
 h.documentEvents.pointerdown({composedPath:()=>[shadow]});h.api.seek(10);
 assert.equal(shadow.currentTime,10);assert.equal(main.currentTime,0);
});
test('background timeupdate events retain sparse heartbeat but publish real pauses immediately',()=>{
 const h=harness();h.api.setBackground(true);const start=h.messages.length;
 for(let i=0;i<10;i++){h.advance(1000);h.nodes[0].listeners.timeupdate();}
 assert.equal(h.messages.slice(start).filter(message=>message.kind==='state').length,2);
 h.nodes[0].pause();assert.equal(h.state().playing,false);
});
