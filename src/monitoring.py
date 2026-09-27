"""
Production Monitoring and Health Checks
System resource monitoring, health endpoints, and metrics
"""
import psutil
import time
from datetime import datetime
from typing import Dict, Any
import logging
from pathlib import Path
import os

from src.config import get_settings

settings = get_settings()
logger = logging.getLogger(__name__)


class SystemMonitor:
    """Monitor system resources and health"""
    
    @staticmethod
    def get_cpu_usage() -> float:
        """Get CPU usage percentage"""
        return psutil.cpu_percent(interval=1)
    
    @staticmethod
    def get_memory_usage() -> Dict[str, Any]:
        """Get memory usage information"""
        mem = psutil.virtual_memory()
        return {
            "total": mem.total,
            "available": mem.available,
            "used": mem.used,
            "percent": mem.percent
        }
    
    @staticmethod
    def get_disk_usage() -> Dict[str, Any]:
        """Get disk usage for application directory"""
        base_path = Path(settings.TEMP_DIR).parent
        disk = psutil.disk_usage(str(base_path))
        return {
            "total": disk.total,
            "used": disk.used,
            "free": disk.free,
            "percent": disk.percent
        }
    
    @staticmethod
    def get_process_info() -> Dict[str, Any]:
        """Get current process information"""
        process = psutil.Process()
        with process.oneshot():
            return {
                "pid": process.pid,
                "cpu_percent": process.cpu_percent(),
                "memory_mb": process.memory_info().rss / 1024 / 1024,
                "num_threads": process.num_threads(),
                "status": process.status()
            }
    
    @staticmethod
    def get_full_health() -> Dict[str, Any]:
        """Get comprehensive system health"""
        return {
            "timestamp": datetime.utcnow().isoformat(),
            "cpu": SystemMonitor.get_cpu_usage(),
            "memory": SystemMonitor.get_memory_usage(),
            "disk": SystemMonitor.get_disk_usage(),
            "process": SystemMonitor.get_process_info()
        }


class PerformanceTracker:
    """Track API performance metrics"""
    
    def __init__(self):
        self.start_time = time.time()
        self.request_count = 0
        self.error_count = 0
        self.total_processing_time = 0.0
    
    def record_request(self, processing_time: float, success: bool = True):
        """Record a request"""
        self.request_count += 1
        self.total_processing_time += processing_time
        if not success:
            self.error_count += 1
    
    def get_stats(self) -> Dict[str, Any]:
        """Get performance statistics"""
        uptime = time.time() - self.start_time
        return {
            "uptime_seconds": round(uptime, 2),
            "total_requests": self.request_count,
            "successful_requests": self.request_count - self.error_count,
            "failed_requests": self.error_count,
            "avg_processing_time": round(
                self.total_processing_time / self.request_count, 3
            ) if self.request_count > 0 else 0,
            "requests_per_minute": round(
                self.request_count / (uptime / 60), 2
            ) if uptime > 0 else 0
        }
    
    def reset(self):
        """Reset statistics"""
        self.start_time = time.time()
        self.request_count = 0
        self.error_count = 0
        self.total_processing_time = 0.0


# Global tracker instance
performance_tracker = PerformanceTracker()


def check_model_health(model) -> Dict[str, Any]:
    """Check if model is loaded and functional"""
    try:
        if model is None:
            return {"loaded": False, "error": "Model not initialized"}
        
        return {
            "loaded": True,
            "type": str(type(model).__name__),
            "device": getattr(model, 'device', 'unknown'),
            "status": "healthy"
        }
    except Exception as e:
        return {
            "loaded": False,
            "error": str(e),
            "status": "unhealthy"
        }


def check_storage_health() -> Dict[str, Any]:
    """Check storage availability"""
    try:
        temp_dir = Path(settings.TEMP_DIR)
        results_dir = Path(settings.RESULTS_DIR)
        
        return {
            "temp_dir": {
                "exists": temp_dir.exists(),
                "writable": temp_dir.exists() and os.access(temp_dir, os.W_OK)
            },
            "results_dir": {
                "exists": results_dir.exists(),
                "writable": results_dir.exists() and os.access(results_dir, os.W_OK)
            }
        }
    except Exception as e:
        return {"error": str(e), "status": "unhealthy"}


def get_comprehensive_health(model=None, db=None) -> Dict[str, Any]:
    """Get comprehensive health check"""
    system_health = SystemMonitor.get_full_health()
    model_health = check_model_health(model)
    storage_health = check_storage_health()
    performance_stats = performance_tracker.get_stats()
    
    # Determine overall status
    overall_status = "healthy"
    if not model_health.get("loaded"):
        overall_status = "degraded"
    if system_health["cpu"] > 90 or system_health["memory"]["percent"] > 90:
        overall_status = "degraded"
    
    health_data = {
        "status": overall_status,
        "timestamp": datetime.utcnow().isoformat(),
        "version": settings.APP_VERSION,
        "system": system_health,
        "model": model_health,
        "storage": storage_health,
        "performance": performance_stats
    }
    
    # Add database stats if available
    if db:
        try:
            from src.database import TranscriptionService
            db_stats = TranscriptionService.get_stats(db)
            health_data["database"] = {
                "status": "connected",
                "stats": db_stats
            }
        except Exception as e:
            health_data["database"] = {
                "status": "error",
                "error": str(e)
            }
    
    return health_data



if __name__ == "__main__":
    # Test monitoring
    print("="*60)
    print("SYSTEM MONITORING TEST")
    print("="*60)
    
    monitor = SystemMonitor()
    print(f"CPU Usage: {monitor.get_cpu_usage()}%")
    print(f"Memory: {monitor.get_memory_usage()}")
    print(f"Disk: {monitor.get_disk_usage()}")
    print(f"Process: {monitor.get_process_info()}")
    print("="*60)
