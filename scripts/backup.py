"""
Automated Backup System
Backs up database, configurations, and important data
"""
import shutil
import os
from pathlib import Path
from datetime import datetime, timedelta
import tarfile
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BASE_DIR = Path(__file__).resolve().parent.parent
BACKUP_DIR = BASE_DIR / "backups"
DATA_DIR = BASE_DIR / "data"
MODELS_DIR = BASE_DIR / "models"


def create_backup(include_models: bool = False):
    """Create a backup of important data"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_name = f"oromo_stt_backup_{timestamp}.tar.gz"
    backup_path = BACKUP_DIR / backup_name
    
    logger.info(f"Creating backup: {backup_name}")
    
    try:
        with tarfile.open(backup_path, "w:gz") as tar:
            # Backup database
            if (DATA_DIR / "oromo_stt.db").exists():
                tar.add(DATA_DIR / "oromo_stt.db", arcname="data/oromo_stt.db")
                logger.info("  ✓ Database backed up")
            
            # Backup configuration
            if (BASE_DIR / ".env").exists():
                tar.add(BASE_DIR / ".env", arcname=".env")
                logger.info("  ✓ Configuration backed up")
            
            # Backup logs (last 7 days only)
            logs_dir = BASE_DIR / "logs"
            if logs_dir.exists():
                for log_file in logs_dir.glob("*.log"):
                    if (datetime.now() - datetime.fromtimestamp(log_file.stat().st_mtime)).days <= 7:
                        tar.add(log_file, arcname=f"logs/{log_file.name}")
                logger.info("  ✓ Logs backed up")
            
            # Optionally backup models (large!)
            if include_models and MODELS_DIR.exists():
                tar.add(MODELS_DIR, arcname="models")
                logger.info("  ✓ Models backed up")
        
        file_size = backup_path.stat().st_size / 1024 / 1024  # MB
        logger.info(f"Backup created successfully: {backup_name} ({file_size:.2f} MB)")
        
        return str(backup_path)
    
    except Exception as e:
        logger.error(f"Backup failed: {e}")
        if backup_path.exists():
            backup_path.unlink()
        raise


def cleanup_old_backups(retention_days: int = 30):
    """Remove backups older than retention period"""
    logger.info(f"Cleaning up backups older than {retention_days} days")
    
    cutoff_date = datetime.now() - timedelta(days=retention_days)
    removed_count = 0
    
    for backup_file in BACKUP_DIR.glob("oromo_stt_backup_*.tar.gz"):
        file_time = datetime.fromtimestamp(backup_file.stat().st_mtime)
        if file_time < cutoff_date:
            backup_file.unlink()
            logger.info(f"  Removed old backup: {backup_file.name}")
            removed_count += 1
    
    logger.info(f"Cleanup complete. Removed {removed_count} old backup(s)")


def restore_backup(backup_path: str):
    """Restore from a backup file"""
    backup_file = Path(backup_path)
    
    if not backup_file.exists():
        raise FileNotFoundError(f"Backup file not found: {backup_path}")
    
    logger.info(f"Restoring from backup: {backup_file.name}")
    
    # Create restore point of current state
    logger.info("Creating restore point of current state...")
    create_backup(include_models=False)
    
    try:
        with tarfile.open(backup_file, "r:gz") as tar:
            tar.extractall(path=BASE_DIR)
        
        logger.info("Restore completed successfully")
    except Exception as e:
        logger.error(f"Restore failed: {e}")
        raise


def list_backups():
    """List all available backups"""
    backups = []
    
    for backup_file in sorted(BACKUP_DIR.glob("oromo_stt_backup_*.tar.gz"), reverse=True):
        size_mb = backup_file.stat().st_size / 1024 / 1024
        modified = datetime.fromtimestamp(backup_file.stat().st_mtime)
        
        backups.append({
            "name": backup_file.name,
            "path": str(backup_file),
            "size_mb": round(size_mb, 2),
            "created": modified.strftime("%Y-%m-%d %H:%M:%S")
        })
    
    return backups


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Oromo STT Backup Tool")
    parser.add_argument("action", choices=["create", "restore", "list", "cleanup"],
                       help="Action to perform")
    parser.add_argument("--include-models", action="store_true",
                       help="Include models in backup (large!)")
    parser.add_argument("--retention-days", type=int, default=30,
                       help="Retention period for cleanup (default: 30)")
    parser.add_argument("--backup-file", type=str,
                       help="Backup file path for restore")
    
    args = parser.parse_args()
    
    # Ensure backup directory exists
    BACKUP_DIR.mkdir(exist_ok=True)
    
    if args.action == "create":
        create_backup(include_models=args.include_models)
    
    elif args.action == "restore":
        if not args.backup_file:
            print("Error: --backup-file required for restore")
            exit(1)
        restore_backup(args.backup_file)
    
    elif args.action == "list":
        backups = list_backups()
        if not backups:
            print("No backups found")
        else:
            print(f"\nAvailable Backups ({len(backups)}):")
            print("="*80)
            for backup in backups:
                print(f"  {backup['name']}")
                print(f"    Created: {backup['created']}")
                print(f"    Size: {backup['size_mb']} MB")
                print()
    
    elif args.action == "cleanup":
        cleanup_old_backups(retention_days=args.retention_days)
