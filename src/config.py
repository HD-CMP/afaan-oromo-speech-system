"""
Production-Grade Configuration Management
Handles all application settings with environment variable support
"""
import os
from pathlib import Path
from typing import Optional
from pydantic_settings import BaseSettings
from functools import lru_cache

# Base directory
BASE_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    """Application settings with environment variable support"""
    
    # =========================================================
    # SERVER CONFIGURATION
    # =========================================================
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    DEBUG: bool = False
    RELOAD: bool = False
    APP_NAME: str = "Afaan Oromo STT API"
    APP_VERSION: str = "1.0.0"
    
    # =========================================================
    # MODEL CONFIGURATION
    # =========================================================
    MODEL_PATH: str = str(BASE_DIR / "models" / "whisper_backend")
    DEVICE: str = "auto"  # auto, cpu, cuda, 0, 1, etc.
    BATCH_SIZE: int = 16
    CHUNK_LENGTH: int = 30
    NUM_BEAMS: int = 5
    TEMPERATURE: float = 0.0
    
    # Quality Control Thresholds (Research-backed optimal values)
    COMPRESSION_RATIO_THRESHOLD: float = 2.4
    LOGPROB_THRESHOLD: float = -1.0
    NO_SPEECH_THRESHOLD: float = 0.6
    
    # =========================================================
    # FILE LIMITS
    # =========================================================
    MAX_FILE_SIZE_MB: int = 500
    MAX_AUDIO_DURATION_MINUTES: int = 120
    
    @property
    def MAX_FILE_SIZE(self) -> int:
        return self.MAX_FILE_SIZE_MB * 1024 * 1024
    
    # =========================================================
    # RATE LIMITING
    # =========================================================
    MAX_REQUESTS_PER_MINUTE: int = 10
    MAX_CONCURRENT_TRANSCRIPTIONS: int = 3
    RATE_LIMIT_ENABLED: bool = True
    
    # =========================================================
    # DATABASE
    # =========================================================
    DATABASE_URL: str = f"sqlite:///{BASE_DIR / 'data' / 'oromo_stt.db'}"
    ENABLE_DATABASE: bool = True
    
    # =========================================================
    # LOGGING
    # =========================================================
    LOG_LEVEL: str = "INFO"
    LOG_FILE: str = str(BASE_DIR / "logs" / "api.log")
    LOG_MAX_SIZE_MB: int = 100
    LOG_BACKUP_COUNT: int = 5
    
    # =========================================================
    # SECURITY
    # =========================================================
    ALLOWED_ORIGINS: str = "*"
    API_KEY_REQUIRED: bool = False
    API_KEY: str = "your-secret-api-key-here"
    
    # =========================================================
    # ERROR TRACKING
    # =========================================================
    SENTRY_DSN: str = ""
    SENTRY_ENVIRONMENT: str = "production"
    SENTRY_TRACES_SAMPLE_RATE: float = 0.1
    ENABLE_SENTRY: bool = False
    
    # =========================================================
    # FEATURES
    # =========================================================
    ENABLE_METRICS: bool = True
    ENABLE_ANALYTICS: bool = True
    ENABLE_WEBSOCKET: bool = True
    
    # =========================================================
    # STORAGE
    # =========================================================
    TEMP_DIR: str = str(BASE_DIR / "temp")
    RESULTS_DIR: str = str(BASE_DIR / "results")
    ENABLE_AUTO_CLEANUP: bool = True
    CLEANUP_INTERVAL_HOURS: int = 24
    
    # =========================================================
    # PERFORMANCE
    # =========================================================
    WORKERS: int = 1
    TIMEOUT: int = 300
    KEEP_ALIVE: int = 75
    
    # =========================================================
    # MONITORING
    # =========================================================
    ENABLE_PROMETHEUS: bool = False
    PROMETHEUS_PORT: int = 9090
    HEALTH_CHECK_INTERVAL: int = 60
    
    # =========================================================
    # BACKUP
    # =========================================================
    ENABLE_AUTO_BACKUP: bool = True
    BACKUP_DIR: str = str(BASE_DIR / "backups")
    BACKUP_INTERVAL_HOURS: int = 24
    BACKUP_RETENTION_DAYS: int = 30
    
    class Config:
        env_file = str(BASE_DIR / ".env")
        env_file_encoding = 'utf-8'
        case_sensitive = True
        extra = "ignore"


@lru_cache()
def get_settings() -> Settings:
    """Get cached settings instance"""
    return Settings()


def ensure_directories():
    """Create necessary directories if they don't exist"""
    settings = get_settings()
    dirs = [
        Path(settings.TEMP_DIR),
        Path(settings.RESULTS_DIR),
        Path(settings.BACKUP_DIR),
        BASE_DIR / "logs",
        BASE_DIR / "data",
    ]
    
    for directory in dirs:
        directory.mkdir(parents=True, exist_ok=True)


def get_device():
    """Determine the device to use for inference"""
    import torch
    settings = get_settings()
    
    if settings.DEVICE == "auto":
        return 0 if torch.cuda.is_available() else -1
    elif settings.DEVICE == "cpu":
        return -1
    elif settings.DEVICE == "cuda":
        return 0 if torch.cuda.is_available() else -1
    else:
        try:
            device_id = int(settings.DEVICE)
            return device_id if torch.cuda.is_available() else -1
        except ValueError:
            return -1


def get_cors_origins():
    """Parse CORS origins from settings"""
    settings = get_settings()
    origins = settings.ALLOWED_ORIGINS
    
    if origins == "*":
        return ["*"]
    
    return [origin.strip() for origin in origins.split(",")]


if __name__ == "__main__":
    # Test configuration
    ensure_directories()
    settings = get_settings()
    
    print("="*60)
    print("CONFIGURATION TEST")
    print("="*60)
    print(f"App Name: {settings.APP_NAME}")
    print(f"Version: {settings.APP_VERSION}")
    print(f"Host: {settings.HOST}:{settings.PORT}")
    print(f"Model Path: {settings.MODEL_PATH}")
    print(f"Device: {get_device()}")
    print(f"Database: {settings.DATABASE_URL}")
    print(f"Log File: {settings.LOG_FILE}")
    print(f"Max File Size: {settings.MAX_FILE_SIZE_MB}MB")
    print(f"Metrics Enabled: {settings.ENABLE_METRICS}")
    print("="*60)
