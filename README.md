# Business Card Parser

Parse business card images and extract structured contact information using OCR and LLM.

## Features

- **OCR**: PaddleOCR for text extraction from images
- **Auto ROI Detection**: Automatic card region detection and cropping to reduce memory usage
- **LLM Extraction**: Ollama for structured data parsing
- **Batch Processing**: Process multiple images with JSON/CSV output
- **Structured Output**: Pydantic models with full type safety
- **CLI**: Simple command-line interface

## Installation

Requires Python 3.10+ and [uv](https://docs.astral.sh/uv/).

```bash
# Clone and install
git clone <repo-url>
cd business-card
uv sync

# Install dev dependencies (optional)
uv sync --extra dev
```

### Prerequisites

- **Ollama**: Install from [ollama.ai](https://ollama.ai) and pull a model:
  ```bash
  ollama pull llama3.2
  ```

## Usage

### OCR Only

Extract raw text from a business card image:

```bash
uv run bcparser parse card.jpg --ocr-only
```

### Full Extraction

Parse image and extract structured contact info:

```bash
uv run bcparser parse card.jpg --extractor ollama:llama3.2
```

### JSON Output

```bash
uv run bcparser parse card.jpg --json
```

### CLI Options

```
bcparser parse [OPTIONS] IMAGE_PATH

Arguments:
  IMAGE_PATH    Path to the business card image

Options:
  -e, --extractor TEXT   Extractor backend: ollama:<model> [default: ollama:llama3.2]
  -l, --lang TEXT        OCR language [default: en]
  -j, --json             Output raw JSON
  --ocr-only             Only run OCR, skip LLM extraction
  --help                 Show help message
```

### Batch Processing

Process multiple images at once:

```bash
# Process a directory of images
uv run bcparser batch ./cards/ -o results.json

# Process specific files
uv run bcparser batch card1.jpg card2.jpg -o results.json

# Output as CSV
uv run bcparser batch ./cards/ -o results.csv --format csv
```

## Auto ROI Detection

The parser automatically detects and crops the business card region from photos. This significantly reduces memory usage when processing high-resolution images (e.g., 4032x3024 phone photos).

**Detection strategies** (tried in order):
1. White region detection - for white cards on darker backgrounds
2. Adaptive thresholding - handles varying lighting
3. Canny edge detection - standard edge-based detection
4. Morphological gradient - finds object boundaries

**Fallback behavior**: If card detection fails, the image is resized to max 2000px to prevent memory issues.

To disable auto-crop:

```python
from business_card.ocr import PaddleOCRBackend

ocr = PaddleOCRBackend(lang="en", auto_crop=False)
```

## Output Example

```json
{
  "company": "Tech Corp",
  "name": "John Doe",
  "department": "Engineering",
  "title": "Software Engineer",
  "email": "john@techcorp.com",
  "confidence": 0.95
}
```

## iOS App (BusinessCardScanner)

### Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen):
   ```bash
   brew install xcodegen
   ```

2. Create your `Secrets.xcconfig` from the template:
   ```bash
   cd BusinessCardScanner
   cp Secrets.xcconfig.example Secrets.xcconfig
   ```

3. Edit `Secrets.xcconfig` and fill in your values:
   ```
   OLLAMA_BASE_URL = http:/$()/your-server:11434
   DEVELOPMENT_TEAM = YOUR_APPLE_TEAM_ID
   PRODUCT_BUNDLE_IDENTIFIER = com.yourcompany.BusinessCardScanner
   ```

4. Generate the Xcode project and open it:
   ```bash
   xcodegen generate
   open BusinessCardScanner.xcodeproj
   ```

> **Note:** `Secrets.xcconfig` is gitignored. Each developer must create their own copy from the example.

## Development

### Run Tests

```bash
uv run pytest -q
```

### Lint

```bash
uvx ruff check src/ tests/
```

## License

MIT
