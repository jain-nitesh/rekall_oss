"""
URL validation utilities for security.

Prevents SSRF (Server-Side Request Forgery) attacks by blocking:
- Internal/private IP addresses
- Localhost/loopback addresses
- Cloud metadata endpoints
- Reserved IP ranges
"""
import re
import ipaddress
import socket
from urllib.parse import urlparse
from typing import Tuple
import logging

logger = logging.getLogger(__name__)


# Blocked hostname patterns (case-insensitive)
BLOCKED_PATTERNS = [
    r'localhost',
    r'127\.\d+\.\d+\.\d+',
    r'0\.0\.0\.0',
    r'::1',  # IPv6 localhost
    r'0:0:0:0:0:0:0:1',  # IPv6 localhost full form
    # Cloud metadata endpoints
    r'169\.254\.169\.254',  # AWS EC2 metadata
    r'metadata\.google\.internal',  # GCP metadata
    r'169\.254\.169\.253',  # Azure metadata (link-local)
    r'100\.100\.100\.200',  # Alibaba Cloud metadata
]

# Private IP address ranges (RFC 1918, RFC 4193, etc.)
PRIVATE_IP_RANGES = [
    '10.0.0.0/8',           # Private network
    '172.16.0.0/12',        # Private network
    '192.168.0.0/16',       # Private network
    '169.254.0.0/16',       # Link-local (APIPA)
    '127.0.0.0/8',          # Loopback
    '::1/128',              # IPv6 loopback
    'fe80::/10',            # IPv6 link-local
    'fc00::/7',             # IPv6 unique local addresses
    '100.64.0.0/10',        # Carrier-grade NAT
]


def is_private_ip(ip_str: str) -> bool:
    """
    Check if an IP address is private/reserved.

    Args:
        ip_str: IP address string (IPv4 or IPv6)

    Returns:
        True if IP is private/reserved, False otherwise
    """
    try:
        ip = ipaddress.ip_address(ip_str)

        # Check against private IP ranges
        for range_str in PRIVATE_IP_RANGES:
            if ip in ipaddress.ip_network(range_str):
                return True

        # Additional checks for special IPs
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved:
            return True

        return False

    except ValueError:
        # Invalid IP address
        return False


def is_safe_url(url: str) -> Tuple[bool, str]:
    """
    Validate that a URL is safe to fetch (not targeting internal resources).

    Security checks:
    1. URL must use HTTP or HTTPS protocol
    2. Hostname must not match blocked patterns
    3. Hostname must not resolve to private IP addresses
    4. Prevents DNS rebinding by checking resolved IPs

    Args:
        url: The URL to validate

    Returns:
        Tuple of (is_safe: bool, error_message: str)
        - If safe: (True, "")
        - If unsafe: (False, "reason why URL is blocked")

    Examples:
        >>> is_safe_url("https://example.com")
        (True, "")

        >>> is_safe_url("http://localhost:8000")
        (False, "Blocked hostname pattern: localhost")

        >>> is_safe_url("http://192.168.1.1")
        (False, "Private IP address not allowed: 192.168.1.1")
    """
    try:
        # Parse URL
        parsed = urlparse(url)

        # Check protocol (must be http or https)
        if parsed.scheme not in ['http', 'https']:
            return False, f"Invalid protocol: {parsed.scheme}. Only HTTP and HTTPS are allowed."

        hostname = parsed.hostname
        if not hostname:
            return False, "Invalid URL: no hostname"

        # Check 1: Blocked hostname patterns
        for pattern in BLOCKED_PATTERNS:
            if re.search(pattern, hostname, re.IGNORECASE):
                logger.warning(f"SSRF attempt blocked: URL matches blocked pattern '{pattern}': {url}")
                return False, f"Blocked hostname pattern: {hostname}"

        # Check 2: If hostname is an IP address, check if it's private
        try:
            ip = ipaddress.ip_address(hostname)
            if is_private_ip(str(ip)):
                logger.warning(f"SSRF attempt blocked: Private IP address: {url}")
                return False, f"Private IP address not allowed: {ip}"
        except ValueError:
            # Not an IP address, it's a domain name - continue to DNS check
            pass

        # Check 3: Resolve hostname and check if it resolves to private IPs
        # This prevents DNS rebinding attacks
        try:
            # Resolve hostname to IP addresses
            addr_info = socket.getaddrinfo(hostname, None, socket.AF_UNSPEC, socket.SOCK_STREAM)

            for addr in addr_info:
                resolved_ip = addr[4][0]

                # Check if resolved IP is private
                if is_private_ip(resolved_ip):
                    logger.warning(
                        f"SSRF attempt blocked: Domain '{hostname}' resolves to private IP: {resolved_ip} (URL: {url})"
                    )
                    return False, f"Domain resolves to private IP: {resolved_ip}"

        except socket.gaierror as e:
            # DNS resolution failed - could be invalid domain
            logger.warning(f"DNS resolution failed for {hostname}: {e}")
            return False, f"DNS resolution failed: {hostname}"
        except Exception as e:
            logger.error(f"Error during DNS resolution for {hostname}: {e}")
            return False, f"Error validating URL: {str(e)}"

        # All checks passed
        return True, ""

    except Exception as e:
        logger.error(f"Error parsing URL {url}: {e}")
        return False, f"Invalid URL: {str(e)}"


def validate_url_or_raise(url: str) -> None:
    """
    Validate URL and raise exception if unsafe.

    This is a convenience wrapper around is_safe_url() for use in
    FastAPI endpoints where you want to raise an HTTPException.

    Args:
        url: The URL to validate

    Raises:
        ValueError: If URL is unsafe, with detailed error message

    Example:
        try:
            validate_url_or_raise(user_provided_url)
            # Proceed to fetch URL
        except ValueError as e:
            raise HTTPException(400, detail=str(e))
    """
    is_safe, error_msg = is_safe_url(url)
    if not is_safe:
        raise ValueError(f"URL not allowed: {error_msg}")
