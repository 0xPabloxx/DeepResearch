#!/usr/bin/env python3
"""
Split inference results into readable markdown files per question.
"""

import json
import os
import re

INPUT_DIR = "/data/langgenius/DeepResearch/tests/output/Tongyi-DeepResearch-30B-A3B_sglang/bamboogle.jsonl"
OUTPUT_DIR = "/data/langgenius/DeepResearch/tests/output/split_readable"

def sanitize_filename(text, max_length=50):
    text = re.sub(r'[^\w\s-]', '', text)
    text = re.sub(r'\s+', '_', text)
    return text[:max_length]

def format_message(msg, idx):
    """Format a single message for markdown."""
    role = msg.get("role", "unknown")
    content = msg.get("content", "")

    role_emoji = {
        "system": "⚙️ System",
        "user": "👤 User",
        "assistant": "🤖 Assistant"
    }.get(role, role)

    lines = [f"### {idx}. {role_emoji}\n"]

    # Truncate very long system prompts
    if role == "system" and len(content) > 500:
        lines.append("```")
        lines.append(content[:500] + "\n... [truncated]")
        lines.append("```\n")
    else:
        lines.append(content + "\n")

    return "\n".join(lines)

def format_trajectory(data):
    """Format full trajectory as markdown."""
    lines = []

    # Header
    question = data.get("question", "N/A")
    answer = data.get("answer", "N/A")
    prediction = data.get("prediction", "N/A")

    lines.append(f"# Question\n\n{question}\n")
    lines.append(f"# Ground Truth Answer\n\n{answer}\n")
    lines.append(f"# Model Prediction\n\n{prediction}\n")
    lines.append("---\n")
    lines.append("# Conversation Trajectory\n")

    # Messages
    messages = data.get("messages", [])
    for idx, msg in enumerate(messages, 1):
        lines.append(format_message(msg, idx))
        lines.append("---\n")

    return "\n".join(lines)

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    iter_files = sorted([f for f in os.listdir(INPUT_DIR) if f.startswith("iter") and f.endswith(".jsonl")])
    print(f"Found {len(iter_files)} rollout files")

    questions_data = {}

    for iter_file in iter_files:
        iter_name = iter_file.replace(".jsonl", "")
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

    for question, qdata in questions_data.items():
        idx = qdata["index"]
        safe_name = sanitize_filename(question)

        q_dir = os.path.join(OUTPUT_DIR, f"{idx:03d}_{safe_name}")
        os.makedirs(q_dir, exist_ok=True)

        # Write summary
        summary_file = os.path.join(q_dir, "README.md")
        with open(summary_file, "w", encoding="utf-8") as f:
            f.write(f"# Question {idx}\n\n")
            f.write(f"**Question:** {qdata['question']}\n\n")
            f.write(f"**Ground Truth:** {qdata['answer']}\n\n")
            f.write("## Rollouts\n\n")
            for iter_name in sorted(qdata["rollouts"].keys()):
                f.write(f"- [{iter_name}.md]({iter_name}.md)\n")

        # Write each rollout as markdown
        for iter_name, data in qdata["rollouts"].items():
            md_file = os.path.join(q_dir, f"{iter_name}.md")
            with open(md_file, "w", encoding="utf-8") as f:
                f.write(format_trajectory(data))

            # Also keep JSON for reference
            json_file = os.path.join(q_dir, f"{iter_name}.json")
            with open(json_file, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"\nOutput: {OUTPUT_DIR}")
    print(f"Created {len(questions_data)} question directories")
    print("\nEach directory contains:")
    print("  - README.md     (summary)")
    print("  - iter1.md      (readable trajectory)")
    print("  - iter1.json    (raw data)")
    print("  - iter2.md/json")
    print("  - iter3.md/json")

if __name__ == "__main__":
    main()
