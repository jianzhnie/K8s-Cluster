#!/usr/bin/env python3
"""Verify torchtitan-npu training environment on Ascend NPU."""

import sys
import os


def separator(title: str):
    print(f"\n{'='*60}")
    print(f"  {title}")
    print(f"{'='*60}")


def check_python():
    print(f"Python: {sys.version.split()[0]}")
    print(f"Path:    {sys.executable}")


def check_torch():
    try:
        import torch
        ver = torch.__version__
        print(f"[OK] torch {ver}")
        if "2.12" in ver:
            print(f"    Version 2.12.x matched")
        else:
            print(f"    [WARN] Expected 2.12.x")
        return True
    except ImportError as e:
        print(f"[FAIL] torch: {e}")
        return False


def check_torch_npu():
    try:
        import torch
        import torch_npu
        print(f"[OK] torch_npu {torch_npu.__version__}")
        try:
            available = torch_npu.npu.is_available()
            print(f"    NPU available: {available}")
            if available:
                count = torch.npu.device_count()
                print(f"    Device count: {count}")
                for i in range(min(count, 4)):
                    print(f"    NPU[{i}]: {torch.npu.get_device_name(i)}")
        except Exception as e:
            print(f"    [INFO] NPU not accessible: {e}")
        return True
    except ImportError as e:
        print(f"[FAIL] torch_npu: {e}")
        return False


def check_torchtitan():
    try:
        import torchtitan
        print(f"[OK] torchtitan installed")
        # check version
        import importlib.metadata
        ver = importlib.metadata.version("torchtitan")
        print(f"    Version: {ver}")
        return True
    except ImportError as e:
        print(f"[FAIL] torchtitan: {e}")
        return False


def check_torchtitan_npu():
    try:
        import torchtitan_npu
        ver = getattr(torchtitan_npu, "__version__", "unknown")
        print(f"[OK] torchtitan_npu {ver}")
        # verify it registered NPU models
        import torchtitan.models as titan_models
        npu_models = {"deepseek_v32", "deepseek_v4", "vlm"}
        registered = set(titan_models._supported_models)
        found = npu_models & registered
        if found:
            print(f"    NPU models registered: {sorted(found)}")
        else:
            print(f"    [WARN] NPU models not registered in torchtitan.models")
        return True
    except ImportError as e:
        print(f"[FAIL] torchtitan_npu: {e}")
        return False


def check_training_packages():
    # (import_name, display_name) pairs
    packages = [
        ("datasets", "datasets"),
        ("accelerate", "accelerate"),
        ("transformers", "transformers"),   # transitive dep of accelerate
        ("wandb", "wandb"),
        ("tensorboard", "tensorboard"),
        ("tiktoken", "tiktoken"),
        ("sentencepiece", "sentencepiece"),
        ("safetensors", "safetensors"),
        ("numpy", "numpy"),
        ("yaml", "PyYAML"),                 # package PyYAML, module yaml
        ("scipy", "scipy"),
        ("einops", "einops"),
        ("pybind11", "pybind11"),
        ("ninja", "ninja"),
    ]
    for import_name, display_name in packages:
        try:
            mod = __import__(import_name)
            ver = getattr(mod, "__version__", "installed")
            print(f"[OK] {display_name}: {ver}")
        except ImportError:
            print(f"[--] {display_name}: not installed (may be optional)")


def check_cann_env():
    vars_to_check = [
        "ASCEND_HOME_PATH",
        "ASCEND_TOOLKIT_HOME",
        "SOC_VERSION",
        "ATB_HOME_PATH",
    ]
    print("CANN Environment:")
    for v in vars_to_check:
        val = os.environ.get(v, "NOT SET")
        print(f"  {v}={val}")


def check_torchtitan_cli():
    """Verify torchtitan train entry point works."""
    try:
        # Just test import of the training entry module
        from torchtitan_npu import entry  # noqa: F401
        print(f"[OK] torchtitan_npu.entry importable")
        return True
    except Exception as e:
        print(f"[FAIL] torchtitan_npu.entry: {e}")
        return False


def main():
    print("=" * 60)
    print("  torchtitan-npu Environment Verification")
    print(f"  Image: cann9.0.0-torch2.12.0-torchtitan_npu0.2.2")
    print("=" * 60)

    check_python()

    results = {}

    separator("PyTorch + Ascend NPU Backend")
    results["torch"] = check_torch()
    results["torch_npu"] = check_torch_npu()

    separator("torchtitan Framework")
    results["torchtitan"] = check_torchtitan()
    results["torchtitan_npu"] = check_torchtitan_npu()
    results["entry"] = check_torchtitan_cli()

    separator("Training Ecosystem Packages")
    check_training_packages()

    separator("CANN Environment")
    check_cann_env()

    # Summary
    print(f"\n{'='*60}")
    print("  Summary")
    print(f"{'='*60}")
    critical = ["torch", "torch_npu", "torchtitan", "torchtitan_npu", "entry"]
    all_ok = True
    for k in critical:
        ok = results.get(k, False)
        status = "[OK]" if ok else "[FAIL]"
        if not ok:
            all_ok = False
        print(f"  {status} {k}")

    if all_ok:
        print(f"\n[PASS] torchtitan-npu training environment is ready.")
        print(f"  Run with: python -m torchtitan_npu.entry --config <config>")
        return 0
    else:
        print(f"\n[FAIL] Some checks failed. Review logs above.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
