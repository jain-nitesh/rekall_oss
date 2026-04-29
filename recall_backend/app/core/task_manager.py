"""
Task Manager for bounded concurrency control.

Prevents unbounded task accumulation by limiting concurrent task execution
and tracking all running tasks for proper cleanup.
"""
import asyncio
import logging
from typing import Set, Coroutine, Any

logger = logging.getLogger(__name__)


class TaskManager:
    """
    Manages async tasks with bounded concurrency.

    Prevents memory leaks from unbounded task accumulation by:
    1. Limiting max concurrent tasks via semaphore
    2. Tracking all active tasks
    3. Auto-cleanup on task completion
    4. Graceful shutdown with task cancellation
    """

    def __init__(self, max_concurrent: int = 10, name: str = "TaskManager"):
        """
        Initialize task manager.

        Args:
            max_concurrent: Maximum number of concurrent tasks allowed
            name: Name for logging purposes
        """
        self.max_concurrent = max_concurrent
        self.name = name
        self.tasks: Set[asyncio.Task] = set()
        self.semaphore = asyncio.Semaphore(max_concurrent)
        self._shutdown = False

        logger.info(
            f"{self.name} initialized with max_concurrent={max_concurrent}"
        )

    async def create_task(self, coro: Coroutine) -> asyncio.Task:
        """
        Create and track a new task with concurrency limiting.

        Args:
            coro: Coroutine to execute

        Returns:
            The created task

        Raises:
            RuntimeError: If task manager is shutting down
        """
        if self._shutdown:
            raise RuntimeError(f"{self.name} is shutting down, cannot create new tasks")

        # Wait for available slot if at max capacity
        await self.semaphore.acquire()

        # Wrap coroutine to release semaphore when done
        task = asyncio.create_task(self._wrap_task(coro))
        self.tasks.add(task)

        # Auto-cleanup when task completes
        task.add_done_callback(self._task_done_callback)

        logger.debug(
            f"{self.name}: Created task ({len(self.tasks)} active, "
            f"{self.max_concurrent - self.semaphore._value} of {self.max_concurrent} slots used)"
        )

        return task

    async def _wrap_task(self, coro: Coroutine) -> Any:
        """
        Wrapper that ensures semaphore release even if task fails.

        Args:
            coro: Coroutine to execute

        Returns:
            Result of the coroutine
        """
        try:
            return await coro
        except asyncio.CancelledError:
            logger.debug(f"{self.name}: Task cancelled")
            raise
        except Exception as e:
            logger.error(f"{self.name}: Task failed with error: {e}", exc_info=True)
            raise
        finally:
            self.semaphore.release()

    def _task_done_callback(self, task: asyncio.Task) -> None:
        """
        Callback when task completes - removes from tracking set.

        Args:
            task: The completed task
        """
        self.tasks.discard(task)

        # Log if task failed
        if not task.cancelled() and task.exception() is not None:
            logger.error(
                f"{self.name}: Task completed with exception: {task.exception()}"
            )

        logger.debug(
            f"{self.name}: Task completed ({len(self.tasks)} active)"
        )

    async def shutdown(self, timeout: float = 30.0) -> None:
        """
        Gracefully shutdown task manager.

        Cancels all pending tasks and waits for them to finish.

        Args:
            timeout: Maximum time to wait for tasks to finish (seconds)
        """
        if self._shutdown:
            logger.warning(f"{self.name}: Already shutting down")
            return

        self._shutdown = True
        logger.info(f"{self.name}: Shutting down ({len(self.tasks)} active tasks)...")

        if not self.tasks:
            logger.info(f"{self.name}: No active tasks, shutdown complete")
            return

        # Cancel all tasks
        for task in self.tasks:
            if not task.done():
                task.cancel()

        # Wait for tasks to finish with timeout
        try:
            await asyncio.wait_for(
                asyncio.gather(*self.tasks, return_exceptions=True),
                timeout=timeout
            )
            logger.info(f"{self.name}: All tasks completed successfully")
        except asyncio.TimeoutError:
            logger.warning(
                f"{self.name}: Shutdown timeout after {timeout}s, "
                f"{sum(1 for t in self.tasks if not t.done())} tasks still running"
            )
        except Exception as e:
            logger.error(f"{self.name}: Error during shutdown: {e}", exc_info=True)

        self.tasks.clear()
        logger.info(f"{self.name}: Shutdown complete")

    def get_stats(self) -> dict:
        """
        Get current task manager statistics.

        Returns:
            Dictionary with stats:
            {
                'active_tasks': int,
                'max_concurrent': int,
                'available_slots': int,
                'is_shutdown': bool
            }
        """
        return {
            'active_tasks': len(self.tasks),
            'max_concurrent': self.max_concurrent,
            'available_slots': self.semaphore._value,
            'is_shutdown': self._shutdown
        }
