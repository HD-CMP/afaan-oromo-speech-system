"""
Maintenance and Update Scripts
System maintenance, updates, and health checks
"""
import os
import sys
from pathlib import Path
import subprocess
import logging
from datetime import datetime
import shutil

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src.config import get_settings, ensure_directories
from src.database import init_db, SessionLocal
from src.monitoring import SystemMonitor

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).resolve().parent.parent


def check_system_health():
    """Comprehensive system health check"""
    logger.info("="*60)
    logger.info("SYSTEM HEALTH CHECK")
    logger.info("="*60)
    
    settings = get_settings()
    monitor = SystemMonitor()
    
    # Check directories
    logger.info("\n[1] Directory Structure:")
    required_dirs = [
        Path(settings.TEMP_DIR),
        Path(settings.RESULTS_DIR),
        Path(settings.BACKUP_DIR),
        BASE_DIR / "logs",
        BASE_DIR / "data"
    ]
    
    for directory in required_dirs:
        exists = directory.exists()
        writable = directory.exists() and os.access(directory, os.W_OK)
        status = "✓" if exists and writable else "✗"
        logger.info(f"  {status} {directory.name}: {'OK' if exists and writable else 'MISSING/NOT WRITABLE'}")
    
    # Check model
    logger.info("\n[2] Model Status:")
    model_path = Path(settings.MODEL_PATH)
    if model_path.exists():
        model_size = sum(f.stat().st_size for f in model_path.rglob('*') if f.is_file()) / 1024 / 1024
        logger.info(f"  ✓ Model found: {model_size:.2f} MB")
    else:
        logger.info(f"  ✗ Model NOT found at: {model_path}")
    
    # Check database
    logger.info("\n[3] Database Status:")
    db_path = BASE_DIR / "data" / "oromo_stt.db"
    if db_path.exists():
        db_size = db_path.stat().st_size / 1024 / 1024
        logger.info(f"  ✓ Database found: {db_size:.2f} MB")
    else:
        logger.info(f"  ✗ Database NOT found")
    
    # System resources
    logger.info("\n[4] System Resources:")
    logger.info(f"  CPU Usage: {monitor.get_cpu_usage()}%")
    
    memory = monitor.get_memory_usage()
    logger.info(f"  Memory: {memory['percent']}% ({memory['used']/1024/1024/1024:.2f}/{memory['total']/1024/1024/1024:.2f} GB)")
    
    disk = monitor.get_disk_usage()
    logger.info(f"  Disk: {disk['percent']}% ({disk['used']/1024/1024/1024:.2f}/{disk['total']/1024/1024/1024:.2f} GB)")
    
    # Dependencies
    logger.info("\n[5] Python Dependencies:")
    try:
        import torch
        import transformers
        import fastapi
        logger.info(f"  ✓ PyTorch: {torch.__version__}")
        logger.info(f"  ✓ Transformers: {transformers.__version__}")
        logger.info(f"  ✓ FastAPI: {fastapi.__version__}")
    except ImportError as e:
        logger.info(f"  ✗ Missing dependency: {e}")
    
    logger.info("="*60)


def cleanup_temp_files():
    """Clean up temporary files"""
    logger.info("Cleaning up temporary files...")
    
    settings = get_settings()
    temp_dir = Path(settings.TEMP_DIR)
    
    if not temp_dir.exists():
        logger.info("  Temp directory doesn't exist")
        return
    
    removed_count = 0
    freed_space = 0
    
    for file in temp_dir.glob("*"):
        if file.is_file():
            size = file.stat().st_size
            file.unlink()
            removed_count += 1
            freed_space += size
    
    logger.info(f"  Removed {removed_count} files")
    logger.info(f"  Freed {freed_space/1024/1024:.2f} MB")


def cleanup_old_logs(days: int = 30):
    """Remove log files older than specified days"""
    logger.info(f"Cleaning up log files older than {days} days...")
    
    from datetime import timedelta
    cutoff_date = datetime.now() - timedelta(days=days)
    
    logs_dir = BASE_DIR / "logs"
    if not logs_dir.exists():
        logger.info("  No logs directory")
        return
    
    removed_count = 0
    for log_file in logs_dir.glob("*.log*"):
        file_time = datetime.fromtimestamp(log_file.stat().st_mtime)
        if file_time < cutoff_date:
            log_file.unlink()
            removed_count += 1
    
    logger.info(f"  Removed {removed_count} old log files")


def update_dependencies():
    """Update Python dependencies"""
    logger.info("Updating Python dependencies...")
    
    requirements_file = BASE_DIR / "requirements.txt"
    if not requirements_file.exists():
        logger.error("  requirements.txt not found")
        return
    
    try:
        subprocess.run([
            sys.executable, "-m", "pip", "install", "--upgrade", "-r", str(requirements_file)
        ], check=True)
        logger.info("  ✓ Dependencies updated successfully")
    except subprocess.CalledProcessError as e:
        logger.error(f"  ✗ Update failed: {e}")


def initialize_database():
    """Initialize or update database schema"""
    logger.info("Initializing database...")
    
    try:
        ensure_directories()
        init_db()
        logger.info("  ✓ Database initialized successfully")
    except Exception as e:
        logger.error(f"  ✗ Database initialization failed: {e}")


def optimize_database():
    """Optimize database (vacuum, analyze)"""
    logger.info("Optimizing database...")
    
    db_path = BASE_DIR / "data" / "oromo_stt.db"
    if not db_path.exists():
        logger.info("  Database doesn't exist yet")
        return
    
    try:
        import sqlite3
        conn = sqlite3.connect(db_path)
        
        # Get size before
        size_before = db_path.stat().st_size / 1024 / 1024
        
        # Vacuum
        conn.execute("VACUUM")
        
        # Analyze
        conn.execute("ANALYZE")
        
        conn.commit()
        conn.close()
        
        # Get size after
        size_after = db_path.stat().st_size / 1024 / 1024
        
        logger.info(f"  ✓ Database optimized")
        logger.info(f"    Before: {size_before:.2f} MB")
        logger.info(f"    After: {size_after:.2f} MB")
        logger.info(f"    Saved: {size_before - size_after:.2f} MB")
    
    except Exception as e:
        logger.error(f"  ✗ Optimization failed: {e}")


def generate_health_report():
    """Generate comprehensive health report"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_file = BASE_DIR / "logs" / f"health_report_{timestamp}.txt"
    
    logger.info(f"Generating health report: {report_file.name}")
    
    with open(report_file, "w") as f:
        f.write("="*80 + "\n")
        f.write(f"HEALTH REPORT - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write("="*80 + "\n\n")
        
        # System info
        monitor = SystemMonitor()
        f.write("[SYSTEM RESOURCES]\n")
        f.write(f"CPU: {monitor.get_cpu_usage()}%\n")
        
        memory = monitor.get_memory_usage()
        f.write(f"Memory: {memory['percent']}%\n")
        
        disk = monitor.get_disk_usage()
        f.write(f"Disk: {disk['percent']}%\n\n")
        
        # Database stats
        try:
            from src.database import TranscriptionService
            db = SessionLocal()
            stats = TranscriptionService.get_stats(db)
            db.close()
            
            f.write("[DATABASE STATISTICS]\n")
            for key, value in stats.items():
                f.write(f"{key}: {value}\n")
        except Exception as e:
            f.write(f"[DATABASE STATISTICS] Error: {e}\n")
        
        f.write("\n" + "="*80 + "\n")
    
    logger.info(f"  ✓ Report saved to: {report_file}")


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Oromo STT Maintenance Tool")
    parser.add_argument("action", choices=[
        "health", "cleanup", "update", "init-db", "optimize-db", "report", "all"
    ], help="Maintenance action to perform")
    parser.add_argument("--log-retention-days", type=int, default=30,
                       help="Days to retain logs (default: 30)")
    
    args = parser.parse_args()
    
    if args.action == "health":
        check_system_health()
    
    elif args.action == "cleanup":
        cleanup_temp_files()
        cleanup_old_logs(days=args.log_retention_days)
    
    elif args.action == "update":
        update_dependencies()
    
    elif args.action == "init-db":
        initialize_database()
    
    elif args.action == "optimize-db":
        optimize_database()
    
    elif args.action == "report":
        generate_health_report()
    
    elif args.action == "all":
        logger.info("Running full maintenance...")
        check_system_health()
        cleanup_temp_files()
        cleanup_old_logs(days=args.log_retention_days)
        optimize_database()
        generate_health_report()
        logger.info("\n✓ Full maintenance completed")
