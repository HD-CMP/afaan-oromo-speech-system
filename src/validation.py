"""
Enhanced Input Validation Module
Comprehensive validation for audio files, parameters, and requests
"""
import os
import magic
import librosa
import numpy as np
from pathlib import Path
from typing import Tuple, Optional, Dict, Any
import logging

from src.config import get_settings

settings = get_settings()
logger = logging.getLogger(__name__)


class ValidationError(Exception):
    """Custom validation error"""
    pass


class AudioValidator:
    """Comprehensive audio file validator"""
    
    ALLOWED_EXTENSIONS = {
        '.wav', '.mp3', '.m4a', '.flac', '.ogg', 
        '.opus', '.wma', '.aac', '.webm'
    }
    
    ALLOWED_MIME_TYPES = {
        'audio/wav', 'audio/wave', 'audio/x-wav',
        'audio/mpeg', 'audio/mp3',
        'audio/mp4', 'audio/m4a', 'audio/x-m4a',
        'audio/flac', 'audio/x-flac',
        'audio/ogg', 'audio/opus',
        'audio/webm',
        'audio/x-ms-wma',
        'audio/aac',
    }
    
    MIN_DURATION = 0.5
    MAX_DURATION = 7200
    MIN_SAMPLE_RATE = 8000
    MAX_SAMPLE_RATE = 48000
    MIN_RMS = 0.001
    
    @classmethod
    def validate_file_path(cls, file_path: str) -> Tuple[bool, str]:
        """Validate file existence and path"""
        if not file_path:
            return False, "File path is empty"
        
        if not os.path.exists(file_path):
            return False, "File not found"
        
        if not os.path.isfile(file_path):
            return False, "Path is not a file"
        
        if len(file_path) > 4096:
            return False, "File path too long"
        
        return True, "Valid"
    
    @classmethod
    def validate_file_extension(cls, file_path: str) -> Tuple[bool, str]:
        """Validate file extension"""
        ext = Path(file_path).suffix.lower()
        
        if not ext:
            return False, "File has no extension"
        
        if ext not in cls.ALLOWED_EXTENSIONS:
            return False, f"Invalid extension '{ext}'. Allowed: {', '.join(cls.ALLOWED_EXTENSIONS)}"
        
        return True, "Valid"
    
    @classmethod
    def validate_file_size(cls, file_path: str) -> Tuple[bool, str]:
        """Validate file size"""
        try:
            size = os.path.getsize(file_path)
            
            if size < 1024:
                return False, "File too small (min 1KB)"
            
            if size > settings.MAX_FILE_SIZE:
                max_mb = settings.MAX_FILE_SIZE_MB
                return False, f"File too large (max {max_mb}MB)"
            
            return True, "Valid"
        except Exception as e:
            return False, f"Size check error: {str(e)}"
    
    @classmethod
    def validate_mime_type(cls, file_path: str) -> Tuple[bool, str]:
        """Validate MIME type using python-magic"""
        try:
            mime = magic.Magic(mime=True)
            file_mime = mime.from_file(file_path)
            
            if file_mime not in cls.ALLOWED_MIME_TYPES:
                return False, f"Invalid MIME type '{file_mime}'"
            
            return True, "Valid"
        except Exception as e:
            logger.warning(f"MIME validation skipped: {e}")
            return True, "MIME check skipped"
    
    @classmethod
    def validate_audio_content(cls, file_path: str) -> Tuple[bool, str]:
        """Validate actual audio content"""
        try:
            audio, sr = librosa.load(file_path, sr=16000, mono=True, duration=10)
            
            if len(audio) == 0:
                return False, "Audio file is empty"
            
            duration = len(audio) / sr
            
            if duration < cls.MIN_DURATION:
                return False, f"Audio too short (min {cls.MIN_DURATION}s)"
            
            full_duration = librosa.get_duration(path=file_path)
            if full_duration > cls.MAX_DURATION:
                max_min = cls.MAX_DURATION / 60
                return False, f"Audio too long (max {max_min} minutes)"
            
            rms = np.sqrt(np.mean(audio**2))
            if rms < cls.MIN_RMS:
                return False, "Audio appears to be silent or corrupted"
            
            if not np.isfinite(audio).all():
                return False, "Audio contains invalid values (NaN/Inf)"
            
            return True, "Valid"
            
        except Exception as e:
            return False, f"Audio validation error: {str(e)[:100]}"
    
    @classmethod
    def validate_audio_quality(cls, file_path: str) -> Dict[str, Any]:
        """Get detailed audio quality metrics"""
        try:
            audio, sr = librosa.load(file_path, sr=None, mono=True, duration=30)
            
            duration = len(audio) / sr
            rms = np.sqrt(np.mean(audio**2))
            peak = np.max(np.abs(audio))
            zero_crossings = np.sum(np.abs(np.diff(np.sign(audio)))) / 2
            zcr = zero_crossings / len(audio)
            
            snr_estimate = 20 * np.log10(rms / (np.std(audio) + 1e-10))
            
            quality_score = 100
            warnings = []
            
            if rms < 0.01:
                quality_score -= 30
                warnings.append("Very low volume")
            elif rms < 0.05:
                quality_score -= 10
                warnings.append("Low volume")
            
            if peak > 0.95:
                quality_score -= 20
                warnings.append("Possible clipping detected")
            
            if zcr > 0.3:
                quality_score -= 15
                warnings.append("High noise level")
            
            if sr < 16000:
                quality_score -= 10
                warnings.append("Low sample rate")
            
            return {
                "valid": True,
                "quality_score": max(0, quality_score),
                "duration": round(duration, 2),
                "sample_rate": sr,
                "rms": round(float(rms), 4),
                "peak": round(float(peak), 4),
                "snr_estimate": round(float(snr_estimate), 2),
                "warnings": warnings,
            }
        except Exception as e:
            return {
                "valid": False,
                "error": str(e)[:200]
            }
    
    @classmethod
    def validate_complete(cls, file_path: str) -> Tuple[bool, str, Optional[Dict]]:
        """Run all validations"""
        validations = [
            ("Path", cls.validate_file_path),
            ("Extension", cls.validate_file_extension),
            ("Size", cls.validate_file_size),
            ("Content", cls.validate_audio_content),
        ]
        
        for name, validator in validations:
            is_valid, message = validator(file_path)
            if not is_valid:
                logger.warning(f"Validation failed [{name}]: {message}")
                return False, message, None
        
        quality_info = cls.validate_audio_quality(file_path)
        
        return True, "All validations passed", quality_info


class SubtitleValidator:
    """Validator for subtitle generation requests"""
    
    ALLOWED_FORMATS = {'srt', 'txt', 'vtt'}
    
    @classmethod
    def validate_format(cls, format_str: str) -> Tuple[bool, str]:
        """Validate subtitle format"""
        if not format_str:
            return False, "Format not specified"
        
        format_str = format_str.lower().strip()
        
        if format_str not in cls.ALLOWED_FORMATS:
            return False, f"Invalid format. Allowed: {', '.join(cls.ALLOWED_FORMATS)}"
        
        return True, "Valid"


class RequestValidator:
    """Validator for API request parameters"""
    
    @classmethod
    def validate_task_id(cls, task_id: str) -> Tuple[bool, str]:
        """Validate task ID format"""
        if not task_id:
            return False, "Task ID is empty"
        
        if len(task_id) > 100:
            return False, "Task ID too long"
        
        if not task_id.replace('-', '').replace('_', '').isalnum():
            return False, "Task ID contains invalid characters"
        
        return True, "Valid"
    
    @classmethod
    def validate_language_code(cls, lang_code: str) -> Tuple[bool, str]:
        """Validate language code"""
        valid_codes = {'orm', 'en', 'so', 'am', 'sw'}
        
        if not lang_code:
            return False, "Language code is empty"
        
        if lang_code not in valid_codes:
            return False, f"Invalid language. Supported: {', '.join(valid_codes)}"
        
        return True, "Valid"


def validate_upload_request(
    file_path: str,
    format: Optional[str] = None,
    language: Optional[str] = None
) -> Tuple[bool, str, Optional[Dict]]:
    """
    Comprehensive validation for upload requests
    
    Returns:
        (is_valid, error_message, quality_info)
    """
    is_valid, message, quality_info = AudioValidator.validate_complete(file_path)
    
    if not is_valid:
        return False, message, None
    
    if format:
        is_valid, message = SubtitleValidator.validate_format(format)
        if not is_valid:
            return False, message, quality_info
    
    if language:
        is_valid, message = RequestValidator.validate_language_code(language)
        if not is_valid:
            return False, message, quality_info
    
    return True, "Validation successful", quality_info


if __name__ == "__main__":
    print("="*60)
    print("VALIDATION MODULE TEST")
    print("="*60)
    
    test_file = "test.wav"
    if os.path.exists(test_file):
        is_valid, message, quality = validate_upload_request(test_file)
        print(f"Valid: {is_valid}")
        print(f"Message: {message}")
        if quality:
            print(f"Quality Score: {quality.get('quality_score', 'N/A')}")
            print(f"Warnings: {quality.get('warnings', [])}")
    else:
        print("No test file found")
    
    print("="*60)
