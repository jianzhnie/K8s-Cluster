#!/usr/bin/env python3
import sys
import os
import argparse
import torch
from safetensors import safe_open


def compare_safetensors(file1_path, file2_path, tolerance=1e-5, verbose=False):
    """
    Compare two safetensors files and report differences.
    Uses safe_open for memory-efficient loading.
    """
    if not os.path.exists(file1_path):
        print(f"Error: File not found: {file1_path}")
        sys.exit(1)
    if not os.path.exists(file2_path):
        print(f"Error: File not found: {file2_path}")
        sys.exit(1)

    print(f"Comparing:\n  File 1: {file1_path}\n  File 2: {file2_path}")

    try:
        # Open files context managers
        f1 = safe_open(file1_path, framework="pt", device="cpu")
        f2 = safe_open(file2_path, framework="pt", device="cpu")
    except Exception as e:
        print(f"Error opening safetensors files: {e}")
        sys.exit(1)

    keys1 = set(f1.keys())
    keys2 = set(f2.keys())

    # Check for missing keys
    missing_in_2 = keys1 - keys2
    missing_in_1 = keys2 - keys1

    if missing_in_2:
        print(f"\nKeys present in File 1 but missing in File 2 ({len(missing_in_2)}):")
        for k in sorted(list(missing_in_2))[:10]:
            print(f"  - {k}")
        if len(missing_in_2) > 10:
            print(f"  ... and {len(missing_in_2) - 10} more.")

    if missing_in_1:
        print(f"\nKeys present in File 2 but missing in File 1 ({len(missing_in_1)}):")
        for k in sorted(list(missing_in_1))[:10]:
            print(f"  - {k}")
        if len(missing_in_1) > 10:
            print(f"  ... and {len(missing_in_1) - 10} more.")

    common_keys = keys1.intersection(keys2)
    print(f"\nComparing {len(common_keys)} common tensors...")

    diff_count = 0
    checked_count = 0

    for key in sorted(list(common_keys)):
        # Load tensors only when needed (memory efficient)
        tensor1 = f1.get_tensor(key)
        tensor2 = f2.get_tensor(key)
        checked_count += 1

        # Check shape
        if tensor1.shape != tensor2.shape:
            print(f"\n[MISMATCH] Shape mismatch for '{key}':")
            print(f"  File 1: {tensor1.shape}")
            print(f"  File 2: {tensor2.shape}")
            diff_count += 1
            continue

        # Check dtype
        if tensor1.dtype != tensor2.dtype:
            print(f"\n[MISMATCH] Dtype mismatch for '{key}':")
            print(f"  File 1: {tensor1.dtype}")
            print(f"  File 2: {tensor2.dtype}")
            diff_count += 1
            continue

        # Check values
        if not torch.allclose(tensor1, tensor2, atol=tolerance, rtol=tolerance):
            diff = (tensor1 - tensor2).abs()
            max_diff = diff.max().item()
            mean_diff = diff.mean().item()
            print(f"\n[MISMATCH] Value mismatch for '{key}':")
            print(f"  Max diff: {max_diff:.6e}")
            print(f"  Mean diff: {mean_diff:.6e}")
            diff_count += 1
        elif verbose:
            print(f"[OK] {key}")

    print("\n" + "=" * 50)
    print("Comparison Summary:")
    print(f"  Total keys checked: {checked_count}")
    print(f"  Mismatched tensors: {diff_count}")
    if missing_in_1 or missing_in_2:
        print(f"  Missing keys: {len(missing_in_1) + len(missing_in_2)}")

    if diff_count == 0 and not missing_in_1 and not missing_in_2:
        print("\nSUCCESS: Files are identical!")
        sys.exit(0)
    else:
        print("\nFAILURE: Files differ.")
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Compare two safetensors files.")
    parser.add_argument("--source", required=True, help="Path to the source safetensors file")
    parser.add_argument("--target", required=True, help="Path to the target safetensors file")
    parser.add_argument("--tolerance", type=float, default=1e-5, help="Tolerance for floating point comparison (default: 1e-5)")
    parser.add_argument("--verbose", action="store_true", help="Print details for matching tensors too")

    args = parser.parse_args()

    compare_safetensors(args.source, args.target, args.tolerance, args.verbose)
