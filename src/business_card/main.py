"""CLI entry point for business card parser."""

from pathlib import Path
from typing import Annotated

import typer
from rich import print as rprint
from rich.console import Console
from rich.panel import Panel

from business_card.ocr.paddle_ocr import PaddleOCRBackend
from business_card.extractor.ollama import OllamaExtractor
from business_card.parser import BusinessCardParser

app = typer.Typer(
    name="bcparser",
    help="Parse business card images and extract contact information.",
    add_completion=False,
)
console = Console()


@app.command()
def parse(
    image_path: Annotated[
        Path,
        typer.Argument(
            help="Path to the business card image",
            exists=True,
            readable=True,
        ),
    ],
    extractor: Annotated[
        str,
        typer.Option(
            "--extractor",
            "-e",
            help="Extractor backend: ollama:<model> or claude:<model>",
        ),
    ] = "ollama:llama3.2",
    output_json: Annotated[
        bool,
        typer.Option(
            "--json",
            "-j",
            help="Output raw JSON instead of formatted output",
        ),
    ] = False,
    ocr_only: Annotated[
        bool,
        typer.Option(
            "--ocr-only",
            help="Only run OCR, skip LLM extraction",
        ),
    ] = False,
    lang: Annotated[
        str,
        typer.Option(
            "--lang",
            "-l",
            help="OCR language (default: en)",
        ),
    ] = "en",
):
    """Parse a business card image and extract contact information."""
    try:
        # Initialize OCR backend
        ocr = PaddleOCRBackend(lang=lang)

        if ocr_only:
            # OCR only mode
            text = ocr.extract(image_path).text
            if output_json:
                import json

                print(json.dumps({"raw_text": text}, indent=2))
            else:
                rprint(Panel(text, title="OCR Result", border_style="blue"))
            return

        # Initialize extractor
        extractor_instance = _create_extractor(extractor)

        # Parse the image
        parser = BusinessCardParser(ocr=ocr, extractor=extractor_instance)
        card = parser.parse(image_path)

        if output_json:
            print(card.model_dump_json(indent=2))
        else:
            _print_formatted(card)

    except FileNotFoundError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(1)
    except ValueError as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(1)


def _create_extractor(extractor_spec: str) -> OllamaExtractor:
    """Create extractor instance from spec string."""
    if ":" in extractor_spec:
        backend, model = extractor_spec.split(":", 1)
    else:
        backend = extractor_spec
        model = None

    if backend == "ollama":
        return OllamaExtractor(model=model or "llama3.2")
    else:
        raise ValueError(f"Unknown extractor backend: {backend}. Use 'ollama:<model>'")


def _print_formatted(card):
    """Print formatted business card info."""
    from rich.table import Table

    console.print()

    # Name
    console.print(f"[bold cyan]{card.name}[/bold cyan]")

    # Title
    if card.title:
        console.print(f"[dim]{card.title}[/dim]")

    # Company and department
    if card.company:
        company_str = card.company
        if card.department:
            company_str += f" - {card.department}"
        console.print(f"[green]{company_str}[/green]")
    elif card.department:
        console.print(f"[green]{card.department}[/green]")

    console.print()

    # Contact info table
    if card.email:
        table = Table(show_header=False, box=None)
        table.add_column("Type", style="dim")
        table.add_column("Value")
        table.add_row("Email", card.email)
        console.print(table)

    # Metadata
    if card.metadata:
        console.print()
        console.print(
            f"[dim]Processed in {card.metadata.processing_time_ms:.0f}ms "
            f"(OCR: {card.metadata.ocr_backend}, "
            f"Extractor: {card.metadata.extractor_backend})[/dim]"
        )

    console.print()


@app.command()
def version():
    """Show version information."""
    from business_card import __version__

    console.print(f"bcparser version {__version__}")


if __name__ == "__main__":
    app()
