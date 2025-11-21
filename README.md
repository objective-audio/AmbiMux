# AmbiMux

`AmbiMux` is a CLI tool that embeds or replaces spatial audio in MOV videos for Apple Vision Pro. It supports both encoding from audio files (4-channel B-format Ambisonics) and copying APAC-encoded spatial audio without re-encoding.

## Features

- **Apple Vision Pro Support**: Optimized for spatial audio playback on Apple Vision Pro
- **B-format Ambisonics Encoding**: Encodes 4-channel B-format Ambisonics in APAC format
- **APAC Input Support**: Supports APAC-encoded input files with any channel count (copies without re-encoding)
- **MOV Output**: Output in MOV container format compatible with Vision Pro
- **Video Preservation**: Preserves original video tracks

## Installation

### Build Instructions

```bash
# Clone the repository
git clone https://github.com/objective-audio/AmbiMux.git
cd AmbiMux

# Build
swift build -c release
```

## Requirements

- macOS 26.0 or later
- Xcode 26 or later (Swift 6.2)

## Usage

### Basic Usage

```bash
# Output MOV with audio (B-format 4ch audio file) and video (default output)
ambimux --audio /path/to/audio.wav --video /path/to/video.mov

# Specify custom output path
ambimux --audio /path/to/audio.wav --video /path/to/video.mov --output /path/to/output.mov
```

### Command Line Arguments

- `--audio`, `-a`: Path to audio file (4ch B-format Ambisonics in AmbiX format, or APAC-encoded file)
- `--video`, `-v`: Path to input video
- `--output`, `-o`: Output file path (optional, defaults to same name as video file)

## Technical Specifications

### Input File Requirements

- **Audio File**: 
  - 4-channel B-format Ambisonics audio file (AmbiX format) - will be encoded to APAC
  - APAC-encoded file (any channel count) - will be copied without re-encoding
  - Supported formats: Any audio format readable by AVFoundation (WAV, MP4, etc.)
- **Video File**: Any MOV/MP4 format video file
- **Sample Rate**: 48kHz recommended (other rates supported)

### Output Specifications

- **Container**: MOV
- **Audio**: APAC (Apple Positional Audio Codec) - optimized for Apple Vision Pro spatial audio
- **Channel Layout**: 
  - For non-APAC audio input: HOA ACN SN3D (4ch)
  - For APAC input: Original channel layout and count preserved
- **Bitrate**: 384kbps (for encoded audio)
- **Video**: Copied from input video (audio uses specified audio file instead of existing video tracks)
- **Target Platform**: Apple Vision Pro

## Development

### Running Tests
```bash
swift test
```

### Code Formatting
```bash
./format.sh
```

## References

- [Ambisonics](https://en.wikipedia.org/wiki/Ambisonics)

## License

MIT License

Copyright (c) 2025 Yuki Yasoshima

See [LICENSE](LICENSE) file for details.
