"""
Advanced Audio Processing Utilities for World-Class ASR
Implements professional-grade audio enhancement and preprocessing
"""
import numpy as np
import librosa
import soundfile as sf
from typing import Tuple, Optional
import warnings

warnings.filterwarnings("ignore")


class AudioPreprocessor:
    """
    World-class audio preprocessing pipeline for optimal ASR performance
    
    Features:
    - Noise reduction
    - Normalization to broadcast standard
    - Silence trimming
    - Dynamic range compression
    - Quality validation
    """
    
    def __init__(
        self,
        target_sr: int = 16000,
        target_db: float = -20.0,
        trim_db: float = 20.0,
        noise_reduce: bool = True
    ):
        """
        Initialize audio preprocessor
        
        Args:
            target_sr: Target sample rate (default: 16000 Hz for Whisper)
            target_db: Target loudness in dBFS (default: -20 dBFS broadcast standard)
            trim_db: Silence trimming threshold (default: 20 dB)
            noise_reduce: Enable noise reduction (requires noisereduce library)
        """
        self.target_sr = target_sr
        self.target_db = target_db
        self.trim_db = trim_db
        self.noise_reduce_enabled = noise_reduce
        
        if noise_reduce:
            try:
                import noisereduce as nr
                self.nr = nr
            except ImportError:
                print("[WARNING] noisereduce not installed. Noise reduction disabled.")
                self.noise_reduce_enabled = False
    
    def load_audio(
        self,
        audio_path: str,
        sr: Optional[int] = None,
        mono: bool = True
    ) -> Tuple[np.ndarray, int]:
        """
        Load audio file with proper resampling
        
        Args:
            audio_path: Path to audio file
            sr: Target sample rate (uses self.target_sr if None)
            mono: Convert to mono
        
        Returns:
            Tuple of (audio array, sample rate)
        """
        if sr is None:
            sr = self.target_sr
        
        try:
            audio, sample_rate = librosa.load(
                audio_path,
                sr=sr,
                mono=mono,
                res_type='kaiser_best'  # Highest quality resampling
            )
            return audio, sample_rate
        except Exception as e:
            raise ValueError(f"Failed to load audio: {str(e)}")
    
    def trim_silence(self, audio: np.ndarray) -> np.ndarray:
        """
        Remove silence from beginning and end of audio
        
        Args:
            audio: Audio array
        
        Returns:
            Trimmed audio array
        """
        audio_trimmed, _ = librosa.effects.trim(
            audio,
            top_db=self.trim_db,
            frame_length=2048,
            hop_length=512
        )
        return audio_trimmed
    
    def normalize_loudness(self, audio: np.ndarray) -> np.ndarray:
        """
        Normalize audio to target loudness (dBFS)
        
        Uses RMS normalization to broadcast standard (-20 dBFS)
        
        Args:
            audio: Audio array
        
        Returns:
            Normalized audio array
        """
        rms = np.sqrt(np.mean(audio**2))
        
        if rms < 1e-3:  # Skip normalization for nearly silent audio (-60 dBFS)
            return audio
        
        # Convert target dB to linear scale
        target_rms = 10 ** (self.target_db / 20)
        
        # Normalize
        audio_normalized = audio * (target_rms / rms)
        
        # Prevent clipping
        audio_normalized = np.clip(audio_normalized, -1.0, 1.0)
        
        return audio_normalized
    
    def reduce_noise(
        self,
        audio: np.ndarray,
        sr: int,
        stationary: bool = True
    ) -> np.ndarray:
        """
        Apply noise reduction
        
        Args:
            audio: Audio array
            sr: Sample rate
            stationary: Use stationary noise reduction (faster, for constant background noise)
        
        Returns:
            Denoised audio array
        """
        if not self.noise_reduce_enabled:
            return audio
        
        try:
            # Use first 0.5 seconds as noise profile
            noise_sample_start = 0
            noise_sample_end = min(int(0.5 * sr), len(audio))
            
            denoised = self.nr.reduce_noise(
                y=audio,
                sr=sr,
                stationary=stationary,
                prop_decrease=0.8,  # Reduce noise by 80%
                y_noise=audio[noise_sample_start:noise_sample_end]
            )
            return denoised
        except Exception as e:
            print(f"[WARNING] Noise reduction failed: {e}. Using original audio.")
            return audio
    
    def apply_compression(
        self,
        audio: np.ndarray,
        threshold: float = 0.3,
        ratio: float = 4.0
    ) -> np.ndarray:
        """
        Apply dynamic range compression
        
        Makes quiet parts louder and loud parts quieter for consistent transcription
        
        Args:
            audio: Audio array
            threshold: Compression threshold (0-1)
            ratio: Compression ratio (>1)
        
        Returns:
            Compressed audio array
        """
        # Simple soft-knee compression
        abs_audio = np.abs(audio)
        mask = abs_audio > threshold
        
        compressed = audio.copy()
        compressed[mask] = (
            threshold + (abs_audio[mask] - threshold) / ratio
        ) * np.sign(audio[mask])
        
        return compressed
    
    def validate_audio_quality(
        self,
        audio: np.ndarray,
        sr: int
    ) -> Tuple[bool, str, dict]:
        """
        Validate audio quality for ASR
        
        Args:
            audio: Audio array
            sr: Sample rate
        
        Returns:
            Tuple of (is_valid, message, metrics)
        """
        metrics = {}
        
        # Duration check
        duration = len(audio) / sr
        metrics['duration'] = round(duration, 2)
        
        if duration < 0.5:
            return False, "Audio too short (minimum 0.5s)", metrics
        
        if duration > 7200:  # 2 hours
            return False, "Audio too long (maximum 2 hours)", metrics
        
        # RMS (loudness) check
        rms = np.sqrt(np.mean(audio**2))
        metrics['rms'] = round(float(rms), 4)
        
        if rms < 0.001:
            return False, "Audio is too quiet or silent", metrics
        
        # Dynamic range check
        dynamic_range = 20 * np.log10(np.max(np.abs(audio)) / (rms + 1e-10))
        metrics['dynamic_range_db'] = round(float(dynamic_range), 2)
        
        if dynamic_range < 6:
            return False, "Audio has insufficient dynamic range", metrics
        
        # Clipping check
        clipping_ratio = np.sum(np.abs(audio) > 0.99) / len(audio)
        metrics['clipping_ratio'] = round(float(clipping_ratio), 4)
        
        if clipping_ratio > 0.01:  # More than 1% clipped
            return False, f"Audio is clipped ({clipping_ratio*100:.1f}% samples)", metrics
        
        # Zero-crossing rate (speech indicator)
        zcr = librosa.feature.zero_crossing_rate(audio)[0]
        metrics['mean_zcr'] = round(float(np.mean(zcr)), 4)
        
        # Spectral centroid (frequency content)
        spectral_centroid = librosa.feature.spectral_centroid(y=audio, sr=sr)[0]
        metrics['mean_spectral_centroid'] = round(float(np.mean(spectral_centroid)), 2)
        
        return True, "Audio quality is good", metrics
    
    def process(
        self,
        audio: np.ndarray,
        sr: int,
        apply_noise_reduction: bool = True,
        apply_compression: bool = True
    ) -> np.ndarray:
        """
        Complete preprocessing pipeline
        
        Steps:
        1. Trim silence
        2. Noise reduction (optional)
        3. Dynamic compression (optional)
        4. Normalization
        
        Args:
            audio: Audio array
            sr: Sample rate
            apply_noise_reduction: Apply noise reduction
            apply_compression: Apply dynamic compression
        
        Returns:
            Processed audio array
        """
        # Step 1: Trim silence
        audio = self.trim_silence(audio)
        
        # Step 2: Noise reduction
        if apply_noise_reduction and self.noise_reduce_enabled:
            audio = self.reduce_noise(audio, sr)
        
        # Step 3: Dynamic compression
        if apply_compression:
            audio = self.apply_compression(audio)
        
        # Step 4: Normalize loudness
        audio = self.normalize_loudness(audio)
        
        return audio
    
    def process_file(
        self,
        input_path: str,
        output_path: Optional[str] = None,
        apply_noise_reduction: bool = True,
        apply_compression: bool = True
    ) -> Tuple[np.ndarray, int, dict]:
        """
        Process audio file end-to-end
        
        Args:
            input_path: Input audio file path
            output_path: Output file path (if None, don't save)
            apply_noise_reduction: Apply noise reduction
            apply_compression: Apply dynamic compression
        
        Returns:
            Tuple of (processed audio, sample rate, quality metrics)
        """
        # Load audio
        audio, sr = self.load_audio(input_path)
        
        # Validate quality
        is_valid, message, metrics = self.validate_audio_quality(audio, sr)
        if not is_valid:
            print(f"[WARNING] Audio quality issue: {message}")
        
        # Process
        audio_processed = self.process(
            audio, sr,
            apply_noise_reduction=apply_noise_reduction,
            apply_compression=apply_compression
        )
        
        # Save if output path provided
        if output_path:
            sf.write(output_path, audio_processed, sr)
        
        return audio_processed, sr, metrics


def get_audio_metadata(audio_path: str) -> dict:
    """
    Extract comprehensive audio metadata
    
    Args:
        audio_path: Path to audio file
    
    Returns:
        Dictionary of metadata
    """
    try:
        audio, sr = librosa.load(audio_path, sr=None, mono=False)
        
        # Handle stereo/mono
        if audio.ndim > 1:
            channels = audio.shape[0]
            audio = librosa.to_mono(audio)
        else:
            channels = 1
        
        duration = len(audio) / sr
        
        return {
            "duration": round(duration, 2),
            "sample_rate": int(sr),
            "channels": channels,
            "samples": len(audio),
            "format": "wav"  # librosa always loads as wav
        }
    except Exception as e:
        return {"error": str(e)}
