"""
Subtitle Synchronization Accuracy Evaluation Script
Evaluates subtitle timestamp accuracy and quality
"""
import os
import sys
import json
import argparse
from pathlib import Path
from typing import List, Dict, Tuple
import logging
import re

sys.path.insert(0, str(Path(__file__).parent.parent))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class SubtitleSegment:
    """Represents a subtitle segment with timestamps"""
    
    def __init__(self, index: int, start: float, end: float, text: str):
        self.index = index
        self.start = start
        self.end = end
        self.text = text
        self.duration = end - start
    
    def __repr__(self):
        return f"Segment({self.index}: {self.start:.2f}s - {self.end:.2f}s, '{self.text}')"


class SubtitleEvaluator:
    """Evaluate subtitle synchronization accuracy"""
    
    @staticmethod
    def parse_srt(srt_content: str) -> List[SubtitleSegment]:
        """Parse SRT format subtitles"""
        segments = []
        
        pattern = r'(\d+)\n(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})\n(.*?)(?=\n\n|\Z)'
        matches = re.findall(pattern, srt_content, re.DOTALL)
        
        for match in matches:
            index = int(match[0])
            start = SubtitleEvaluator._timestamp_to_seconds(match[1])
            end = SubtitleEvaluator._timestamp_to_seconds(match[2])
            text = match[3].strip()
            
            segments.append(SubtitleSegment(index, start, end, text))
        
        return segments
    
    @staticmethod
    def _timestamp_to_seconds(timestamp: str) -> float:
        """Convert SRT timestamp to seconds"""
        h, m, s = timestamp.split(':')
        s, ms = s.split(',')
        
        total_seconds = int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000
        return total_seconds
    
    @staticmethod
    def calculate_timing_error(
        predicted_segments: List[SubtitleSegment],
        reference_segments: List[SubtitleSegment]
    ) -> Dict:
        """
        Calculate timing errors between predicted and reference subtitles
        
        Returns:
            Dictionary with error metrics
        """
        if len(predicted_segments) != len(reference_segments):
            logger.warning(
                f"Segment count mismatch: predicted={len(predicted_segments)}, "
                f"reference={len(reference_segments)}"
            )
        
        start_errors = []
        end_errors = []
        duration_errors = []
        
        min_len = min(len(predicted_segments), len(reference_segments))
        
        for i in range(min_len):
            pred = predicted_segments[i]
            ref = reference_segments[i]
            
            start_error = abs(pred.start - ref.start)
            end_error = abs(pred.end - ref.end)
            duration_error = abs(pred.duration - ref.duration)
            
            start_errors.append(start_error)
            end_errors.append(end_error)
            duration_errors.append(duration_error)
        
        results = {
            "segment_count": {
                "predicted": len(predicted_segments),
                "reference": len(reference_segments),
                "matched": min_len
            },
            "start_time_error": {
                "mean": sum(start_errors) / len(start_errors) if start_errors else 0,
                "max": max(start_errors) if start_errors else 0,
                "min": min(start_errors) if start_errors else 0,
            },
            "end_time_error": {
                "mean": sum(end_errors) / len(end_errors) if end_errors else 0,
                "max": max(end_errors) if end_errors else 0,
                "min": min(end_errors) if end_errors else 0,
            },
            "duration_error": {
                "mean": sum(duration_errors) / len(duration_errors) if duration_errors else 0,
                "max": max(duration_errors) if duration_errors else 0,
            },
            "overall_timing_error": {
                "mean": (sum(start_errors) + sum(end_errors)) / (2 * len(start_errors)) if start_errors else 0,
            }
        }
        
        return results
    
    @staticmethod
    def evaluate_subtitle_quality(segments: List[SubtitleSegment]) -> Dict:
        """
        Evaluate subtitle quality metrics
        
        Returns:
            Dictionary with quality metrics
        """
        if not segments:
            return {"error": "No segments to evaluate"}
        
        durations = [seg.duration for seg in segments]
        text_lengths = [len(seg.text) for seg in segments]
        gaps = []
        
        for i in range(len(segments) - 1):
            gap = segments[i + 1].start - segments[i].end
            gaps.append(gap)
        
        reading_speeds = []
        for seg in segments:
            if seg.duration > 0:
                chars_per_second = len(seg.text) / seg.duration
                reading_speeds.append(chars_per_second)
        
        quality_issues = []
        
        avg_duration = sum(durations) / len(durations)
        if avg_duration < 1.0:
            quality_issues.append("Short average segment duration")
        if avg_duration > 10.0:
            quality_issues.append("Long average segment duration")
        
        if gaps and max(gaps) > 5.0:
            quality_issues.append("Large gaps between segments detected")
        
        if reading_speeds:
            avg_reading_speed = sum(reading_speeds) / len(reading_speeds)
            if avg_reading_speed > 25:
                quality_issues.append("Reading speed too fast")
        
        return {
            "total_segments": len(segments),
            "duration": {
                "mean": sum(durations) / len(durations),
                "min": min(durations),
                "max": max(durations),
            },
            "text_length": {
                "mean": sum(text_lengths) / len(text_lengths),
                "min": min(text_lengths),
                "max": max(text_lengths),
            },
            "gaps_between_segments": {
                "mean": sum(gaps) / len(gaps) if gaps else 0,
                "max": max(gaps) if gaps else 0,
            },
            "reading_speed_chars_per_sec": {
                "mean": sum(reading_speeds) / len(reading_speeds) if reading_speeds else 0,
            },
            "quality_issues": quality_issues,
        }


def load_srt_file(file_path: str) -> List[SubtitleSegment]:
    """Load SRT file"""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    return SubtitleEvaluator.parse_srt(content)


def main():
    parser = argparse.ArgumentParser(description='Evaluate subtitle synchronization accuracy')
    parser.add_argument('--predicted', type=str, required=True, help='Path to predicted SRT file')
    parser.add_argument('--reference', type=str, help='Path to reference SRT file (optional)')
    parser.add_argument('--output', type=str, default='subtitle_evaluation.json', help='Output file')
    parser.add_argument('--timing-threshold', type=float, default=0.2, help='Acceptable timing error in seconds')
    
    args = parser.parse_args()
    
    logger.info("="*60)
    logger.info("SUBTITLE SYNCHRONIZATION EVALUATION")
    logger.info("="*60)
    logger.info(f"Predicted: {args.predicted}")
    if args.reference:
        logger.info(f"Reference: {args.reference}")
    logger.info(f"Timing threshold: ±{args.timing_threshold}s")
    logger.info("="*60)
    
    predicted_segments = load_srt_file(args.predicted)
    logger.info(f"Loaded {len(predicted_segments)} predicted segments")
    
    results = {
        "predicted_file": args.predicted,
        "quality_metrics": SubtitleEvaluator.evaluate_subtitle_quality(predicted_segments),
    }
    
    if args.reference:
        reference_segments = load_srt_file(args.reference)
        logger.info(f"Loaded {len(reference_segments)} reference segments")
        
        timing_results = SubtitleEvaluator.calculate_timing_error(
            predicted_segments,
            reference_segments
        )
        
        results["reference_file"] = args.reference
        results["timing_accuracy"] = timing_results
        
        mean_error = timing_results["overall_timing_error"]["mean"]
        
        print("\n" + "="*60)
        print("TIMING ACCURACY RESULTS")
        print("="*60)
        print(f"Mean timing error: {mean_error:.3f}s")
        print(f"Max start error: {timing_results['start_time_error']['max']:.3f}s")
        print(f"Max end error: {timing_results['end_time_error']['max']:.3f}s")
        print("="*60)
        
        if mean_error <= args.timing_threshold:
            print(f"✅ PASSED: Mean error ≤ {args.timing_threshold}s")
        else:
            print(f"❌ FAILED: Mean error > {args.timing_threshold}s")
        
        print("="*60)
    
    print("\n" + "="*60)
    print("QUALITY METRICS")
    print("="*60)
    quality = results["quality_metrics"]
    print(f"Total segments: {quality['total_segments']}")
    print(f"Average duration: {quality['duration']['mean']:.2f}s")
    print(f"Average reading speed: {quality['reading_speed_chars_per_sec']['mean']:.1f} chars/sec")
    
    if quality['quality_issues']:
        print(f"\n⚠️  Quality issues detected:")
        for issue in quality['quality_issues']:
            print(f"  - {issue}")
    else:
        print(f"\n✅ No major quality issues detected")
    
    print("="*60)
    
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    
    logger.info(f"Results saved to: {args.output}")


if __name__ == "__main__":
    main()
