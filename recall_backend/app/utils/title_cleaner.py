"""
Utility for cleaning and normalizing extracted titles.

This module provides functions to clean up overly verbose or poorly formatted
titles extracted from OpenGraph tags and HTML.
"""

import re
from typing import Optional


def clean_social_media_title(title: str, url: str = "") -> str:
    """
    Clean and normalize titles from social media platforms.

    Common issues this fixes:
    - "Username on Instagram: 'Post caption...'" → "Post caption"
    - Very long titles with hashtags → Shortened version
    - Multiple paragraphs → First sentence only
    - Emojis at the start → Keep them if relevant

    Args:
        title: Raw title from metadata
        url: Optional URL for context

    Returns:
        Cleaned, concise title
    """
    if not title or len(title) < 3:
        return title

    original_title = title

    # Remove "X on Instagram:" or "X on Pinterest:" prefixes
    title = re.sub(r'^.+ on (Instagram|Pinterest|TikTok|Twitter|Facebook):\s*["\']?', '', title, flags=re.IGNORECASE)

    # Remove trailing quotes from the prefix removal
    title = re.sub(r'^["\'](.+)["\']$', r'\1', title)

    # If title is very long (>200 chars), try to extract meaningful part
    if len(title) > 200:
        title = _extract_main_content(title)

    # Remove excessive hashtags (keep first few, remove the rest)
    title = _clean_hashtags(title)

    # Truncate to reasonable length (max 150 chars) at sentence boundary
    title = _truncate_at_sentence(title, max_length=150)

    # If cleaning made it too short or empty, return original
    if len(title) < 10:
        return original_title

    return title.strip()


def _extract_main_content(text: str) -> str:
    """
    Extract the main content from a long text block.

    Strategy:
    1. Take text before first newline (often the main message)
    2. If that's too short, take first 2-3 sentences
    3. Remove hashtags section
    """
    # Split by double newline (paragraph break)
    paragraphs = text.split('\n\n')

    # Try first paragraph (usually the main message)
    first_para = paragraphs[0].strip()

    # If first paragraph is substantial, use it
    if len(first_para) > 30:
        return first_para

    # Otherwise, try to get first few sentences before hashtags
    # Split at hashtag section
    before_hashtags = re.split(r'\n#', text)[0]

    return before_hashtags.strip()


def _clean_hashtags(text: str) -> str:
    """
    Remove or limit hashtags in title.

    Strategy:
    - If hashtags are at the end, remove them
    - If hashtags are inline, keep the first 2-3, remove the rest
    """
    # Remove hashtag sections at the end (common in Instagram)
    # Pattern: newline followed by hashtags
    text = re.sub(r'\n+#\w+.*$', '', text, flags=re.DOTALL)

    # If there are inline hashtags, keep first 2, remove the rest
    hashtags = re.findall(r'#\w+', text)
    if len(hashtags) > 3:
        # Find where the excessive hashtags start
        # Keep text before the 3rd hashtag
        parts = re.split(r'(#\w+)', text)
        hashtag_count = 0
        result_parts = []

        for part in parts:
            if part.startswith('#'):
                hashtag_count += 1
                if hashtag_count <= 2:
                    result_parts.append(part)
                else:
                    break  # Stop adding parts after 2nd hashtag
            else:
                result_parts.append(part)

        text = ''.join(result_parts).strip()

    return text


def _truncate_at_sentence(text: str, max_length: int = 150) -> str:
    """
    Truncate text at sentence boundary, not mid-word.

    Args:
        text: Text to truncate
        max_length: Maximum length

    Returns:
        Truncated text ending at sentence boundary
    """
    if len(text) <= max_length:
        return text

    # Try to find sentence boundary before max_length
    truncated = text[:max_length]

    # Look for sentence endings: . ! ?
    last_sentence_end = max(
        truncated.rfind('. '),
        truncated.rfind('! '),
        truncated.rfind('? ')
    )

    if last_sentence_end > max_length * 0.6:  # At least 60% of max_length
        return text[:last_sentence_end + 1].strip()

    # No good sentence boundary, truncate at word boundary
    last_space = truncated.rfind(' ')
    if last_space > max_length * 0.8:  # At least 80% of max_length
        return text[:last_space].strip() + '...'

    # Just truncate with ellipsis
    return truncated.strip() + '...'


def clean_title(title: str, url: str = "", max_length: int = 512) -> str:
    """
    Main entry point for title cleaning.

    Applies appropriate cleaning based on URL source.

    Args:
        title: Raw title to clean
        url: Source URL for context
        max_length: Maximum allowed length (database constraint)

    Returns:
        Cleaned title
    """
    if not title:
        return "Untitled"

    # Detect if it's a social media platform
    social_platforms = ['instagram.com', 'pinterest.com', 'tiktok.com',
                       'twitter.com', 'facebook.com', 'x.com']

    is_social_media = any(platform in url.lower() for platform in social_platforms)

    # Apply social media cleaning if applicable
    if is_social_media:
        title = clean_social_media_title(title, url)

    # Ensure it fits database constraints
    if len(title) > max_length:
        title = _truncate_at_sentence(title, max_length - 3) + '...'

    return title.strip() or "Untitled"
