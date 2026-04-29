"""decouple_ai_from_ingestion

Revision ID: fbe4c10336ba
Revises: ced17a7d6797
Create Date: 2025-12-31 18:13:10.357882

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'fbe4c10336ba'
down_revision: Union[str, None] = 'ced17a7d6797'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """
    Decouple AI processing from content ingestion (IDEMPOTENT).

    Replaces single processing_status with separate ingestion_status and ai_status.
    This enables two-phase processing:
    - Phase 1: Fast ingestion (URL fetch + metadata) - content visible immediately
    - Phase 2: Slower AI processing (summarization + embeddings) - enriches content

    Note: This migration is idempotent - safe to run multiple times.
    """
    # Step 1: Create new enum types (if not exists)
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE ingestionstatus AS ENUM (
                'pending', 'fetching', 'ingested', 'failed'
            );
        EXCEPTION
            WHEN duplicate_object THEN null;
        END $$;
    """)
    op.execute("""
        DO $$ BEGIN
            CREATE TYPE aistatus AS ENUM (
                'pending', 'processing', 'completed', 'failed', 'disabled'
            );
        EXCEPTION
            WHEN duplicate_object THEN null;
        END $$;
    """)

    # Step 2: Add new columns (if not exists)
    # Check which columns exist and only add missing ones
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    existing_columns = {col['name'] for col in inspector.get_columns('content_items')}

    if 'ingestion_status' not in existing_columns:
        op.add_column('content_items',
            sa.Column('ingestion_status', sa.Enum('pending', 'fetching', 'ingested', 'failed',
                      name='ingestionstatus'), nullable=True))
    if 'ingestion_error' not in existing_columns:
        op.add_column('content_items',
            sa.Column('ingestion_error', sa.Text(), nullable=True))
    if 'ingestion_attempts' not in existing_columns:
        op.add_column('content_items',
            sa.Column('ingestion_attempts', sa.Integer(), server_default='0', nullable=False))
    if 'last_ingestion_at' not in existing_columns:
        op.add_column('content_items',
            sa.Column('last_ingestion_at', sa.DateTime(), nullable=True))

    if 'ai_status' not in existing_columns:
        op.add_column('content_items',
            sa.Column('ai_status', sa.Enum('pending', 'processing', 'completed', 'failed', 'disabled',
                      name='aistatus'), nullable=True))
    if 'ai_error' not in existing_columns:
        op.add_column('content_items',
            sa.Column('ai_error', sa.Text(), nullable=True))
    if 'ai_attempts' not in existing_columns:
        op.add_column('content_items',
            sa.Column('ai_attempts', sa.Integer(), server_default='0', nullable=False))
    if 'last_ai_processed_at' not in existing_columns:
        op.add_column('content_items',
            sa.Column('last_ai_processed_at', sa.DateTime(), nullable=True))

    # Step 3: Migrate existing data from old processing_status to new fields
    op.execute("""
        UPDATE content_items
        SET
            -- Map old processing_status to new ingestion_status
            ingestion_status = CASE
                WHEN processing_status = 'pending' THEN 'pending'::ingestionstatus
                WHEN processing_status = 'processing' THEN 'fetching'::ingestionstatus
                WHEN processing_status = 'completed' THEN 'ingested'::ingestionstatus
                WHEN processing_status = 'failed' THEN 'failed'::ingestionstatus
                ELSE 'pending'::ingestionstatus
            END,

            -- Map old processing_status to new ai_status
            ai_status = CASE
                WHEN processing_status = 'pending' THEN 'pending'::aistatus
                WHEN processing_status = 'processing' THEN 'pending'::aistatus
                WHEN processing_status = 'completed' THEN 'completed'::aistatus
                WHEN processing_status = 'failed' THEN 'pending'::aistatus
                ELSE 'pending'::aistatus
            END,

            -- Migrate attempt counts
            ingestion_attempts = COALESCE(processing_attempts, 0),
            ai_attempts = CASE
                WHEN processing_status = 'completed' THEN COALESCE(processing_attempts, 0)
                ELSE 0
            END,

            -- Migrate timestamps
            last_ingestion_at = last_processed_at,
            last_ai_processed_at = CASE
                WHEN processing_status = 'completed' THEN last_processed_at
                ELSE NULL
            END,

            -- Migrate error messages to ingestion_error (AI errors start fresh)
            ingestion_error = CASE
                WHEN processing_status = 'failed' THEN processing_error
                ELSE NULL
            END,
            ai_error = NULL
    """)

    # Step 4: Make new columns non-nullable now that data is migrated
    op.alter_column('content_items', 'ingestion_status', nullable=False)
    op.alter_column('content_items', 'ai_status', nullable=False)

    # Step 5: Create indexes for efficient querying
    op.create_index('ix_content_items_ingestion_status', 'content_items', ['ingestion_status'])
    op.create_index('ix_content_items_ai_status', 'content_items', ['ai_status'])

    # Step 6: Drop old columns and enum (backwards incompatible but cleaner)
    # Note: We're keeping old columns for now to allow gradual migration
    # Uncomment these lines after verifying new system works:
    # op.drop_index('ix_content_items_processing_status', 'content_items')
    # op.drop_column('content_items', 'processing_status')
    # op.drop_column('content_items', 'processing_error')
    # op.drop_column('content_items', 'processing_attempts')
    # op.drop_column('content_items', 'last_processed_at')
    # op.execute("DROP TYPE processingstatus")


def downgrade() -> None:
    """
    Rollback: Restore single processing_status from dual-status fields.
    """
    # Reverse the migration by consolidating statuses back
    op.execute("""
        UPDATE content_items
        SET
            processing_status = CASE
                -- If AI completed, mark as completed
                WHEN ai_status = 'completed' THEN 'completed'::processingstatus
                -- If AI is processing, mark as processing
                WHEN ai_status = 'processing' THEN 'processing'::processingstatus
                -- If ingestion failed, mark as failed
                WHEN ingestion_status = 'failed' THEN 'failed'::processingstatus
                -- If ingestion is fetching, mark as processing
                WHEN ingestion_status = 'fetching' THEN 'processing'::processingstatus
                -- Otherwise mark as pending
                ELSE 'pending'::processingstatus
            END,
            processing_attempts = GREATEST(
                COALESCE(ingestion_attempts, 0),
                COALESCE(ai_attempts, 0)
            ),
            last_processed_at = COALESCE(last_ai_processed_at, last_ingestion_at),
            processing_error = COALESCE(ai_error, ingestion_error)
    """)

    # Drop new indexes
    op.drop_index('ix_content_items_ai_status', 'content_items')
    op.drop_index('ix_content_items_ingestion_status', 'content_items')

    # Drop new columns
    op.drop_column('content_items', 'last_ai_processed_at')
    op.drop_column('content_items', 'ai_attempts')
    op.drop_column('content_items', 'ai_error')
    op.drop_column('content_items', 'ai_status')

    op.drop_column('content_items', 'last_ingestion_at')
    op.drop_column('content_items', 'ingestion_attempts')
    op.drop_column('content_items', 'ingestion_error')
    op.drop_column('content_items', 'ingestion_status')

    # Drop new enum types
    op.execute("DROP TYPE aistatus")
    op.execute("DROP TYPE ingestionstatus")
