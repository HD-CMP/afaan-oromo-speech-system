"""
Complete Evaluation Suite
Runs both WER and subtitle evaluation as required by proposal
"""
import os
import sys
import json
import argparse
from pathlib import Path
from datetime import datetime
import logging

sys.path.insert(0, str(Path(__file__).parent.parent))

from evaluate_wer import WEREvaluator
from evaluate_subtitles import SubtitleEvaluator, load_srt_file

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def main():
    parser = argparse.ArgumentParser(
        description='Complete evaluation suite for Afaan Oromo STT system'
    )
    parser.add_argument('--model', type=str, required=True, help='Path to model')
    parser.add_argument('--wer-dataset', type=str, help='Path to WER test dataset JSON')
    parser.add_argument('--subtitle-predicted', type=str, help='Path to predicted SRT')
    parser.add_argument('--subtitle-reference', type=str, help='Path to reference SRT')
    parser.add_argument('--output-dir', type=str, default='evaluation_results', help='Output directory')
    
    args = parser.parse_args()
    
    os.makedirs(args.output_dir, exist_ok=True)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    print("="*70)
    print("AFAAN OROMO STT - COMPREHENSIVE EVALUATION")
    print("="*70)
    print(f"Model: {args.model}")
    print(f"Timestamp: {timestamp}")
    print("="*70)
    
    full_results = {
        "timestamp": timestamp,
        "model_path": args.model,
        "evaluation_type": "comprehensive",
    }
    
    if args.wer_dataset:
        print("\n" + "="*70)
        print("PHASE 1: WER EVALUATION")
        print("="*70)
        
        evaluator = WEREvaluator(args.model)
        
        with open(args.wer_dataset, 'r', encoding='utf-8') as f:
            test_data = json.load(f)
        
        audio_files = [item['audio'] for item in test_data]
        references = [item['text'] for item in test_data]
        
        wer_results = evaluator.evaluate_dataset(audio_files, references)
        
        full_results["wer_evaluation"] = wer_results
        
        print(f"\n📊 WER: {wer_results['wer_percentage']}%")
        
        clean_threshold = 0.25
        noisy_threshold = 0.35
        
        if wer_results['wer'] <= clean_threshold:
            print(f"✅ PASSED: WER ≤ {clean_threshold*100}% (Clean audio target - Proposal)")
            full_results["wer_status"] = "PASSED"
        elif wer_results['wer'] <= noisy_threshold:
            print(f"⚠️  PARTIAL: WER ≤ {noisy_threshold*100}% (Noisy audio target - Proposal)")
            full_results["wer_status"] = "PARTIAL"
        else:
            print(f"❌ FAILED: WER > {noisy_threshold*100}%")
            full_results["wer_status"] = "FAILED"
    
    if args.subtitle_predicted:
        print("\n" + "="*70)
        print("PHASE 2: SUBTITLE SYNCHRONIZATION EVALUATION")
        print("="*70)
        
        predicted_segments = load_srt_file(args.subtitle_predicted)
        
        quality_metrics = SubtitleEvaluator.evaluate_subtitle_quality(predicted_segments)
        
        subtitle_results = {
            "predicted_file": args.subtitle_predicted,
            "quality_metrics": quality_metrics,
        }
        
        if args.subtitle_reference:
            reference_segments = load_srt_file(args.subtitle_reference)
            
            timing_results = SubtitleEvaluator.calculate_timing_error(
                predicted_segments,
                reference_segments
            )
            
            subtitle_results["timing_accuracy"] = timing_results
            
            mean_error = timing_results["overall_timing_error"]["mean"]
            print(f"\n📊 Mean timing error: {mean_error:.3f}s")
            
            timing_threshold = 0.2
            if mean_error <= timing_threshold:
                print(f"✅ PASSED: Timing error ≤ {timing_threshold}s")
                subtitle_results["sync_status"] = "PASSED"
            else:
                print(f"❌ FAILED: Timing error > {timing_threshold}s")
                subtitle_results["sync_status"] = "FAILED"
        
        full_results["subtitle_evaluation"] = subtitle_results
        
        print(f"\n📊 Total segments: {quality_metrics['total_segments']}")
        print(f"📊 Avg duration: {quality_metrics['duration']['mean']:.2f}s")
        
        if quality_metrics['quality_issues']:
            print(f"\n⚠️  Quality issues:")
            for issue in quality_metrics['quality_issues']:
                print(f"  - {issue}")
    
    print("\n" + "="*70)
    print("FINAL SUMMARY")
    print("="*70)
    
    if "wer_evaluation" in full_results:
        print(f"WER: {full_results['wer_evaluation']['wer_percentage']}% - {full_results.get('wer_status', 'N/A')}")
    
    if "subtitle_evaluation" in full_results:
        if "timing_accuracy" in full_results["subtitle_evaluation"]:
            timing_err = full_results["subtitle_evaluation"]["timing_accuracy"]["overall_timing_error"]["mean"]
            print(f"Subtitle sync: {timing_err:.3f}s - {full_results['subtitle_evaluation'].get('sync_status', 'N/A')}")
        print(f"Subtitle quality: {len(full_results['subtitle_evaluation']['quality_metrics']['quality_issues'])} issues")
    
    print("="*70)
    
    output_file = os.path.join(args.output_dir, f"evaluation_{timestamp}.json")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(full_results, f, indent=2, ensure_ascii=False)
    
    print(f"\n✅ Full results saved to: {output_file}")


if __name__ == "__main__":
    main()
