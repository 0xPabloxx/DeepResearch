#!/usr/bin/env python3
"""
Split inference results into individual files per question.
Each question gets its own directory with results from all rollouts.
"""

import json
import os
import re

# Configuration
INPUT_DIR = "/data/langgenius/DeepResearch/tests/output/Tongyi-DeepResearch-30B-A3B_sglang/bamboogle.jsonl"
OUTPUT_DIR = "/data/langgenius/DeepResearch/tests/output/split_by_question"

def sanitize_filename(text, max_length=50):
    """Create a safe filename from question text."""
    # Remove special characters
    text = re.sub(r'[^\w\s-]', '', text)
    # Replace spaces with underscores
    text = re.sub(r'\s+', '_', text)
    # Truncate
    return text[:max_length]

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Read all iter files
    iter_files = sorted([f for f in os.listdir(INPUT_DIR) if f.startswith("iter") and f.endswith(".jsonl")])

    print(f"Found {len(iter_files)} rollout files")

    # Store all data by question
    questions_data = {}

    for iter_file in iter_files:
        iter_name = iter_file.replace(".jsonl", "")  # e.g., "iter1"
        filepath = os.path.join(INPUT_DIR, iter_file)

        with open(filepath, "r", encoding="utf-8") as f:
            for idx, line in enumerate(f):
                data = json.loads(line.strip())
                question = data.get("question", f"question_{idx}")

                if question not in questions_data:
                    questions_data[question] = {
                        "index": idx,
                        "question": question,
                        "answer": data.get("answer", ""),
                        "rollouts": {}
                    }

                questions_data[question]["rollouts"][iter_name] = data

    print(f"Total questions: {len(questions_data)}")

    # Create individual files
    for question, qdata in questions_data.items():
        idx = qdata["index"]
        safe_name = sanitize_filename(question)

        # Create question directory
        q_dir = os.path.join(OUTPUT_DIR, f"{idx:03d}_{safe_name}")
        os.makedirs(q_dir, exist_ok=True)

        # Write summary file
        summary_file = os.path.join(q_dir, "summary.json")
        summary = {
            "index": idx,
            "question": qdata["question"],
            "ground_truth_answer": qdata["answer"],
            "rollout_count": len(qdata["rollouts"])
        }
        with open(summary_file, "w", encoding="utf-8") as f:
            json.dump(summary, f, ensure_ascii=False, indent=2)

        # Write each rollout
        for iter_name, data in qdata["rollouts"].items():
            rollout_file = os.path.join(q_dir, f"{iter_name}.json")
            with open(rollout_file, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"\nOutput directory: {OUTPUT_DIR}")
    print(f"Created {len(questions_data)} question directories")
    print("\nDirectory structure:")
    print("  split_by_question/")
    print("  ├── 000_question_name/")
    print("  │   ├── summary.json      # Question + ground truth")
    print("  │   ├── iter1.json        # Rollout 1 full trajectory")
    print("  │   ├── iter2.json        # Rollout 2 full trajectory")
    print("  │   └── iter3.json        # Rollout 3 full trajectory")
    print("  ├── 001_question_name/")
    print("  └── ...")

if __name__ == "__main__":
    main()
