'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../App/Resources/WatchPresentation.js'),'utf8');
function harness(url,embedded=false) {
 const styles=new Map(),attributes=new Map(),windowEvents={},documentEvents={},content={title:'Real site title',comments:['Real site comment'],controls:{visible:true}},location=new URL(url);
 const document={documentElement:{setAttribute:(k,v)=>attributes.set(k,v),removeAttribute:k=>attributes.delete(k)},
  head:{appendChild(style){styles.set(style.id,style);}},getElementById:id=>styles.get(id),
  createElement(){const style={id:'',textContent:'',remove(){styles.delete(style.id);}};return style;},
  addEventListener(n,fn){documentEvents[n]=fn;},content};
 const window={addEventListener(n,fn){windowEvents[n]=fn;}};window.top=embedded?{}:window;
 const sandbox={window,document,location,URL};vm.createContext(sandbox);vm.runInContext(source,sandbox);
 return {api:sandbox.__webkwebWatch,styles,attributes,windowEvents,documentEvents,location,content,
  watch:()=>attributes.has('data-webkweb-watch')};
}
test('genuine watch route with video ID is decorated without replacing page content',()=>{
 const h=harness('https://m.youtube.com/watch?v=abcdefghijk');assert.equal(h.watch(),true);assert.equal(h.styles.size,1);
 assert.equal(h.content.title,'Real site title');assert.equal(h.content.comments.length,1);assert.equal(h.content.controls.visible,true);
});
test('watch query order hash and encoded ID keep the same route',()=>{
 const h=harness('https://www.youtube.com/watch?list=PLabc&v=abcde%66ghijk&t=12#comments');assert.equal(h.watch(),true);
 assert.equal(h.api.matches('http://youtube.com/watch?v=abcdefghijk'),true);
});
test('host spoof credentials schemes and non-watch pages do not enter watch mode',()=>{
 const urls=['https://youtube.com.evil.example/watch?v=abcdefghijk','https://notyoutube.com/watch?v=abcdefghijk',
  'https://youtube.com@evil.example/watch?v=abcdefghijk','https://user:password@youtube.com/watch?v=abcdefghijk',
  'ftp://youtube.com/watch?v=abcdefghijk','https://m.youtube.com/watch?v=short',
  'https://m.youtube.com/results?v=abcdefghijk','https://m.youtube.com/shorts/abcdefghijk','https://www.youtube.com/embed/abcdefghijk'];
 for(const url of urls){const h=harness(url);assert.equal(h.watch(),false,url);assert.equal(h.styles.size,0,url);}
});
test('SPA leave and return removes and restores only app presentation style',()=>{
 const h=harness('https://m.youtube.com/watch?v=abcdefghijk');h.styles.set('site-style',{id:'site-style'});
 h.location.href='https://m.youtube.com/results?search_query=test';h.documentEvents['yt-navigate-finish']();
 assert.equal(h.watch(),false);assert.equal(h.styles.size,1);assert.ok(h.styles.has('site-style'));
 h.location.href='https://m.youtube.com/watch?v=12345678901';h.documentEvents['yt-navigate-finish']();assert.equal(h.watch(),true);assert.equal(h.styles.size,2);
});
test('history back forward and BFCache pageshow reconcile current route',()=>{
 const h=harness('https://m.youtube.com/');h.location.href='https://m.youtube.com/watch?v=abcdefghijk';h.windowEvents.popstate();assert.equal(h.watch(),true);
 h.location.href='https://m.youtube.com/';h.windowEvents.popstate();assert.equal(h.watch(),false);
 h.location.href='https://m.youtube.com/watch?v=abcdefghijk';h.windowEvents.pageshow();assert.equal(h.watch(),true);
});
test('presentation is not injected into embedded players',()=>{
 const h=harness('https://m.youtube.com/watch?v=abcdefghijk',true);assert.equal(h.watch(),false);assert.equal(h.api,undefined);
});
test('repeated route refresh does not duplicate style elements',()=>{
 const h=harness('https://m.youtube.com/watch?v=abcdefghijk');for(let i=0;i<20;i++)h.api.update();assert.equal(h.styles.size,1);
});
test('native exit restores original website masthead and survives SPA and BFCache updates',()=>{
 const h=harness('https://m.youtube.com/watch?v=abcdefghijk');h.styles.set('site-style',{id:'site-style'});
 h.api.setImmersive(false);assert.equal(h.watch(),false);assert.ok(h.styles.has('site-style'));assert.equal(h.styles.size,1);
 h.documentEvents['yt-navigate-finish']();h.windowEvents.pageshow();h.windowEvents.popstate();assert.equal(h.watch(),false);
 assert.equal(h.content.title,'Real site title');assert.equal(h.content.comments[0],'Real site comment');
 h.api.setImmersive(true);assert.equal(h.watch(),true);assert.equal(h.styles.size,2);
});
