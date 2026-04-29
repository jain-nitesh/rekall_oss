"""
Video processing service for key frame extraction and metadata.
Uses ffmpeg via ffmpeg-python package.
"""
import asyncio
import logging
import tempfile
import os
from fractions import Fraction
from typing import List, Dict, Optional

from app.core.config import settings

logger = logging.getLogger(__name__)


class VideoProcessingService:
    """Extract key frames, thumbnails, and metadata from video files."""

    async def extract_key_frames(
        self, video_path: str, max_frames: Optional[int] = None
    ) -> List[bytes]:
        """
        Extract key frames from a video at evenly spaced intervals.
        For a 5-20 second clip, extracts frames at 25%, 50%, 75% timestamps.

        Returns list of JPEG-encoded frame bytes.
        """
        import ffmpeg

        max_frames = max_frames or settings.video_max_key_frames

        try:
            # Get video duration
            metadata = await self.get_video_metadata(video_path)
            duration = metadata.get("duration", 0)
            if duration <= 0:
                logger.warning(f"Could not determine video duration: {video_path}")
                return []

            frames = []
            # Calculate timestamps at even intervals (skip first/last 10%)
            for i in range(1, max_frames + 1):
                timestamp = duration * (i / (max_frames + 1))

                with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
                    tmp_path = tmp.name

                try:
                    cmd = (
                        ffmpeg
                        .input(video_path, ss=timestamp)
                        .output(tmp_path, vframes=1, format="image2", vcodec="mjpeg", q=2)
                        .overwrite_output()
                    )
                    loop = asyncio.get_event_loop()
                    await loop.run_in_executor(
                        None, lambda: cmd.run(capture_stdout=True, capture_stderr=True)
                    )

                    with open(tmp_path, "rb") as f:
                        frame_bytes = f.read()
                        if frame_bytes:
                            frames.append(frame_bytes)
                finally:
                    if os.path.exists(tmp_path):
                        os.unlink(tmp_path)

            logger.info(f"Extracted {len(frames)} key frames from {video_path}")
            return frames

        except Exception as e:
            logger.error(f"Key frame extraction failed: {e}")
            return []

    async def generate_video_thumbnail(self, video_path: str) -> Optional[bytes]:
        """
        Extract a thumbnail from the first meaningful frame (at 1 second or 10%).
        Returns JPEG bytes or None.
        """
        import ffmpeg

        try:
            metadata = await self.get_video_metadata(video_path)
            duration = metadata.get("duration", 0)
            timestamp = min(1.0, duration * 0.1) if duration > 0 else 0

            with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
                tmp_path = tmp.name

            try:
                cmd = (
                    ffmpeg
                    .input(video_path, ss=timestamp)
                    .output(tmp_path, vframes=1, format="image2", vcodec="mjpeg", q=2)
                    .overwrite_output()
                )
                loop = asyncio.get_event_loop()
                await loop.run_in_executor(
                    None, lambda: cmd.run(capture_stdout=True, capture_stderr=True)
                )

                with open(tmp_path, "rb") as f:
                    return f.read()
            finally:
                if os.path.exists(tmp_path):
                    os.unlink(tmp_path)

        except Exception as e:
            logger.error(f"Video thumbnail generation failed: {e}")
            return None

    async def get_video_metadata(self, video_path: str) -> Dict:
        """
        Get video metadata: duration, resolution, fps, codec.
        Returns dict with metadata fields.
        """
        import ffmpeg

        try:
            loop = asyncio.get_event_loop()
            probe = await loop.run_in_executor(None, lambda: ffmpeg.probe(video_path))

            video_stream = next(
                (s for s in probe["streams"] if s["codec_type"] == "video"),
                None
            )

            duration = float(probe.get("format", {}).get("duration", 0))
            result = {
                "duration": duration,
                "format": probe.get("format", {}).get("format_name", ""),
                "size_bytes": int(probe.get("format", {}).get("size", 0)),
            }

            if video_stream:
                fps_str = video_stream.get("r_frame_rate", "0/1")
                try:
                    fps = float(Fraction(fps_str)) if fps_str else 0
                except (ValueError, ZeroDivisionError):
                    fps = 0

                result.update({
                    "width": int(video_stream.get("width", 0)),
                    "height": int(video_stream.get("height", 0)),
                    "codec": video_stream.get("codec_name", ""),
                    "fps": fps,
                })

            return result

        except Exception as e:
            logger.error(f"Video metadata extraction failed: {e}")
            return {"duration": 0}


# Singleton
video_processing_service = VideoProcessingService()
