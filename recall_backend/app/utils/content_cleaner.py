"""
Utility functions for cleaning and validating content data before database insertion.

Ensures all extracted data fits within database field constraints and contains only useful information.
"""
from typing import Optional, List
from urllib.parse import urlparse


def clean_source_app(source_app: Optional[str], url: Optional[str] = None) -> str:
    """
    Clean and normalize source_app to fit within 50 character limit.
    
    Priority:
    1. Extract domain name from URL if source_app is too long or looks like an address
    2. Normalize common app names
    3. Truncate to 50 characters max
    4. Default to 'other' if invalid
    
    Args:
        source_app: Raw source app value (may be long address or business name)
        url: URL to extract domain from if source_app is invalid
        
    Returns:
        Clean source app identifier (max 50 chars)
    """
    if not source_app:
        return _extract_domain_from_url(url) if url else 'other'
    
    # If it's too long or looks like an address (contains numbers, commas, etc.), extract domain
    if len(source_app) > 50 or _looks_like_address(source_app):
        if url:
            return _extract_domain_from_url(url)
        # If no URL, try to extract a clean identifier
        return _extract_clean_identifier(source_app)
    
    # Normalize common app names
    normalized = _normalize_app_name(source_app)
    
    # Truncate to 50 characters
    return normalized[:50] if len(normalized) > 50 else normalized


def clean_category(category: Optional[str]) -> str:
    """
    Clean and normalize category to fit within 50 character limit.
    
    Args:
        category: Raw category value
        
    Returns:
        Clean category identifier (max 50 chars, defaults to 'other')
    """
    if not category:
        return 'other'
    
    # Normalize to lowercase and strip whitespace
    category = category.lower().strip()
    
    # Map common variations
    category_mappings = {
        'tech': 'technology',
        'productivity tools': 'productivity',
        'productivity-tools': 'productivity',
        'entertainment & media': 'entertainment',
        'science & technology': 'science',
    }
    
    category = category_mappings.get(category, category)
    
    # Truncate to 50 characters
    if len(category) > 50:
        category = category[:50]
    
    # Validate against known categories
    valid_categories = [
        'technology', 'design', 'business', 'science', 
        'productivity', 'education', 'entertainment', 'other'
    ]
    
    # If it matches a valid category, return it; otherwise return 'other'
    if category in valid_categories:
        return category
    
    # Check if it contains valid category keywords
    for valid_cat in valid_categories:
        if valid_cat in category:
            return valid_cat
    
    return 'other'


def clean_title(title: Optional[str]) -> str:
    """
    Clean and truncate title to fit within 512 character limit.
    
    Args:
        title: Raw title value
        
    Returns:
        Clean title (max 512 chars, defaults to 'Untitled')
    """
    if not title:
        return 'Untitled'
    
    # Strip whitespace
    title = title.strip()
    
    # Truncate to 512 characters
    if len(title) > 512:
        title = title[:512].rstrip()
    
    return title if title else 'Untitled'


def clean_thumbnail_url(thumbnail_url: Optional[str]) -> Optional[str]:
    """
    Clean and truncate thumbnail URL to fit within 512 character limit.
    
    Args:
        thumbnail_url: Raw thumbnail URL
        
    Returns:
        Clean thumbnail URL (max 512 chars) or None if invalid
    """
    if not thumbnail_url:
        return None
    
    # Strip whitespace
    thumbnail_url = thumbnail_url.strip()
    
    # Validate it looks like a URL
    if not (thumbnail_url.startswith('http://') or thumbnail_url.startswith('https://')):
        return None
    
    # Truncate to 512 characters
    if len(thumbnail_url) > 512:
        thumbnail_url = thumbnail_url[:512]
    
    return thumbnail_url


def clean_tags(tags: Optional[List[str]], max_tags: int = 10, max_tag_length: int = 50) -> List[str]:
    """
    Clean and normalize tags list.
    
    Args:
        tags: Raw tags list
        max_tags: Maximum number of tags to return
        max_tag_length: Maximum length per tag
        
    Returns:
        Clean tags list
    """
    if not tags:
        return []
    
    cleaned_tags = []
    seen = set()
    
    for tag in tags:
        if not tag:
            continue
        
        # Clean tag: lowercase, strip, remove special chars
        tag_clean = str(tag).strip().lower()
        
        # Remove special characters (keep alphanumeric, spaces, hyphens)
        tag_clean = ''.join(c for c in tag_clean if c.isalnum() or c in (' ', '-', '_'))
        tag_clean = ' '.join(tag_clean.split())  # Normalize whitespace
        
        # Skip if too short or too long
        if len(tag_clean) < 2 or len(tag_clean) > max_tag_length:
            continue
        
        # Skip duplicates
        if tag_clean in seen:
            continue
        
        seen.add(tag_clean)
        cleaned_tags.append(tag_clean)
        
        # Stop at max_tags
        if len(cleaned_tags) >= max_tags:
            break
    
    return cleaned_tags


def _extract_domain_from_url(url: Optional[str]) -> str:
    """Extract clean domain name from URL."""
    if not url:
        return 'other'
    
    try:
        parsed = urlparse(url)
        domain = parsed.netloc.lower()
        
        # Remove port if present
        if ':' in domain:
            domain = domain.split(':')[0]
        
        # Remove www. prefix
        domain = domain.replace('www.', '')
        
        # Extract main domain name (e.g., "example.com" -> "example")
        domain_parts = domain.split('.')
        if len(domain_parts) >= 2:
            # Get the main domain name (second-to-last part)
            main_domain = domain_parts[-2] if len(domain_parts) > 2 else domain_parts[0]
            return main_domain[:50]  # Ensure max 50 chars
        
        return domain[:50] if len(domain) <= 50 else 'other'
    except Exception:
        return 'other'


def _looks_like_address(text: str) -> bool:
    """Check if text looks like an address (contains numbers, commas, etc.)."""
    # If it contains numbers and commas, or is very long, it's likely an address
    has_numbers = any(c.isdigit() for c in text)
    has_commas = ',' in text
    has_long_words = any(len(word) > 20 for word in text.split())
    
    return (has_numbers and has_commas) or has_long_words or len(text) > 100


def _extract_clean_identifier(text: str) -> str:
    """Extract a clean identifier from a long text (like business name)."""
    # Take first word or first few words
    words = text.split()
    if words:
        # Take first word, lowercase, remove special chars
        identifier = words[0].lower()
        identifier = ''.join(c for c in identifier if c.isalnum())
        return identifier[:50] if identifier else 'other'
    return 'other'


def _normalize_app_name(app_name: str) -> str:
    """Normalize common app names to standard identifiers."""
    app_name_lower = app_name.lower().strip()
    
    # Map common variations
    app_mappings = {
        'linkedin': 'linkedin',
        'reddit': 'reddit',
        'twitter': 'twitter',
        'x': 'twitter',
        'medium': 'medium',
        'youtube': 'youtube',
        'github': 'github',
        'product hunt': 'productHunt',
        'producthunt': 'productHunt',
        'hacker news': 'hackerNews',
        'hackernews': 'hackerNews',
        'd mart': 'other',  # Business name, not a source app
        'dmart': 'other',
    }
    
    # Check direct match
    if app_name_lower in app_mappings:
        return app_mappings[app_name_lower]
    
    # Check if it contains any mapped name
    for key, value in app_mappings.items():
        if key in app_name_lower:
            return value
    
    # If it's a single word and short, use it as-is
    if len(app_name_lower) <= 50 and ' ' not in app_name_lower:
        return app_name_lower
    
    # Otherwise, extract first word
    first_word = app_name_lower.split()[0] if app_name_lower.split() else 'other'
    return first_word[:50]

