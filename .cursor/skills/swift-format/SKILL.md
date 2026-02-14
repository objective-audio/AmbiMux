---
name: swift-format
description: Format Swift code using swift-format tool. Use when the user asks to format code, clean up code style, or run swift format.
---

# Swift Code Formatting

Format Swift code in this project using Apple's `swift-format` tool to ensure consistent code style.

## Quick Start

To format all Swift files in the project:

```bash
swift format --in-place --recursive Sources/
```

## Common Commands

### Format entire Sources directory
```bash
swift format --in-place --recursive Sources/
```

### Format specific file
```bash
swift format --in-place path/to/File.swift
```

### Check formatting without modifying (dry run)
```bash
swift format --recursive Sources/
```

### Check version
```bash
swift format --version
```

## Workflow

1. **Check if swift-format is available**
   ```bash
   swift format --version
   ```

2. **Format the code**
   ```bash
   swift format --in-place --recursive Sources/
   ```

3. **Review changes**
   ```bash
   git diff
   ```

4. **Run tests to ensure formatting didn't break anything**
   ```bash
   swift test
   ```

5. **Commit the formatting changes**
   ```bash
   git add -A
   git commit -m "Format code with swift format"
   ```

## What swift-format fixes

- Removes trailing whitespace
- Ensures consistent indentation
- Breaks long lines appropriately (default 80 chars)
- Fixes spacing around operators and brackets
- Ensures consistent brace placement
- Normalizes blank lines

## Notes

- Always run tests after formatting to ensure no unintended changes
- Format before committing to keep diffs clean
- The `--in-place` flag modifies files directly
- Without `--in-place`, output goes to stdout
