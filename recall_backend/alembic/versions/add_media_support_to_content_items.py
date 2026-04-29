"""Add media support to content_items for memory engine.

Revision ID: media_support_001
Revises: notes_001
Create Date: 2026-04-05

Adds content_type enum, media storage fields, and OCR text column
to support image/video capture alongside existing URL-based content.
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB


# revision identifiers, used by Alembic.
revision: str = 'media_support_001'
down_revision: Union[str, None] = 'notes_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Create the content_type enum
    content_type_enum = sa.Enum('url', 'image', 'video', 'note', name='contenttype')
    content_type_enum.create(op.get_bind(), checkfirst=True)

    # 2. Add content_type column with default 'url' for existing rows
    op.add_column('content_items', sa.Column(
        'content_type',
        sa.Enum('url', 'image', 'video', 'note', name='contenttype'),
        nullable=False,
        server_default='url'
    ))
    op.create_index('idx_content_items_content_type', 'content_items', ['content_type'])

    # 3. Make url column nullable (was NOT NULL, now nullable for image/video/note types)
    op.alter_column('content_items', 'url', existing_type=sa.Text(), nullable=True)

    # 4. Make title nullable (AI will generate titles for media content)
    op.alter_column('content_items', 'title', existing_type=sa.String(512), nullable=True)

    # 5. Make summary nullable (AI will generate summaries for media content)
    op.alter_column('content_items', 'summary', existing_type=sa.Text(), nullable=True)

    # 6. Add media storage fields
    op.add_column('content_items', sa.Column('media_url', sa.Text(), nullable=True))
    op.add_column('content_items', sa.Column('media_mime_type', sa.String(100), nullable=True))
    op.add_column('content_items', sa.Column('media_size_bytes', sa.BigInteger(), nullable=True))
    op.add_column('content_items', sa.Column('media_duration_seconds', sa.Float(), nullable=True))

    # 7. Add OCR text field
    op.add_column('content_items', sa.Column('ocr_text', sa.Text(), nullable=True))

    # 8. Add flexible media metadata (EXIF, GPS, dimensions, etc.)
    op.add_column('content_items', sa.Column('media_metadata', JSONB(), nullable=True))


def downgrade() -> None:
    # Delete media content rows that have NULL url/title/summary
    # (these can't satisfy NOT NULL constraints being restored)
    op.execute(
        "DELETE FROM content_items WHERE content_type IN ('image', 'video', 'note')"
    )

    # Remove media fields
    op.drop_column('content_items', 'media_metadata')
    op.drop_column('content_items', 'ocr_text')
    op.drop_column('content_items', 'media_duration_seconds')
    op.drop_column('content_items', 'media_size_bytes')
    op.drop_column('content_items', 'media_mime_type')
    op.drop_column('content_items', 'media_url')

    # Backfill any remaining NULLs before restoring NOT NULL
    op.execute("UPDATE content_items SET summary = '' WHERE summary IS NULL")
    op.execute("UPDATE content_items SET title = 'Untitled' WHERE title IS NULL")
    op.execute("UPDATE content_items SET url = '' WHERE url IS NULL")

    # Restore NOT NULL on summary and title
    op.alter_column('content_items', 'summary', existing_type=sa.Text(), nullable=False)
    op.alter_column('content_items', 'title', existing_type=sa.String(512), nullable=False)

    # Restore NOT NULL on url
    op.alter_column('content_items', 'url', existing_type=sa.Text(), nullable=False)

    # Remove content_type column and enum
    op.drop_index('idx_content_items_content_type', 'content_items')
    op.drop_column('content_items', 'content_type')
    sa.Enum(name='contenttype').drop(op.get_bind(), checkfirst=True)
