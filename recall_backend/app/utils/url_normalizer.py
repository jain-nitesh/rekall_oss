"""
URL normalization utility for deduplication.

Normalizes URLs to a canonical form so that equivalent URLs
(differing only in tracking params, trailing slashes, etc.)
are recognized as duplicates.
"""
from urllib.parse import urlparse, urlunparse, parse_qs, urlencode


# Tracking parameters to strip during normalization
TRACKING_PARAMS = {
    'utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term',
    'fbclid', 'gclid', 'gclsrc', 'dclid', 'msclkid',
    'ref', 'ref_src', 'ref_url',
    '_ga', '_gl', 'mc_cid', 'mc_eid',
    'yclid', 'twclid', 'ttclid',
}


def normalize_url(url: str) -> str:
    """
    Normalize a URL for deduplication purposes.

    Transformations:
    1. Lowercase scheme and hostname
    2. Strip www. prefix
    3. Remove trailing slashes from path
    4. Remove common tracking/analytics query parameters
    5. Sort remaining query parameters alphabetically
    6. Remove fragment (hash) unless it looks like a SPA route

    Args:
        url: The URL to normalize

    Returns:
        Normalized URL string
    """
    try:
        parsed = urlparse(url)
    except Exception:
        return url

    # Lowercase scheme and hostname
    scheme = parsed.scheme.lower()
    hostname = parsed.hostname or ''
    hostname = hostname.lower()

    # Strip www. prefix
    if hostname.startswith('www.'):
        hostname = hostname[4:]

    # Reconstruct netloc with port if non-standard
    port = parsed.port
    if port and not (scheme == 'http' and port == 80) and not (scheme == 'https' and port == 443):
        netloc = f"{hostname}:{port}"
    else:
        netloc = hostname

    # Remove trailing slashes from path (but keep "/" for root)
    path = parsed.path.rstrip('/') or '/'

    # Filter out tracking parameters and sort the rest
    query_params = parse_qs(parsed.query, keep_blank_values=True)
    filtered_params = {
        k: v for k, v in query_params.items()
        if k.lower() not in TRACKING_PARAMS
    }
    # Sort params and flatten single-value lists
    sorted_query = urlencode(
        sorted(filtered_params.items()),
        doseq=True
    )

    # Remove fragment unless it looks like a SPA route (starts with / or !)
    fragment = ''
    if parsed.fragment and (parsed.fragment.startswith('/') or parsed.fragment.startswith('!')):
        fragment = parsed.fragment

    return urlunparse((scheme, netloc, path, '', sorted_query, fragment))
