"""
Basic URL-based categorization service.

For beginners:
- This service detects source app and category from URL and text
- Phase 2: Uses simple pattern matching and keyword detection
- Phase 3: Will be replaced by AI-powered categorization
- Provides reasonable defaults without needing AI
"""
from typing import List, Optional, Dict, Any
from urllib.parse import urlparse


class BasicCategorizer:
    """
    Categorizes content based on URL patterns and keywords.

    Limitations:
    - Simple pattern matching (not as accurate as AI)
    - May misclassify some content
    - Good enough for Phase 2 testing

    Will be upgraded to AI categorization in Phase 3.
    """

    # Map of domain patterns to source app identifiers
    # These match the Flutter SourceApp enum values
    # Priority order: specific subdomains first, then main domains
    SOURCE_PATTERNS = {
        # Specific subdomains (higher priority)
        'news.ycombinator.com': 'hackerNews',
        'www.linkedin.com': 'linkedin',
        'www.reddit.com': 'reddit',
        'www.twitter.com': 'twitter',
        'www.x.com': 'twitter',
        'www.medium.com': 'medium',
        'www.youtube.com': 'youtube',
        'www.github.com': 'github',
        'www.producthunt.com': 'productHunt',
        'www.instagram.com': 'instagram',
        'www.facebook.com': 'facebook',
        'www.tiktok.com': 'tiktok',
        'www.pinterest.com': 'pinterest',
        'www.quora.com': 'quora',
        'stackoverflow.com': 'stackOverflow',
        'www.stackoverflow.com': 'stackOverflow',
        'dev.to': 'devto',
        'www.dev.to': 'devto',
        'substack.com': 'substack',
        'www.substack.com': 'substack',
        'www.amazon.com': 'amazon',
        'amazon.com': 'amazon',
        'www.amazon.in': 'amazon',
        'amazon.in': 'amazon',
        'www.flipkart.com': 'flipkart',
        'flipkart.com': 'flipkart',
        'www.vimeo.com': 'vimeo',
        'vimeo.com': 'vimeo',
        'www.twitch.tv': 'twitch',
        'twitch.tv': 'twitch',
        'discord.com': 'discord',
        'www.discord.com': 'discord',
        't.me': 'telegram',
        'telegram.org': 'telegram',
        'www.notion.so': 'notion',
        'notion.so': 'notion',
        'www.hashnode.com': 'hashnode',
        'hashnode.com': 'hashnode',
        # Main domains (lower priority)
        'linkedin.com': 'linkedin',
        'reddit.com': 'reddit',
        'twitter.com': 'twitter',
        'x.com': 'twitter',  # Twitter's new domain
        'medium.com': 'medium',
        'youtube.com': 'youtube',
        'youtu.be': 'youtube',  # YouTube short links
        'github.com': 'github',
        'producthunt.com': 'productHunt',
        'instagram.com': 'instagram',
        'facebook.com': 'facebook',
        'tiktok.com': 'tiktok',
        'pinterest.com': 'pinterest',
        'quora.com': 'quora',
    }
    
    # News site patterns (checked after specific patterns)
    NEWS_DOMAINS = {
        'cnn.com', 'bbc.com', 'bbc.co.uk', 'theverge.com', 'techcrunch.com',
        'reuters.com', 'bloomberg.com', 'nytimes.com', 'washingtonpost.com',
        'theguardian.com', 'wsj.com', 'ft.com', 'economist.com'
    }

    # Keywords for category detection
    # When these words appear in URL/title/description, suggest category
    CATEGORY_KEYWORDS = {
        'technology': [
            'tech', 'code', 'programming', 'software', 'developer', 'api',
            'github', 'python', 'javascript', 'java', 'react', 'flutter',
            'computer', 'data', 'algorithm', 'tutorial', 'framework'
        ],
        'design': [
            'design', 'ui', 'ux', 'figma', 'sketch', 'creative',
            'typography', 'color', 'layout', 'interface', 'graphic'
        ],
        'business': [
            'business', 'startup', 'entrepreneur', 'marketing', 'sales',
            'finance', 'investment', 'strategy', 'management', 'revenue'
        ],
        'science': [
            'science', 'research', 'study', 'academic', 'paper',
            'biology', 'physics', 'chemistry', 'nature', 'experiment'
        ],
        'productivity': [
            'productivity', 'tools', 'workflow', 'efficiency', 'organize',
            'planning', 'focus', 'tips', 'habits', 'time management'
        ],
        'education': [
            'learn', 'tutorial', 'course', 'education', 'teaching',
            'training', 'lessons', 'guide', 'howto', 'academy'
        ],
        'entertainment': [
            'entertainment', 'gaming', 'game', 'movie', 'music', 'art',
            'video', 'fun', 'comedy', 'meme', 'stream'
        ],
    }

    def detect_source_app(self, url: str) -> str:
        """
        Detect source app from URL using proper domain parsing.

        Uses urllib.parse to extract and normalize the domain, then matches
        against known patterns. More accurate than substring matching.

        Args:
            url: The URL to analyze

        Returns:
            Source app identifier (e.g., 'linkedin', 'youtube', 'other')

        Examples:
            "https://www.youtube.com/watch?v=..." → 'youtube'
            "https://news.ycombinator.com/item?id=..." → 'hackerNews'
            "https://example.com/article" → 'other'
        """
        try:
            # Parse URL to extract domain
            parsed = urlparse(url)
            netloc = parsed.netloc.lower()
            
            # Remove port if present (e.g., "example.com:8080" → "example.com")
            if ':' in netloc:
                netloc = netloc.split(':')[0]
            
            # Remove www. prefix for matching (but check with it first for priority)
            domain_with_www = netloc
            domain_without_www = netloc.replace('www.', '', 1) if netloc.startswith('www.') else netloc
            
            # Check specific patterns first (priority order)
            # Check with www first, then without
            for domain_pattern, source in self.SOURCE_PATTERNS.items():
                if domain_pattern == domain_with_www or domain_pattern == domain_without_www:
                    return source
                # Also check if pattern is contained in the domain (for subdomains)
                if domain_pattern in netloc:
                    return source
            
            # Check news domains
            base_domain = domain_without_www.split('.')[-2:] if '.' in domain_without_www else [domain_without_www]
            base_domain_str = '.'.join(base_domain)
            if base_domain_str in self.NEWS_DOMAINS:
                return 'news'
            
            # Check for generic news patterns in domain
            if 'news' in netloc or any(news_domain in netloc for news_domain in ['cnn', 'bbc', 'nyt', 'reuters', 'bloomberg']):
                return 'news'
            
            # Use domain as source app identifier (flexible, no hardcoding needed)
            # Extract main domain name (e.g., "myntra.com" -> "myntra", "flipkart.com" -> "flipkart")
            domain_parts = domain_without_www.split('.')
            if len(domain_parts) >= 2:
                # Get the main domain name (second-to-last part, e.g., "myntra" from "www.myntra.com")
                main_domain = domain_parts[-2] if len(domain_parts) > 2 else domain_parts[0]
                return main_domain.lower()
            else:
                return domain_without_www.lower()
            
        except Exception:
            # Fallback to simple substring matching if URL parsing fails
            url_lower = url.lower()
            for domain, source in self.SOURCE_PATTERNS.items():
                if domain in url_lower:
                    return source
            if any(news_domain in url_lower for news_domain in ['cnn', 'bbc', 'nyt', 'reuters', 'bloomberg', 'news']):
                return 'news'
            
            # Extract domain from URL as fallback
            try:
                from urllib.parse import urlparse
                parsed = urlparse(url)
                netloc = parsed.netloc.lower().replace('www.', '')
                domain_parts = netloc.split('.')
                if len(domain_parts) >= 2:
                    main_domain = domain_parts[-2] if len(domain_parts) > 2 else domain_parts[0]
                    return main_domain.lower()
                return netloc
            except Exception:
                pass

        # Default: unknown source
        return 'other'

    def detect_category(self, url: str, title: str, description: str) -> str:
        """
        Detect category from URL and text content.

        Uses keyword matching:
        1. Combines URL, title, and description into one text
        2. Counts keyword matches for each category
        3. Returns category with most matches

        Args:
            url: The URL
            title: Page title
            description: Page description

        Returns:
            Category identifier (e.g., 'technology', 'business', 'other')

        Examples:
            title="Learn Python Programming" → 'technology'
            title="10 Productivity Tips" → 'productivity'
            title="Movie Review: ..." → 'entertainment'
        """
        # Combine all text and convert to lowercase for matching
        text = f"{url} {title} {description}".lower()

        # Count keyword matches for each category
        scores = {}
        for category, keywords in self.CATEGORY_KEYWORDS.items():
            # Count how many keywords from this category appear in text
            scores[category] = sum(1 for keyword in keywords if keyword in text)

        # If we have any matches, return category with highest score
        if max(scores.values()) > 0:
            return max(scores, key=scores.get)

        # No matches: default to 'other'
        return 'other'

    def _map_og_section_to_category(self, og_section: str) -> Optional[str]:
        """
        Map OpenGraph article:section to our category system.

        Common OpenGraph sections and their category mappings:
        - Technology/Tech → technology
        - Business → business
        - Design → design
        - Science → science
        - Entertainment → entertainment
        - Education → education
        - Productivity → productivity

        Args:
            og_section: OpenGraph article:section value

        Returns:
            Category identifier or None if no match
        """
        og_section_lower = og_section.lower()
        
        # Direct mappings
        section_mappings = {
            'technology': 'technology',
            'tech': 'technology',
            'business': 'business',
            'design': 'design',
            'science': 'science',
            'entertainment': 'entertainment',
            'education': 'education',
            'productivity': 'productivity',
            'productivity tools': 'productivity',
            'news': 'other',
            'lifestyle': 'other',
            'health': 'other',
            'sports': 'entertainment',
            'gaming': 'entertainment',
        }
        
        # Check direct match first
        if og_section_lower in section_mappings:
            return section_mappings[og_section_lower]
        
        # Check if section contains any category keywords
        for category, keywords in self.CATEGORY_KEYWORDS.items():
            for keyword in keywords:
                if keyword in og_section_lower:
                    return category
        
        return None

    def extract_basic_tags(self, title: str, description: str, meta_keywords: Optional[List[str]] = None, meta_tags: Optional[List[str]] = None, og_tags: Optional[Dict[str, Any]] = None) -> List[str]:
        """
        Extract basic tags from title, description, HTML metadata, and OpenGraph tags.

        Priority order:
        1. OpenGraph article tags (og:article:tag) - highest priority
        2. HTML meta keywords and tags
        3. Title and description keywords (fallback)

        Args:
            title: Page title
            description: Page description
            meta_keywords: Keywords from HTML meta tags (optional)
            meta_tags: Tags from HTML meta tags (optional)
            og_tags: OpenGraph tags dictionary (optional)

        Returns:
            List of tag strings (max 5)

        Examples:
            title="FastAPI Tutorial for Python Developers"
            meta_keywords=["python", "fastapi", "tutorial"]
            og_tags={"article_tags": ["python", "web-development"]}
            → ['python', 'web-development', 'fastapi', 'tutorial', 'developers']

        Note: When AI is disabled, this uses HTML metadata and OpenGraph tags for better accuracy
        """
        tags = []

        # Priority 1: Use OpenGraph article tags if available (most reliable)
        if og_tags and 'article_tags' in og_tags:
            article_tags = og_tags['article_tags']
            if isinstance(article_tags, list):
                tags.extend([tag.lower() if isinstance(tag, str) else str(tag).lower() for tag in article_tags[:3]])
            elif isinstance(article_tags, str):
                tags.append(article_tags.lower())

        # Priority 2: Use HTML meta keywords and tags if available
        if meta_keywords:
            # Add keywords that aren't already in the list
            for kw in meta_keywords[:3]:
                if kw not in tags and len(tags) < 5:
                    tags.append(kw)
        
        if meta_tags:
            # Add tags that aren't already in the list
            for tag in meta_tags:
                if tag not in tags and len(tags) < 5:
                    tags.append(tag)

        # Priority 3: Extract from title and description if we don't have enough tags
        if len(tags) < 5:
            # Combine title and description
            text = f"{title} {description}"
            words = text.split()

            # Extract potential tags
            for word in words:
                # Clean word (remove punctuation)
                word_clean = word.strip('.,!?;:()[]{}"\'-').lower()

                # Skip short words
                if len(word_clean) <= 4:
                    continue

                # Include if:
                # - Original word was capitalized (likely a proper noun)
                # - Word is a common technical term
                technical_terms = ['api', 'ai', 'ml', 'ui', 'ux', 'css', 'html', 'sql']

                if word[0].isupper() or word_clean in technical_terms:
                    # Avoid duplicates
                    if word_clean not in tags:
                        tags.append(word_clean)

                    # Stop at 5 tags
                    if len(tags) >= 5:
                        break

        return tags[:5]  # Return max 5 tags

    def estimate_reading_time(self, text: str) -> int:
        """
        Estimate reading time in minutes.

        Average reading speed: 200 words per minute

        Args:
            text: The main text content

        Returns:
            Estimated reading time in minutes (minimum 1)

        Examples:
            400 words → 2 minutes
            100 words → 1 minute (minimum)
        """
        # Count words (split by whitespace)
        word_count = len(text.split())

        # Calculate minutes (200 words per minute)
        # Round up using integer division + 1
        minutes = max(1, (word_count + 199) // 200)

        return minutes
