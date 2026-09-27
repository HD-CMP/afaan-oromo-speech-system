"""
WER (Word Error Rate) Evaluation Script
Evaluates transcription accuracy against reference texts
"""
import os
import sys
import json
import argparse
from pathlib import Path
from typing import List, Dict, Tuple
import logging

sys.path.insert(0, str(Path(__file__).parent.parent))

from jiwer import wer, cer, mer, wil
from transformers import pipeline
import torch
from tqdm import tqdm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class WEREvaluator:
    """Evaluate WER for Afaan Oromo ASR model"""
    
    def __init__(self, model_path: str):
        """
        Initialize evaluator
        
        Args:
            model_path: Path to the fine-tuned model
        """
        logger.info(f"Loading model from: {model_path}")
        
        device = 0 if torch.cuda.is_available() else -1
        
        self.pipeline = pipeline(
            "automatic-speech-recognition",
            model=model_path,
            device=device,
            return_timestamps=True,
            chunk_length_s=30
        )
        
        logger.info(f"Model loaded on: {'GPU' if device >= 0 else 'CPU'}")
    
    def transcribe_file(self, audio_path: str) -> str:
        """Transcribe a single audio file"""
        try:
            result = self.pipeline(audio_path)
            return result["text"].strip()
        except Exception as e:
            logger.error(f"Transcription failed for {audio_path}: {e}")
            return ""
    
    def evaluate_dataset(
        self,
        audio_files: List[str],
        reference_texts: List[str]
    ) -> Dict:
        """
        Evaluate WER on a dataset
        
        Args:
            audio_files: List of audio file paths
            reference_texts: List of reference transcriptions
        
        Returns:
            Dictionary with evaluation metrics
        """
        if len(audio_files) != len(reference_texts):
            raise ValueError("Number of audio files must match number of references")
        
        predictions = []
        references = []
        
        logger.info(f"Evaluating {len(audio_files)} files...")
        
        for audio_path, reference in tqdm(zip(audio_files, reference_texts), total=len(audio_files)):
            if not os.path.exists(audio_path):
                logger.warning(f"File not found: {audio_path}")
                continue
            
            prediction = self.transcribe_file(audio_path)
            
            predictions.append(prediction)
            references.append(reference)
        
        wer_score = wer(references, predictions)
        cer_score = cer(references, predictions)
        mer_score = mer(references, predictions)
        wil_score = wil(references, predictions)
        
        results = {
            "total_samples": len(predictions),
            "wer": round(wer_score, 4),
            "wer_percentage": round(wer_score * 100, 2),
            "cer": round(cer_score, 4),
            "mer": round(mer_score, 4),
            "wil": round(wil_score, 4),
            "predictions": predictions,
            "references": references,
        }
        
        logger.info(f"WER: {results['wer_percentage']}%")
        logger.info(f"CER: {round(cer_score * 100, 2)}%")
        
        return results
    
    def evaluate_with_categories(
        self,
        dataset: Dict[str, List[Tuple[str, str]]]
    ) -> Dict:
        """
        Evaluate with different audio categories (clean, noisy, etc.)
        
        Args:
            dataset: Dictionary mapping category name to list of (audio_path, reference) tuples
        
        Returns:
            Dictionary with per-category and overall results
        """
        all_results = {}
        
        for category, samples in dataset.items():
            logger.info(f"\n{'='*60}")
            logger.info(f"Evaluating category: {category}")
            logger.info(f"{'='*60}")
            
            audio_files = [s[0] for s in samples]
            references = [s[1] for s in samples]
            
            results = self.evaluate_dataset(audio_files, references)
            all_results[category] = results
        
        overall_predictions = []
        overall_references = []
        
        for category_results in all_results.values():
            overall_predictions.extend(category_results['predictions'])
            overall_references.extend(category_results['references'])
        
        overall_wer = wer(overall_references, overall_predictions)
        
        all_results['overall'] = {
            "total_samples": len(overall_predictions),
            "wer": round(overall_wer, 4),
            "wer_percentage": round(overall_wer * 100, 2),
        }
        
        return all_results


def load_test_dataset(dataset_path: str) -> List[Tuple[str, str]]:
    """
    Load test dataset from JSON file
    
    Expected format:
    [
        {"audio": "path/to/audio.wav", "text": "reference transcription"},
        ...
    ]
    """
    with open(dataset_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    return [(item['audio'], item['text']) for item in data]


def main():
    parser = argparse.ArgumentParser(description='Evaluate WER for Afaan Oromo ASR')
    parser.add_argument('--model', type=str, required=True, help='Path to model')
    parser.add_argument('--dataset', type=str, required=True, help='Path to test dataset JSON')
    parser.add_argument('--output', type=str, default='evaluation_results.json', help='Output file')
    parser.add_argument('--clean-threshold', type=float, default=0.25, help='WER threshold for clean audio (proposal: ≤25%)')
    parser.add_argument('--noisy-threshold', type=float, default=0.35, help='WER threshold for noisy audio (proposal: ≤35%)')
    
    args = parser.parse_args()
    
    logger.info("="*60)
    logger.info("AFAAN OROMO ASR - WER EVALUATION")
    logger.info("="*60)
    logger.info(f"Model: {args.model}")
    logger.info(f"Dataset: {args.dataset}")
    logger.info(f"Clean audio target: ≤{args.clean_threshold*100}%")
    logger.info(f"Noisy audio target: ≤{args.noisy_threshold*100}%")
    logger.info("="*60)
    
    evaluator = WEREvaluator(args.model)
    
    test_data = load_test_dataset(args.dataset)
    logger.info(f"Loaded {len(test_data)} test samples")
    
    audio_files = [item[0] for item in test_data]
    references = [item[1] for item in test_data]
    
    results = evaluator.evaluate_dataset(audio_files, references)
    
    print("\n" + "="*60)
    print("EVALUATION RESULTS")
    print("="*60)
    print(f"Total Samples: {results['total_samples']}")
    print(f"WER: {results['wer_percentage']}%")
    print(f"CER: {round(results['cer'] * 100, 2)}%")
    print(f"MER: {round(results['mer'] * 100, 2)}%")
    print(f"WIL: {round(results['wil'] * 100, 2)}%")
    print("="*60)
    
    if results['wer'] <= args.clean_threshold:
        print(f"✅ PASSED: WER ≤ {args.clean_threshold*100}% (Clean audio target)")
    else:
        print(f"❌ FAILED: WER > {args.clean_threshold*100}% (Clean audio target)")
    
    print("="*60)
    
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    
    logger.info(f"Results saved to: {args.output}")


if __name__ == "__main__":
    main()
