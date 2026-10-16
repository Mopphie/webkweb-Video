Local media fixtures

sample.mp4 contains four seconds of a uniform teal image and a synthetic 440 Hz
tone, generated specifically for this project's decoder/integration tests.
It contains no footage, images, audio recordings, logos or accounts from a
third-party service. No ad platform is contacted by these fixtures.

audible.mp4 is a separate 60-second low-bitrate generated test pattern and sine
tone. Audible UI playback uses it so a four-second loop does not reset the media
clock during a sustained-progress assertion. Playback-quality frame counters
also distinguish real frame progress across a loop from a stalled clock.

Regenerate from the repository root using an installed ffmpeg:

ffmpeg -hide_banner -loglevel error -y -f lavfi -i color=c=teal:s=160x90:r=12 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 4 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -b:a 32k -movflags +faststart Tests/Fixtures/sample.mp4

ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=64x36:rate=3 -f lavfi -i sine=frequency=440:sample_rate=16000 -t 60 -c:v libx264 -preset veryslow -profile:v baseline -crf 42 -pix_fmt yuv420p -c:a aac -b:a 8k -movflags +faststart Tests/Fixtures/audible.mp4

media.html and Scripts/check-browser.py test the original Playback.js with real
Chromium decoding. The Python script generates its own eight-second video under
ignored build/browser-fixtures/. They do not claim iOS/provider compatibility.
