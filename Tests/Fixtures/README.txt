Local media fixtures

sample.mp4 contains four seconds of a uniform teal image and a synthetic 440 Hz
tone, generated specifically for this project's decoder/integration tests.
It contains no footage, images, audio recordings, logos or accounts from a
third-party service. No ad platform is contacted by these fixtures.

Regenerate from the repository root using an installed ffmpeg:

ffmpeg -hide_banner -loglevel error -y -f lavfi -i color=c=teal:s=160x90:r=12 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 4 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -b:a 32k -movflags +faststart Tests/Fixtures/sample.mp4

media.html and Scripts/check-browser.py test the original Playback.js with real
Chromium decoding. The Python script generates its own eight-second video under
ignored build/browser-fixtures/. They do not claim iOS/provider compatibility.
