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
- Apple QuickTime expension
- files with CTTS atom in TRAK

This product is released under MIT license.

Please also take a look at our Nimble HTTP Streamer, the HLS edge server: https://wmspanel.com/nimble .
MP4 to HLS transmuxing is planned to be implemented as part of Nimble Streamer.
