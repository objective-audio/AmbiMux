# AmbiMux

`AmbiMux` is a CLI tool that embeds or replaces spatial audio in MOV videos for Apple Vision Pro. It supports APAC and LPCM (HOA Ambisonics) audio from external files, as well as audio already embedded in the video file.

## Features

- **Apple Vision Pro Support**: Optimized for spatial audio playback on Apple Vision Pro
- **Auto-detection**: Automatically detects whether the input audio file is APAC or LPCM — no need to specify the format manually
- **Embedded Audio Support**: Can process HOA LPCM audio already embedded in the input MOV without requiring a separate audio file
- **Flexible Output Format**: LPCM input defaults to LPCM output; use `--audio-output apac` to encode to APAC instead
- **APAC Passthrough**: APAC input is always passed through without re-encoding
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
# Mux an external audio file (APAC or LPCM auto-detected) with a video
ambimux --audio /path/to/audio.mp4 --video /path/to/video.mov

# Encode LPCM input to APAC in the output MOV
ambimux --audio /path/to/audio.wav --video /path/to/video.mov --audio-output apac

# Use audio already embedded in the video file (no --audio needed)
ambimux --video /path/to/video.mov

# Specify a custom output path
ambimux --audio /path/to/audio.wav --video /path/to/video.mov --output /path/to/output.mov
```

### Command Line Arguments

- `--audio`, `-a`: Path to spatial audio file (APAC or LPCM, auto-detected). Omit to use audio embedded in the video file.
- `--audio-output`: Output audio format when input is LPCM: `lpcm` (default) or `apac`
- `--video`, `-v`: Path to input video file
- `--output`, `-o`: Output file path (optional, defaults to the same name as the video file with `.mov` extension)

## Technical Specifications

### Input File Requirements

- **External Audio File (`--audio`)**:
  - HOA LPCM (4/9/16-channel B-format Ambisonics, AmbiX format) — supported by any format readable by AVFoundation (WAV, AIFF, CAF, etc.)
  - APAC-encoded file (any channel count, e.g. MP4) — passed through without re-encoding
  - Format is auto-detected from the file's audio stream
- **Embedded Audio (no `--audio`)**:
  - HOA LPCM embedded in the input MOV (4/9/16-channel)
- **Video File**: Any MOV/MP4 format video file
- **Sample Rate**: Up to 48kHz (downsampled to 48kHz if higher; lower rates preserved as-is)

### Output Specifications

- **Container**: MOV
- **Audio**:
  - APAC input → APAC passthrough (channel layout and count preserved)
  - LPCM input → LPCM by default; APAC (384kbps) when `--audio-output apac` is specified
- **Channel Layout**:
  - For LPCM input: HOA ACN SN3D (normalized via intermediate CAF)
  - For APAC input: Original channel layout and count preserved
- **Video**: Copied from input video
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
