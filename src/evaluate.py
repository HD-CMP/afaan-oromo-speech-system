"""
WER (Word Error Rate) Evaluation Module for Afaan Oromo ASR
Evaluates model performance on test datasets
"""

import torch
from transformers import pipeline
import librosa
import numpy as np
import warnings
import json
from pathlib import Path
from datetime import datetime
import jiwer
from typing import List, Dict, Tuple

warnings.filterwarnings("ignore")

# =========================================================
# CONFIGURATION
# =========================================================
MODEL_PATH = r"C:\Users\hp\Desktop\oromo_asr_backend\Whisper_Merged_FP16"
device = 0 if torch.cuda.is_available() else -1

# =========================================================
# LOAD MODEL
# =========================================================
print("="*70)
print("WER EVALUATION FOR AFAAN OROMO ASR")
print("="*70)
print(f"\nLoading model: {MODEL_PATH}")
print(f"Device: {'GPU (CUDA)' if device == 0 else 'CPU'}")

try:
    asr_pipeline = pipeline(
        "automatic-speech-recognition",
        model=MODEL_PATH,
        device=device,
        return_timestamps=True,
        chunk_length_s=30
    )
    print("[SUCCESS] Model loaded successfully!\n")
except Exception as e:
    print(f"[ERROR] Error loading model: {e}")
    exit(1)

# =========================================================
# UTILITY FUNCTIONS
# =========================================================
def preprocess_audio(audio, sr=16000):
    """Preprocess audio for optimal ASR performance"""
    # Trim silence
    audio, _ = librosa.effects.trim(audio, top_db=20)
    
    # Normalize to -20 dBFS
    rms = np.sqrt(np.mean(audio**2))
    if rms > 1e-3:  # Skip normalization for nearly silent audio
        target_rms = 10**(-20/20)
        audio = audio * (target_rms / rms)
    
    # Clip
    audio = np.clip(audio, -1.0, 1.0)
    return audio

def transcribe_audio(audio_path: str) -> str:
    """Transcribe audio file and return text"""
    try:
        # Load audio
        audio, sr = librosa.load(audio_path, sr=16000, mono=True)
        audio = preprocess_audio(audio, sr)
        
        # Transcribe
        result = asr_pipeline(
            {"array": audio, "sampling_rate": sr},
            return_timestamps=False,
            chunk_length_s=30,
            batch_size=16 if device == 0 else 1,
            generate_kwargs={
                "num_beams": 5,
                "max_length": 225,
                "temperature": 0.0,
                "compression_ratio_threshold": 2.4,
                "logprob_threshold": -1.0,
                "no_speech_threshold": 0.6,
            }
        )
        
        return result["text"].strip()
    
    except Exception as e:
        print(f"Error transcribing {audio_path}: {e}")
        return ""

def normalize_text(text: str) -> str:
    """Normalize text for WER calculation"""
    # Convert to lowercase
    text = text.lower()
    
    # Remove punctuation
    import string
    text = text.translate(str.maketrans('', '', string.punctuation))
    
    # Remove extra whitespace
    text = " ".join(text.split())
    
    return text

def calculate_wer(reference: str, hypothesis: str) -> float:
    """Calculate Word Error Rate"""
    ref_normalized = normalize_text(reference)
    hyp_normalized = normalize_text(hypothesis)
    
    if not ref_normalized:
        return 0.0
    
    wer = jiwer.wer(ref_normalized, hyp_normalized)
    return wer * 100  # Return as percentage

def evaluate_dataset(test_cases: List[Dict[str, str]]) -> Dict:
    """
    Evaluate model on test dataset
    
    Args:
        test_cases: List of dicts with 'audio_path' and 'reference_text'
    
    Returns:
        Evaluation results dictionary
    """
    results = []
    total_wer = 0.0
    successful = 0
    
    print(f"\nEvaluating {len(test_cases)} test cases...\n")
    print("-"*70)
    
    for i, test_case in enumerate(test_cases, 1):
        audio_path = test_case.get("audio_path")
        reference = test_case.get("reference_text", "")
        
        if not audio_path or not Path(audio_path).exists():
            print(f"[{i}/{len(test_cases)}] SKIP: File not found - {audio_path}")
            continue
        
        print(f"[{i}/{len(test_cases)}] Processing: {Path(audio_path).name}")
        
        # Transcribe
        hypothesis = transcribe_audio(audio_path)
        
        if not hypothesis:
            print(f"           ERROR: Transcription failed")
            continue
        
        # Calculate WER
        wer = calculate_wer(reference, hypothesis)
        
        # Store result
        result = {
            "file": Path(audio_path).name,
            "reference": reference,
            "hypothesis": hypothesis,
            "wer": round(wer, 2)
        }
        results.append(result)
        
        total_wer += wer
        successful += 1
        
        # Print result
        print(f"           REF: {reference[:60]}{'...' if len(reference) > 60 else ''}")
        print(f"           HYP: {hypothesis[:60]}{'...' if len(hypothesis) > 60 else ''}")
        print(f"           WER: {wer:.2f}%")
        print("-"*70)
    
    # Calculate corpus-level WER and CER
    all_refs = [normalize_text(r["reference"]) for r in results if r["reference"]]
    all_hyps = [normalize_text(r["hypothesis"]) for r in results if r["hypothesis"]]
    
    if all_refs and all_hyps and len(all_refs) == len(all_hyps):
        corpus_wer = jiwer.wer(all_refs, all_hyps) * 100
        corpus_cer = jiwer.cer(all_refs, all_hyps) * 100
    else:
        corpus_wer = 0.0
        corpus_cer = 0.0
    
    summary = {
        "total_files": len(test_cases),
        "successful": successful,
        "failed": len(test_cases) - successful,
        "corpus_wer": round(corpus_wer, 2),
        "corpus_cer": round(corpus_cer, 2),
        "per_sentence_avg_wer": round(total_wer / successful, 2) if successful > 0 else 0.0,
        "results": results,
        "timestamp": datetime.now().isoformat(),
        "device": "GPU" if device == 0 else "CPU",
        "model": MODEL_PATH
    }
    
    return summary

def print_summary(summary: Dict):
    """Print evaluation summary"""
    print("\n" + "="*70)
    print("EVALUATION SUMMARY")
    print("="*70)
    print(f"Total test files:    {summary['total_files']}")
    print(f"Successfully tested: {summary['successful']}")
    print(f"Failed:              {summary['failed']}")
    print(f"\n{'='*70}")
    print(f"CORPUS WER:          {summary['corpus_wer']:.2f}%")
    print(f"CORPUS CER:          {summary['corpus_cer']:.2f}%")
    print(f"{'='*70}")
    
    # Performance interpretation
    avg_wer = summary['corpus_wer']
    if avg_wer <= 10:
        status = "EXCELLENT"
    elif avg_wer <= 25:
        status = "GOOD (Target achieved!)"
    elif avg_wer <= 35:
        status = "ACCEPTABLE (Within noisy audio target)"
    else:
        status = "NEEDS IMPROVEMENT"
    
    print(f"\nPerformance: {status}\n")
    
    # Target comparison
    print("Project Targets:")
    print("  - Clean audio: WER <= 25% [PASS]" if avg_wer <= 25 else "  - Clean audio: WER <= 25% [FAIL]")
    print("  - Noisy audio: WER <= 35% [PASS]" if avg_wer <= 35 else "  - Noisy audio: WER <= 35% [FAIL]")
    print()

def save_results(summary: Dict, output_path: str = "evaluation_results.json"):
    """Save evaluation results to JSON file"""
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)
    print(f"Results saved to: {output_path}\n")

# =========================================================
# MAIN EVALUATION
# =========================================================
if __name__ == "__main__":
    # Example test cases - Replace with actual test data
    # Format: {'audio_path': 'path/to/audio.wav', 'reference_text': 'Ground truth text'}
    
    test_cases = [
        # Add your test cases here
        # Example:
        # {
        #     "audio_path": "test_data/sample1.wav",
        #     "reference_text": "Afaan Oromoo seenaa dheeraa qaba"
        # },
        # {
        #     "audio_path": "test_data/sample2.wav",
        #     "reference_text": "Barnoota barbaachisaa dha"
        # }
    ]
    
    # Check if test cases are provided
    if not test_cases:
        print("\n" + "="*70)
        print("WARNING: No test cases defined!")
        print("="*70)
        print("\nTo evaluate the model, please:")
        print("1. Prepare audio files with ground truth transcriptions")
        print("2. Add them to the 'test_cases' list in this script")
        print("3. Format: {'audio_path': 'file.wav', 'reference_text': 'text'}")
        print("\nExample usage:")
        print("""
test_cases = [
    {
        "audio_path": "test_audio/sample1.wav",
        "reference_text": "Afaan Oromoo seenaa dheeraa qaba"
    },
    {
        "audio_path": "test_audio/sample2.wav",
        "reference_text": "Barnoota barbaachisaa dha"
    }
]
        """)
        print("\nAlternatively, provide a dataset directory:")
        print("python evaluate.py --dataset path/to/test_dataset")
        print()
        
        # Create sample result for demonstration
        print("Creating DEMO evaluation result...\n")
        demo_summary = {
            "total_files": 0,
            "successful": 0,
            "failed": 0,
            "corpus_wer": 0.0,
            "corpus_cer": 0.0,
            "per_sentence_avg_wer": 0.0,
            "results": [],
            "timestamp": datetime.now().isoformat(),
            "device": "GPU" if device == 0 else "CPU",
            "model": MODEL_PATH,
            "note": "Demo evaluation - no test data provided"
        }
        save_results(demo_summary, "evaluation_results_demo.json")
        print("To perform actual evaluation, add test cases as described above.")
        exit(0)
    
    # Run evaluation
    summary = evaluate_dataset(test_cases)
    
    # Print summary
    print_summary(summary)
    
    # Save results
    save_results(summary)
    
    print("="*70)
    print("EVALUATION COMPLETE")
    print("="*70)
