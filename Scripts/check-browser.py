#!/usr/bin/env python3
"""Real Chromium media checks; never an iOS/WebKit or provider compatibility claim.

Needs Python Playwright, Chromium and ffmpeg. Runs only against a loopback fixture
and locally generated test media; no third-party accounts, videos or ad systems.
Generated media and reports stay under ignored build/. This script starts no Actions.
"""
from __future__ import annotations
import argparse, asyncio, datetime, hashlib, http.server, json, pathlib
import shutil, subprocess, threading, time
from urllib.parse import urlparse

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPORT = ROOT / 'build' / 'reports'
MEDIA = ROOT / 'build' / 'browser-fixtures' / 'media.mp4'


def prepare_media():
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        raise RuntimeError('ffmpeg is required to generate our own test video')
    MEDIA.parent.mkdir(parents=True, exist_ok=True)
    # Generated test pattern and sine wave: no third-party film, image or audio.
    cmd = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
           '-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=12',
           '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100',
           '-t', '8', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
           '-c:a', 'aac', '-movflags', '+faststart', str(MEDIA)]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=40)
    if result.returncode:
        raise RuntimeError('Test video generation failed: ' + result.stderr[:1500])


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        path = urlparse(self.path).path
        if path == '/fixture.html':
            data = (ROOT / 'Tests' / 'Fixtures' / 'media.html').read_bytes()
            content_type = 'text/html; charset=utf-8'
        elif path == '/media.mp4':
            data = MEDIA.read_bytes(); content_type = 'video/mp4'
        else:
            self.send_error(404); return
        # Chrome's real media pipeline uses byte ranges for seeks/metadata.
        start, end, partial = 0, len(data) - 1, False
        if self.headers.get('Range', '').startswith('bytes='):
            requested = self.headers['Range'][6:].split('-', 1)
            try:
                start = int(requested[0]); end = int(requested[1]) if requested[1] else end
                end = min(end, len(data) - 1)
                if start < 0 or start > end: raise ValueError()
                partial = True
            except ValueError:
                self.send_error(416); return
        self.send_response(206 if partial else 200)
        self.send_header('Content-Type', content_type)
        self.send_header('Accept-Ranges', 'bytes')
        if partial: self.send_header('Content-Range', f'bytes {start}-{end}/{len(data)}')
        self.send_header('Content-Length', str(end - start + 1)); self.end_headers()
        try: self.wfile.write(data[start:end + 1])
        except (BrokenPipeError, ConnectionResetError): pass


async def run_checks(executable, playback_script=None):
    from playwright.async_api import async_playwright
    prepare_media(); REPORT.mkdir(parents=True, exist_ok=True)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    base = f'http://127.0.0.1:{server.server_port}'
    bridge = (playback_script or ROOT / 'App' / 'Resources' / 'Playback.js').read_text()
    injection = '''window.__messages = [];
window.webkit = {messageHandlers: {playback: {postMessage(m) { window.__messages.push(m); }}}};
document.addEventListener('DOMContentLoaded', () => { BRIDGE }, {once:true});'''.replace('BRIDGE', bridge)
    results = []
    async with async_playwright() as pw:
        browser = await pw.chromium.launch(executable_path=executable, headless=True,
                                          args=['--no-sandbox', '--disable-dev-shm-usage'])
        async def case(name, mode, check):
            context = await browser.new_context(viewport={'width': 900, 'height': 900})
            await context.route('**/*', lambda route: route.continue_() if
                                urlparse(route.request.url).hostname in ('127.0.0.1', 'localhost')
                                else route.abort())
            await context.add_init_script(injection)
            page = await context.new_page(); errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            started = time.monotonic()
            try:
                await page.goto(base + '/fixture.html?mode=' + mode)
                await page.wait_for_function('Boolean(globalThis.__webkweb)')
                if mode in ('video', 'audio'):
                    await page.wait_for_function('document.querySelector("#main").readyState >= 2')
                await check(page)
                assert not errors, 'Uncaught browser errors: ' + repr(errors)
                results.append({'case': name, 'status': 'PASS', 'seconds': round(time.monotonic()-started, 2)})
            except Exception as error:
                shot = REPORT / ('browser-' + name + '.png')
                await page.screenshot(path=str(shot))
                diagnostics = await page.evaluate('''() => ({
                    trustedClick: window.websiteTrustedClick,
                    playEvents: window.websitePlayEvents,
                    media: [...document.querySelectorAll('video,audio')].map(v => ({
                        paused:v.paused, time:v.currentTime, readyState:v.readyState,
                        error:v.error ? v.error.code : null})),
                    messages: (window.__messages || []).slice(-8)
                })''')
                results.append({'case': name, 'status': 'FAIL', 'error': str(error)[:1500],
                                'page_errors': errors, 'diagnostics': diagnostics, 'screenshot': str(shot)})
            finally:
                await context.close()
            print(results[-1]['status'] + ': ' + name, flush=True)

        async def playback(p):
            await p.click('#play')
            await p.wait_for_function('document.querySelector("video").currentTime > 0.3')
            await p.evaluate('__webkweb.pause()')
            before = await p.eval_on_selector('video', 'v => v.currentTime')
            await p.wait_for_timeout(200)
            after = await p.eval_on_selector('video', 'v => v.currentTime')
            assert abs(after-before) < 0.08
            await p.evaluate('__webkweb.seek(3); __webkweb.setRate(1.5)')
            await p.wait_for_function('document.querySelector("video").currentTime >= 3')
            s = await p.evaluate('__messages.filter(m => m.kind === "state").at(-1)')
            assert s['rate'] == 1.5 and s['width'] == 160 and s['height'] == 90, s
            assert 'source' not in s and 'contentType' not in s

        async def captions(p):
            await p.evaluate('''() => { const v=document.querySelector('video');
                const t=v.addTextTrack('subtitles','Deutsch','de');t.addCue(new VTTCue(0,8,'Own test cue'));
                __webkweb.setCaption(0); }''')
            assert await p.eval_on_selector('video', 'v => v.textTracks[0].mode') == 'showing'
            await p.evaluate('__webkweb.setCaption(-1)')
            assert await p.eval_on_selector('video', 'v => v.textTracks[0].mode') == 'disabled'

        async def website_play_after_stop(p):
            # A site's own play control calls HTMLMediaElement.play(), rather
            # than the app's __webkweb.resume() shortcut used by #play.
            await p.evaluate('''() => {
                const v = document.querySelector('video');
                const player = document.createElement('div');
                v.before(player); player.append(v);
                player.style.cssText = 'position:relative;width:640px;height:360px';
                const button = document.createElement('button');
                button.id = 'website-play'; button.textContent = 'Play';
                button.setAttribute('aria-label', 'Play');
                button.style.cssText = 'position:absolute;left:270px;top:140px';
                button.onclick = event => {
                    window.websiteTrustedClick = event.isTrusted;
                    v.play().catch(() => {});
                };
                player.append(button); __webkweb.pause(true);
            }''')
            await p.evaluate('document.querySelector("video").play().catch(() => {})')
            await p.wait_for_timeout(100)
            assert await p.eval_on_selector('video', 'v => v.paused'), 'Autoplay bypassed stop latch'
            await p.evaluate('document.querySelector("#website-play").click()')
            await p.wait_for_timeout(100)
            assert await p.eval_on_selector('video', 'v => v.paused'), 'Synthetic click bypassed stop latch'
            await p.click('#website-play')
            assert await p.evaluate('window.websiteTrustedClick === true')
            await p.wait_for_function('!document.querySelector("video").paused && document.querySelector("video").currentTime > 0.2', timeout=2500)

        async def native_web_controls_after_stop(p):
            await p.evaluate('''() => {
                const v = document.querySelector('video');
                window.websitePlayEvents = 0;
                v.addEventListener('play', () => window.websitePlayEvents++);
                __webkweb.pause(true);
            }''')
            video = p.locator('video')
            await video.hover()
            bounds = await video.bounding_box()
            await p.evaluate('''() => {
                __webkweb.noteHostTouch?.({x:0.99,y:0.99});
                document.querySelector('video').play().catch(() => {});
            }''')
            await p.wait_for_timeout(100)
            assert await p.eval_on_selector('video', 'v => v.paused'), 'A touch outside media bypassed the stop'
            await p.evaluate('window.websitePlayEvents=0')
            viewport = await p.evaluate('({width:innerWidth,height:innerHeight})')
            point = {'x': (bounds['x'] + 24) / viewport['width'],
                     'y': (bounds['y'] + bounds['height'] - 48) / viewport['height']}
            # Chromium's built-in media controls hide pointer events from DOM.
            # Emulate the native host's isolated touch callback, then click the
            # actual Chromium play control. This does not test UIKit itself.
            await p.evaluate('(point) => __webkweb.noteHostTouch?.(point)', point)
            assert await p.eval_on_selector('video', 'v => v.paused'), 'Touch notification started playback itself'
            await video.click(position={'x': 24, 'y': bounds['height'] - 48})
            await p.wait_for_function('window.websitePlayEvents > 0', timeout=2500)
            await p.wait_for_function('!document.querySelector("video").paused && document.querySelector("video").currentTime > 0.2', timeout=2500)

        async def replay(p):
            await p.click('#play')
            await p.evaluate('__webkweb.seek(7.7)')
            await p.wait_for_function('__messages.filter(m=>m.kind==="ended").length === 1')
            first = await p.evaluate('__messages.find(m=>m.kind==="ended").eventID')
            await p.click('#play')
            await p.wait_for_function('document.querySelector("video").currentTime > 0.1 && !document.querySelector("video").ended')
            await p.evaluate('__webkweb.seek(8)')
            await p.wait_for_function('__messages.filter(m=>m.kind==="ended").length === 2')
            ids = await p.evaluate('__messages.filter(m=>m.kind==="ended").map(m=>m.eventID)')
            assert ids[0] == first and ids[0] != ids[1], ids

        async def stop_latch(p):
            await p.click('#play'); await p.evaluate('__webkweb.pause(true)')
            await p.evaluate('''async () => { const v=fixture.video(undefined,'new');
                try { await v.play(); } catch (_) {} }''')
            assert await p.eval_on_selector('#new', 'v => v.paused')
            await p.evaluate('__webkweb.clearStop()')
            assert await p.eval_on_selector('#main', 'v => v.paused')
            await p.click('#play')
            await p.wait_for_function('!document.querySelector("#main").paused')

        async def queue_loop(p):
            await p.evaluate('document.querySelector("video").loop=true;__webkweb.setQueueManaged(true)')
            assert not await p.eval_on_selector('video', 'v => v.loop')
            await p.eval_on_selector('video', 'v => {v.src="/media.mp4?second";v.load()}')
            await p.wait_for_function('document.querySelector("video").readyState>=2')
            await p.evaluate('__webkweb.state();__webkweb.setQueueManaged(false)')
            assert await p.eval_on_selector('video', 'v => v.loop')

        async def rapid_player(p):
            # Explicit action happens in the same task as insertion, before MO delivery.
            await p.evaluate('fixture.video();__webkweb.resume()')
            await p.wait_for_function('document.querySelector("video").currentTime > 0.1', timeout=4000)

        async def shadow_player(p):
            await p.evaluate('fixture.shadow();__webkweb.resume()')
            await p.wait_for_function('document.querySelector("section").shadowRoot.querySelector("video").currentTime>0.1', timeout=4000)

        async def source_identity(p):
            first = await p.evaluate('__messages.filter(m=>m.kind==="state").at(-1).mediaID')
            await p.eval_on_selector('video', 'v => {v.src="/media.mp4?replacement";v.load()}')
            await p.wait_for_function('document.querySelector("video").readyState>=2')
            await p.wait_for_function('(id)=>__messages.filter(m=>m.kind==="state").at(-1).mediaID !== id', arg=first)

        async def frames(p):
            await p.wait_for_function('document.querySelectorAll("iframe").length===2')
            children = [f for f in p.frames if f != p.main_frame]
            ids = []
            for f in children:
                await f.wait_for_function('Boolean(__webkweb) && document.querySelector("video").readyState>=2')
                await f.evaluate('__webkweb.resume()')
                await f.wait_for_function('document.querySelector("video").currentTime > 0.1')
                ids.append(await f.evaluate('__messages.find(m=>m.kind==="ready").documentID'))
            assert len(ids)==2 and ids[0]!=ids[1]
            for f in children: await f.evaluate('__webkweb.pause(true)')
            assert all([await f.eval_on_selector('video','v=>v.paused') for f in children])

        async def navigation(p):
            await p.evaluate('history.pushState({}, "", "?mode=video&next=1")')
            await p.wait_for_function('__messages.some(m=>m.kind==="navigation" && m.address.includes("next=1"))')

        async def audio(p):
            await p.click('#play'); await p.evaluate('__webkweb.seek(8)')
            await p.wait_for_function('__messages.some(m=>m.kind==="queueended")')
            assert not await p.evaluate('__messages.some(m=>m.kind==="ended")')

        async def media_error(p):
            await p.eval_on_selector('video', 'v=>{v.src="/missing.mp4";v.load()}')
            await p.wait_for_function('__messages.some(m=>m.kind==="state" && m.mediaError)')
            await p.evaluate('__webkweb.recover()')
            await p.wait_for_function('__messages.some(m=>m.kind==="notice")')
            assert await p.eval_on_selector('video', 'v=>v.paused')

        async def fullscreen(p):
            await p.click('#play'); await p.click('#fullscreen')
            await p.wait_for_function('document.fullscreenElement || __messages.some(m=>m.kind==="notice")')

        async def pip(p):
            await p.click('#play'); await p.click('#pip')
            await p.wait_for_function('document.pictureInPictureElement || __messages.some(m=>m.kind==="notice")')

        async def airplay_fallback(p):
            await p.click('#airplay')
            await p.wait_for_function('__messages.some(m=>m.kind==="notice" && m.text.includes("AirPlay"))')

        checks = [('play-pause-seek-rate','video',playback), ('captions','video',captions),
                  ('website-play-after-native-stop','video',website_play_after_stop),
                  ('host-touch-and-native-web-controls-after-stop','video',native_web_controls_after_stop),
                  ('natural-end-replay','video',replay), ('timer-stop-latch','video',stop_latch),
                  ('queue-loop-source-restore','video',queue_loop), ('rapid-new-player','empty',rapid_player),
                  ('rapid-open-shadow-player','empty',shadow_player), ('source-identity','video',source_identity),
                  ('same-and-cross-origin-frames','frames',frames), ('spa-navigation','video',navigation),
                  ('audio-queue-not-video-count','audio',audio), ('media-error-recovery','video',media_error),
                  ('fullscreen-or-fallback','video',fullscreen), ('pip-or-fallback','video',pip),
                  ('airplay-unavailable-fallback','video',airplay_fallback)]
        for name, mode, check in checks: await case(name, mode, check)
        version = browser.version
        await browser.close()
    server.shutdown(); server.server_close()
    report = {'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'playback_sha256':hashlib.sha256(bridge.encode()).hexdigest(),
              'engine':'Chromium', 'version':version, 'real_media_decode':any(r['case']=='play-pause-seek-rate' and r['status']=='PASS' for r in results),
              'media_provenance':'Locally generated testsrc2/sine; no third-party media',
              'network_scope':'loopback only', 'checks':results,
              'native_host_touch':'Chromium invokes the isolated host callback; UIKit is not exercised by this script',
              'ios_webkit':'NOT_RUN', 'provider_playback':'NOT_RUN',
              'provider_ad_removal':'NOT_TESTED_OR_PROMISED',
              'github_actions':'NOT_STARTED_BY_THIS_SCRIPT; see workflow runs for repository build status'}
    (REPORT/'browser-check.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    return int(any(r['status']=='FAIL' for r in results))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chromium',default=shutil.which('chromium') or shutil.which('google-chrome'))
    parser.add_argument('--playback-script',type=pathlib.Path,help='Optional saved bridge for before/after regression checks')
    args=parser.parse_args()
    if not args.chromium: parser.error('Install Chromium or pass --chromium /path/to/browser')
    raise SystemExit(asyncio.run(run_checks(args.chromium,args.playback_script)))
