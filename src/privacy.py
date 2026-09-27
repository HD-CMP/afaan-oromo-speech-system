"""
Privacy and Security Module
Implements file cleanup, retention policies, and secure handling
"""
import os
import time
import hashlib
import logging
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional, List
import threading

from src.config import get_settings

settings = get_settings()
logger = logging.getLogger(__name__)


class PrivacyManager:
    """Manages privacy and security for file handling"""
    
    def __init__(self):
        self.cleanup_thread = None
        self.running = False
    
    @staticmethod
    def sanitize_filename(filename: str) -> str:
        """Sanitize filename to prevent directory traversal"""
        filename = os.path.basename(filename)
        filename = "".join(c for c in filename if c.isalnum() or c in ('_', '-', '.'))
        return filename[:255]
    
    @staticmethod
    def generate_secure_filename(original_filename: str) -> str:
        """Generate secure unique filename"""
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        random_hash = hashlib.md5(str(time.time()).encode()).hexdigest()[:8]
        ext = Path(original_filename).suffix
        return f"{timestamp}_{random_hash}{ext}"
    
    @staticmethod
    def cleanup_file(filepath: str, delay: int = 0) -> bool:
        """
        Cleanup file with optional delay
        
        Args:
            filepath: Path to file to delete
            delay: Delay in seconds before deletion (0 = immediate)
        
        Returns:
            True if successful, False otherwise
        """
        def _cleanup():
            if delay > 0:
                time.sleep(delay)
            
            try:
                if os.path.exists(filepath):
                    os.remove(filepath)
                    logger.info(f"[PRIVACY] Deleted file: {os.path.basename(filepath)}")
                    return True
            except Exception as e:
                logger.error(f"[PRIVACY] Cleanup failed for {filepath}: {e}")
                return False
        
        if delay > 0:
            thread = threading.Thread(target=_cleanup, daemon=True)
            thread.start()
            return True
        else:
            return _cleanup()
    
    @staticmethod
    def cleanup_old_files(directory: str, max_age_hours: int = 1) -> int:
        """
        Delete files older than specified hours
        
        Args:
            directory: Directory to clean
            max_age_hours: Maximum age in hours
        
        Returns:
            Number of files deleted
        """
        if not os.path.exists(directory):
            return 0
        
        cutoff_time = time.time() - (max_age_hours * 3600)
        deleted_count = 0
        
        try:
            for filename in os.listdir(directory):
                filepath = os.path.join(directory, filename)
                
                if not os.path.isfile(filepath):
                    continue
                
                file_age = os.path.getmtime(filepath)
                if file_age < cutoff_time:
                    try:
                        os.remove(filepath)
                        deleted_count += 1
                        logger.debug(f"[PRIVACY] Deleted old file: {filename}")
                    except Exception as e:
                        logger.warning(f"[PRIVACY] Could not delete {filename}: {e}")
        
        except Exception as e:
            logger.error(f"[PRIVACY] Cleanup error in {directory}: {e}")
        
        if deleted_count > 0:
            logger.info(f"[PRIVACY] Cleaned {deleted_count} files from {directory}")
        
        return deleted_count
    
    @staticmethod
    def enforce_file_retention(directory: str, max_files: int = 100) -> int:
        """
        Enforce maximum file count by deleting oldest files
        
        Args:
            directory: Directory to enforce limit
            max_files: Maximum number of files to keep
        
        Returns:
            Number of files deleted
        """
        if not os.path.exists(directory):
            return 0
        
        try:
            files = []
            for filename in os.listdir(directory):
                filepath = os.path.join(directory, filename)
                if os.path.isfile(filepath):
                    files.append((filepath, os.path.getmtime(filepath)))
            
            if len(files) <= max_files:
                return 0
            
            files.sort(key=lambda x: x[1])
            files_to_delete = files[:len(files) - max_files]
            deleted_count = 0
            
            for filepath, _ in files_to_delete:
                try:
                    os.remove(filepath)
                    deleted_count += 1
                except Exception as e:
                    logger.warning(f"[PRIVACY] Retention delete failed: {e}")
            
            logger.info(f"[PRIVACY] Retention policy deleted {deleted_count} files")
            return deleted_count
        
        except Exception as e:
            logger.error(f"[PRIVACY] Retention enforcement error: {e}")
            return 0
    
    @staticmethod
    def get_directory_size(directory: str) -> int:
        """Get total size of directory in bytes"""
        total_size = 0
        try:
            for dirpath, dirnames, filenames in os.walk(directory):
                for filename in filenames:
                    filepath = os.path.join(dirpath, filename)
                    if os.path.exists(filepath):
                        total_size += os.path.getsize(filepath)
        except Exception as e:
            logger.error(f"[PRIVACY] Size calculation error: {e}")
        
        return total_size
    
    @staticmethod
    def enforce_storage_quota(directory: str, max_size_mb: int = 1000) -> int:
        """
        Enforce storage quota by deleting oldest files
        
        Args:
            directory: Directory to enforce quota
            max_size_mb: Maximum size in megabytes
        
        Returns:
            Number of files deleted
        """
        current_size = PrivacyManager.get_directory_size(directory)
        max_size_bytes = max_size_mb * 1024 * 1024
        
        if current_size <= max_size_bytes:
            return 0
        
        try:
            files = []
            for dirpath, dirnames, filenames in os.walk(directory):
                for filename in filenames:
                    filepath = os.path.join(dirpath, filename)
                    if os.path.exists(filepath):
                        files.append((filepath, os.path.getmtime(filepath), os.path.getsize(filepath)))
            
            files.sort(key=lambda x: x[1])
            
            deleted_count = 0
            deleted_size = 0
            
            for filepath, _, filesize in files:
                if current_size - deleted_size <= max_size_bytes:
                    break
                
                try:
                    os.remove(filepath)
                    deleted_count += 1
                    deleted_size += filesize
                except Exception as e:
                    logger.warning(f"[PRIVACY] Quota delete failed: {e}")
            
            logger.info(f"[PRIVACY] Quota enforcement: deleted {deleted_count} files ({deleted_size / 1024 / 1024:.2f} MB)")
            return deleted_count
        
        except Exception as e:
            logger.error(f"[PRIVACY] Quota enforcement error: {e}")
            return 0
    
    def start_background_cleanup(self, interval_minutes: int = 30):
        """Start background cleanup thread"""
        if self.running:
            logger.warning("[PRIVACY] Background cleanup already running")
            return
        
        self.running = True
        
        def cleanup_loop():
            logger.info(f"[PRIVACY] Background cleanup started (interval: {interval_minutes}min)")
            
            while self.running:
                try:
                    temp_cleaned = self.cleanup_old_files(settings.TEMP_DIR, max_age_hours=1)
                    results_cleaned = self.cleanup_old_files(settings.RESULTS_DIR, max_age_hours=24)
                    
                    self.enforce_file_retention(settings.TEMP_DIR, max_files=50)
                    self.enforce_storage_quota(settings.TEMP_DIR, max_size_mb=500)
                    
                    if temp_cleaned > 0 or results_cleaned > 0:
                        logger.info(f"[PRIVACY] Cleanup cycle: {temp_cleaned} temp, {results_cleaned} results")
                
                except Exception as e:
                    logger.error(f"[PRIVACY] Cleanup cycle error: {e}")
                
                time.sleep(interval_minutes * 60)
        
        self.cleanup_thread = threading.Thread(target=cleanup_loop, daemon=True)
        self.cleanup_thread.start()
    
    def stop_background_cleanup(self):
        """Stop background cleanup thread"""
        self.running = False
        logger.info("[PRIVACY] Background cleanup stopped")


privacy_manager = PrivacyManager()


def validate_file_upload(filename: str, file_size: int, allowed_extensions: List[str] = None) -> tuple[bool, str]:
    """
    Validate uploaded file for security
    
    Args:
        filename: Original filename
        file_size: File size in bytes
        allowed_extensions: List of allowed extensions (default: audio/video)
    
    Returns:
        (is_valid, error_message)
    """
    if allowed_extensions is None:
        allowed_extensions = ['.wav', '.mp3', '.m4a', '.flac', '.ogg', '.mp4', '.avi', '.mov', '.mkv']
    
    if file_size > settings.MAX_FILE_SIZE:
        return False, f"File too large. Max size: {settings.MAX_FILE_SIZE_MB}MB"
    
    if file_size < 1024:
        return False, "File too small (min 1KB)"
    
    ext = Path(filename).suffix.lower()
    if ext not in allowed_extensions:
        return False, f"Invalid file type. Allowed: {', '.join(allowed_extensions)}"
    
    sanitized = privacy_manager.sanitize_filename(filename)
    if not sanitized or len(sanitized) < 3:
        return False, "Invalid filename"
    
    return True, "Valid"


if __name__ == "__main__":
    print("="*60)
    print("PRIVACY MANAGER TEST")
    print("="*60)
    
    manager = PrivacyManager()
    
    print(f"Sanitized: {manager.sanitize_filename('../../etc/passwd')}")
    print(f"Secure: {manager.generate_secure_filename('test.wav')}")
    
    temp_size = manager.get_directory_size(settings.TEMP_DIR)
    print(f"Temp dir size: {temp_size / 1024 / 1024:.2f} MB")
    
    print("="*60)
