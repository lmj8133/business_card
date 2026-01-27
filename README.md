# Business Card Parser

Parse business card images and extract structured contact information using OCR and LLM.

## Features

- **OCR**: PaddleOCR for text extraction from images
- **LLM Extraction**: Ollama for structured data parsing
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
