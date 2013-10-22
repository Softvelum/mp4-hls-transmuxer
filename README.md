MP4 to HLS Transmuxer
==================

This tool performs transmuxing from MP4 to HLS.

> ruby mp4hls.rb sample.mp4 sample.ts

- sample.mp4 - input MP4 file
- sample.ts - output file

Supported formats:
- video+audio
- video
- audio
- original MP4
- Apple QuickTime extension
- files with CTTS atom in TRAK

This product is released under MIT license.

This prototype was made as part of feature investigate for Nimble HTTP Streamer VOD streaming functionality.
It currently supports MP4 transmuxing to HLS in VOD mode as origin server.

Please refer to this page for details: https://wmspanel.com/nimble/vod_streaming

