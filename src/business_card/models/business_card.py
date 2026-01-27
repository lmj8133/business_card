"""Pydantic models for business card data."""

from typing import Literal
from pydantic import BaseModel, Field


class Name(BaseModel):
    """Person's name information."""

    full_name: str = Field(description="Full name as displayed on the card")
    first_name: str | None = Field(default=None, description="First/given name")
    last_name: str | None = Field(default=None, description="Last/family name")


class Company(BaseModel):
    """Company information."""

    name: str | None = Field(default=None, description="Company name")
    department: str | None = Field(default=None, description="Department or division")


class Phone(BaseModel):
    """Phone number with type classification."""

    number: str = Field(description="Phone number")
    type: Literal["office", "mobile", "fax", "other"] = Field(
        default="other", description="Type of phone number"
    )


class Contact(BaseModel):
    """Contact information."""

    phones: list[Phone] = Field(default_factory=list, description="Phone numbers")
    emails: list[str] = Field(default_factory=list, description="Email addresses")
    websites: list[str] = Field(default_factory=list, description="Website URLs")


class Address(BaseModel):
    """Address information."""

    full_address: str | None = Field(
        default=None, description="Complete address as displayed"
    )
    city: str | None = Field(default=None, description="City name")
    state: str | None = Field(default=None, description="State or province")
    postal_code: str | None = Field(default=None, description="ZIP or postal code")
    country: str | None = Field(default=None, description="Country name")


class Metadata(BaseModel):
    """Processing metadata."""

    ocr_backend: str = Field(description="OCR backend used")
    extractor_backend: str = Field(description="LLM extractor used")
    processing_time_ms: float = Field(description="Total processing time in ms")


class BusinessCard(BaseModel):
    """Complete business card information."""

    name: Name = Field(description="Person's name")
    company: Company = Field(
        default_factory=Company, description="Company information"
    )
    title: str | None = Field(default=None, description="Job title or position")
    contact: Contact = Field(
        default_factory=Contact, description="Contact information"
    )
    address: Address = Field(
        default_factory=Address, description="Address information"
    )
    raw_text: str = Field(description="Raw OCR text for reference")
    confidence: float = Field(
        default=0.0, ge=0.0, le=1.0, description="Extraction confidence score"
    )
    metadata: Metadata | None = Field(default=None, description="Processing metadata")
