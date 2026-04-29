"""Add knowledge health check table for proactive intelligence.

Revision ID: health_001
Revises: conversations_001
Create Date: 2026-04-07

Creates knowledge_health_checks table for the proactive intelligence
feature (Second Brain Phase 4).
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = 'health_001'
down_revision: Union[str, None] = 'conversations_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE IF NOT EXISTS knowledge_health_checks (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            check_type VARCHAR(30) NOT NULL,
            title VARCHAR(300) NOT NULL,
            description TEXT,
            priority VARCHAR(10) NOT NULL DEFAULT 'medium',
            related_entity_id UUID REFERENCES entities(id) ON DELETE SET NULL,
            related_wiki_page_id UUID REFERENCES wiki_pages(id) ON DELETE SET NULL,
            is_dismissed BOOLEAN NOT NULL DEFAULT false,
            is_acted_on BOOLEAN NOT NULL DEFAULT false,
            created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
    """)

    op.execute("CREATE INDEX IF NOT EXISTS ix_health_checks_user_id ON knowledge_health_checks(user_id);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_health_checks_type ON knowledge_health_checks(check_type);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_health_checks_dismissed ON knowledge_health_checks(is_dismissed);")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS knowledge_health_checks;")
