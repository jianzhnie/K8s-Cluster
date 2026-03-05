import os
import argparse


def _discover_text_document_prefixes(
    dataset_root_dir: str,
    *,
    contains: str,
    followlinks: bool,
) -> list[str]:
    bin_bases: set[str] = set()
    idx_bases: set[str] = set()

    for dirpath, _, filenames in os.walk(dataset_root_dir, followlinks=followlinks):
        for filename in filenames:
            if contains not in filename:
                continue

            base, ext = os.path.splitext(filename)
            if ext == ".bin":
                bin_bases.add(os.path.join(dirpath, base))
            elif ext == ".idx":
                idx_bases.add(os.path.join(dirpath, base))

    return sorted(bin_bases & idx_bases)


def get_all_prefixes(
    data_dir: str,
    datasets: list[str],
    *,
    contains: str = "text_document",
    followlinks: bool = False,
) -> list[str]:
    all_prefixes: set[str] = set()
    for name in datasets:
        root_dir = os.path.join(data_dir, name)
        if not os.path.isdir(root_dir):
            continue
        all_prefixes.update(
            _discover_text_document_prefixes(
                root_dir, contains=contains, followlinks=followlinks
            )
        )
    return sorted(all_prefixes)


def write_prefixes(prefixes: list[str], output_path: str) -> None:
    output_path = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8", newline="\n") as f:
        for p in prefixes:
            f.write(p)
            f.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--data-dir",
        default="/llm_workspace_1P/fdd/workspace/workspace/datasets/C3_LVM",
    )
    parser.add_argument(
        "--datasets",
        nargs="+",
        default=["NCC", "Ncode", "Nmath", "NCC2.1"],
    )
    parser.add_argument("--contains", default="text_document")
    parser.add_argument("--followlinks", action="store_true")
    parser.add_argument(
        "--output",
        default=os.path.join(os.path.dirname(__file__), "data_prefixes.txt"),
    )
    args = parser.parse_args()

    prefixes = get_all_prefixes(
        args.data_dir,
        args.datasets,
        contains=args.contains,
        followlinks=args.followlinks,
    )
    write_prefixes(prefixes, args.output)
    print(f"count={len(prefixes)}")
    print(os.path.abspath(args.output))


if __name__ == "__main__":
    main()
