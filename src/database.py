"""
Database Layer for Persistence
Handles transcription history, analytics, and metrics
"""
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime, Text, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime
from typing import Optional, List
import json
from pathlib import Path

from src.config import get_settings

settings = get_settings()

# Create database engine
engine = create_engine(
    settings.DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in settings.DATABASE_URL else {}
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


# =========================================================
# DATABASE MODELS
# =========================================================

class TranscriptionHistory(Base):
    """Store transcription requests and results"""
    __tablename__ = "transcription_history"
    
    id = Column(Integer, primary_key=True, index=True)
    task_id = Column(String(36), unique=True, index=True)
    filename = Column(String(255))
    file_size = Column(Integer)  # bytes
    duration = Column(Float)  # seconds
    transcription_text = Column(Text)
    word_count = Column(Integer)
    processing_time = Column(Float)  # seconds
    model_used = Column(String(100))
    device_used = Column(String(20))
    success = Column(Boolean, default=True)
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    ip_address = Column(String(45), nullable=True)
    user_agent = Column(String(255), nullable=True)


class SubtitleHistory(Base):
    """Store subtitle generation requests"""
    __tablename__ = "subtitle_history"
    
    id = Column(Integer, primary_key=True, index=True)
    task_id = Column(String(36), unique=True, index=True)
    filename = Column(String(255))
    file_size = Column(Integer)
    duration = Column(Float)
    segment_count = Column(Integer)
    format = Column(String(10))  # srt, txt
    processing_time = Column(Float)
    success = Column(Boolean, default=True)
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class APIMetrics(Base):
    """Store API performance metrics"""
    __tablename__ = "api_metrics"
    
    id = Column(Integer, primary_key=True, index=True)
    endpoint = Column(String(100))
    method = Column(String(10))
    status_code = Column(Integer)
    response_time = Column(Float)  # seconds
    timestamp = Column(DateTime, default=datetime.utcnow)


class SystemHealth(Base):
    """Store system health snapshots"""
    __tablename__ = "system_health"
    
    id = Column(Integer, primary_key=True, index=True)
    cpu_usage = Column(Float)
    memory_usage = Column(Float)
    disk_usage = Column(Float)
    active_requests = Column(Integer)
    model_loaded = Column(Boolean)
    timestamp = Column(DateTime, default=datetime.utcnow)


# =========================================================
# DATABASE OPERATIONS
# =========================================================

def init_db():
    """Initialize database and create tables"""
    Base.metadata.create_all(bind=engine)
    print("[DATABASE] Tables created successfully")


def get_db():
    """Get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# =========================================================
# CRUD OPERATIONS
# =========================================================

class TranscriptionService:
    """Service for transcription history operations"""
    
    @staticmethod
    def create(db, task_id: str, data: dict):
        """Create new transcription record"""
        record = TranscriptionHistory(
            task_id=task_id,
            filename=data.get("filename"),
            file_size=data.get("file_size"),
            duration=data.get("duration"),
            transcription_text=data.get("text"),
            word_count=data.get("word_count"),
            processing_time=data.get("processing_time"),
            model_used=data.get("model"),
            device_used=data.get("device"),
            success=data.get("success", True),
            error_message=data.get("error"),
            ip_address=data.get("ip_address"),
            user_agent=data.get("user_agent")
        )
        db.add(record)
        db.commit()
        db.refresh(record)
        return record
    
    @staticmethod
    def get_recent(db, limit: int = 100):
        """Get recent transcriptions"""
        return db.query(TranscriptionHistory)\
            .order_by(TranscriptionHistory.created_at.desc())\
            .limit(limit)\
            .all()
    
    @staticmethod
    def get_stats(db):
        """Get transcription statistics"""
        from sqlalchemy import func
        
        total = db.query(func.count(TranscriptionHistory.id)).scalar()
        successful = db.query(func.count(TranscriptionHistory.id))\
            .filter(TranscriptionHistory.success == True).scalar()
        avg_duration = db.query(func.avg(TranscriptionHistory.duration)).scalar() or 0
        avg_processing_time = db.query(func.avg(TranscriptionHistory.processing_time)).scalar() or 0
        total_words = db.query(func.sum(TranscriptionHistory.word_count)).scalar() or 0
        
        return {
            "total_transcriptions": total,
            "successful_transcriptions": successful,
            "failed_transcriptions": total - successful,
            "success_rate": (successful / total * 100) if total > 0 else 0,
            "avg_audio_duration": round(avg_duration, 2),
            "avg_processing_time": round(avg_processing_time, 2),
            "total_words_transcribed": total_words
        }


class MetricsService:
    """Service for API metrics"""
    
    @staticmethod
    def record(db, endpoint: str, method: str, status_code: int, response_time: float):
        """Record API metric"""
        metric = APIMetrics(
            endpoint=endpoint,
            method=method,
            status_code=status_code,
            response_time=response_time
        )
        db.add(metric)
        db.commit()
    
    @staticmethod
    def get_summary(db, hours: int = 24):
        """Get metrics summary for last N hours"""
        from sqlalchemy import func
        from datetime import timedelta
        
        cutoff = datetime.utcnow() - timedelta(hours=hours)
        
        total_requests = db.query(func.count(APIMetrics.id))\
            .filter(APIMetrics.timestamp >= cutoff).scalar()
        
        avg_response_time = db.query(func.avg(APIMetrics.response_time))\
            .filter(APIMetrics.timestamp >= cutoff).scalar() or 0
        
        errors = db.query(func.count(APIMetrics.id))\
            .filter(APIMetrics.timestamp >= cutoff)\
            .filter(APIMetrics.status_code >= 400).scalar()
        
        return {
            "total_requests": total_requests,
            "avg_response_time": round(avg_response_time, 3),
            "error_count": errors,
            "success_rate": ((total_requests - errors) / total_requests * 100) if total_requests > 0 else 0
        }


class HealthService:
    """Service for system health monitoring"""
    
    @staticmethod
    def record(db, cpu: float, memory: float, disk: float, active: int, model_loaded: bool):
        """Record system health snapshot"""
        health = SystemHealth(
            cpu_usage=cpu,
            memory_usage=memory,
            disk_usage=disk,
            active_requests=active,
            model_loaded=model_loaded
        )
        db.add(health)
        db.commit()
    
    @staticmethod
    def get_latest(db):
        """Get latest health snapshot"""
        return db.query(SystemHealth)\
            .order_by(SystemHealth.timestamp.desc())\
            .first()


if __name__ == "__main__":
    # Initialize database
    init_db()
    print("[DATABASE] Initialization complete")
