# AmbiMux

`AmbiMux` is a CLI tool that embeds or replaces 1st Order Ambisonics (B-format, 4ch) in MOV videos. The 4-channel B-format must be in AmbiX format.

## Features

- **B-format Ambisonics Encoding**: Encodes 4-channel B-format Ambisonics in APAC format
- **MOV Output**: Output in MOV container format
- **Video Preservation**: Preserves original video tracks
- **Real-time Processing**: Efficient processing using AVAssetWriter
- **Detailed Verification**: Displays detailed information about output files

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
# Output MOV with audio (B-format 4ch WAV) and video (default output)
ambimux --audio /path/to/audio.wav --video /path/to/video.mov

# Specify custom output path
ambimux --audio /path/to/audio.wav --video /path/to/video.mov --output /path/to/output.mov
```

### Command Line Arguments

- `--audio`, `-a`: Path to 4ch B-format Ambisonics WAV (AmbiX format)
- `--video`, `-v`: Path to input video
- `--output`, `-o`: Output file path (optional, defaults to same name as video file)

## Technical Specifications

### Input File Requirements

- **Audio File**: 4-channel B-format Ambisonics WAV file (AmbiX format)
- **Video File**: Any MOV/MP4 format video file
- **Sample Rate**: 48kHz recommended (other rates supported)

### Output Specifications

- **Container**: MOV
- **Audio**: APAC (Apple Positional Audio Codec)
- **Channel Layout**: HOA ACN SN3D (4ch)
- **Bitrate**: 384kbps
- **Video**: Copied from input video (audio uses specified WAV instead of existing video tracks)

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
