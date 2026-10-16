'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.join(__dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
const production=['App','Shared','Widgets'].flatMap(dir=>fs.readdirSync(path.join(root,dir),{recursive:true}).filter(p=>/\.(swift|js)$/.test(p)).map(p=>read(path.join(dir,p)))).join('\n');
test('no active external filter downloader, compiled filter engine or retired services',()=>{
 for(const value of ['URLSession','compileContentRuleList(','sponsor.ajay.app','adguardteam.github.io','hagezi/dns-blocklists','GoogleCast','setSegments','undoSkip'])assert.equal(production.includes(value),false,value);
 assert.equal(fs.existsSync(path.join(root,'App/Resources/WatchPresentation.js')),false);
});
test('all website bridge functionality stays in an isolated world',()=>{
 const source=read('App/BrowserSession.swift');assert.match(source,/WKContentWorld\.world/);assert.match(source,/contentWorld: Self\.world/);assert.match(source,/securityOrigin/);assert.match(source,/allowedKinds\.contains/);assert.match(source,/frames\.count < 32/);
});
test('private playback cannot create app diagnostic events or force system PiP',()=>{
 const source=read('App/BrowserSession.swift');assert.match(source,/guard !isPrivate else \{ return \}/);assert.match(source,/guard !isPrivate else \{ return .*disabled/);assert.match(source,/allowsPictureInPictureMediaPlayback = !isPrivate/);
});
test('no private website CSS, forced PiP, ad response or download path is bundled',()=>{
 const source=read('App/Resources/Playback.js');
 for(const value of ['createElement("style")','webkweb-shorts-policy','webkitSetPresentationMode','requestPictureInPicture','fetch(','XMLHttpRequest','googlevideo','ytInitialPlayerResponse'])assert.equal(source.includes(value),false,value);
});
test('production code has no third-party imports or package declarations',()=>{
 const allowed=new Set(['Foundation','SwiftUI','SwiftData','WebKit','Combine','UIKit','WidgetKit','AppIntents','AVFoundation','AVKit','MediaPlayer','UniformTypeIdentifiers','LocalAuthentication']);
 for(const match of production.matchAll(/^import (\w+)/gm))assert.ok(allowed.has(match[1]),match[1]);
 assert.equal(read('project.yml').includes('packages:'),false);
});
test('old filter cache is actively cleaned, user filter imports are never loaded',()=>{
 const source=read('App/Rules.swift');assert.match(source,/removeContentRuleList/);assert.match(source,/FilterSourceCache/);assert.equal(source.includes('ImportedFilters"'),false);
});

test('removed Share extension cannot be built, provisioned or consume incoming links',()=>{
 assert.equal(fs.existsSync(path.join(root,'ShareExtension')),false);
 assert.equal(fs.existsSync(path.join(root,'Shared/ShareInbox.swift')),false);
 assert.equal(read('project.yml').includes('ShareExtension'),false);
 assert.equal(read('App/BrowserSession.swift').includes('consumeSharedLinks'),false);
 const workflow=read('.github/workflows/testflight.yml');
 assert.equal(workflow.includes('APPLE_SHARE_PROVISIONING_PROFILE'),false);
 assert.equal(workflow.includes('provision-share.py'),false);
});
