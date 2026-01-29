#!/usr/bin/env python3
"""Submit a forecast to the flu-metrocast hub.

This script:
1. Finds all model outputs for the most recent reference date
2. Prompts user to select which model to submit
3. Renames/copies the file to UMass-alloy format
4. Creates a PR in the flu-metrocast repo
"""

import subprocess
import sys
from datetime import datetime
from pathlib import Path


def get_model_outputs(model_output_dir: Path) -> dict[str, list[Path]]:
    """Find all model output files grouped by reference date.

    Returns:
        Dict mapping reference date strings to list of forecast files.
    """
    outputs_by_date: dict[str, list[Path]] = {}

    for model_dir in model_output_dir.iterdir():
        if not model_dir.is_dir() or not model_dir.name.startswith("UMass-"):
            continue

        for csv_file in model_dir.glob("*.csv"):
            # Parse date from filename: YYYY-MM-DD-ModelName.csv
            parts = csv_file.name.split("-")
            if len(parts) >= 4:
                try:
                    ref_date = f"{parts[0]}-{parts[1]}-{parts[2]}"
                    datetime.strptime(ref_date, "%Y-%m-%d")  # Validate date
                    if ref_date not in outputs_by_date:
                        outputs_by_date[ref_date] = []
                    outputs_by_date[ref_date].append(csv_file)
                except ValueError:
                    continue

    return outputs_by_date


def select_model(files: list[Path]) -> Path | None:
    """Prompt user to select a model from the list.

    Args:
        files: List of forecast file paths.

    Returns:
        Selected file path, or None if cancelled.
    """
    print("\nAvailable models for submission:")
    print("-" * 50)

    for i, f in enumerate(files, 1):
        model_name = f.parent.name.replace("UMass-", "")
        print(f"  {i}. {model_name:<20} ({f.name})")

    print(f"  0. Cancel")
    print("-" * 50)

    while True:
        try:
            choice = input("\nSelect model number: ").strip()
            if choice == "0":
                return None
            idx = int(choice) - 1
            if 0 <= idx < len(files):
                return files[idx]
            print(f"Please enter a number between 0 and {len(files)}")
        except ValueError:
            print("Please enter a valid number")


def run_git_command(cmd: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess:
    """Run a git command and return the result."""
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"Error running: {' '.join(cmd)}")
        print(f"stderr: {result.stderr}")
        raise subprocess.CalledProcessError(result.returncode, cmd, result.stdout, result.stderr)
    return result


def main():
    # Paths
    script_dir = Path(__file__).parent
    sandbox_root = script_dir.parent
    model_output_dir = sandbox_root / "model-output"

    # flu-metrocast repo (sibling directory)
    flu_metrocast_root = sandbox_root.parent / "flu-metrocast"
    alloy_output_dir = flu_metrocast_root / "model-output" / "UMass-alloy"

    # Verify paths exist
    if not model_output_dir.exists():
        print(f"Error: Model output directory not found: {model_output_dir}")
        sys.exit(1)

    if not flu_metrocast_root.exists():
        print(f"Error: flu-metrocast repo not found: {flu_metrocast_root}")
        sys.exit(1)

    # Find all outputs
    outputs_by_date = get_model_outputs(model_output_dir)

    if not outputs_by_date:
        print("No model outputs found.")
        sys.exit(1)

    # Get most recent date
    most_recent_date = max(outputs_by_date.keys())
    files = sorted(outputs_by_date[most_recent_date], key=lambda f: f.parent.name)

    print(f"\nMost recent reference date: {most_recent_date}")
    print(f"Found {len(files)} model(s)")

    # Select model
    selected_file = select_model(files)
    if selected_file is None:
        print("Cancelled.")
        sys.exit(0)

    source_model = selected_file.parent.name.replace("UMass-", "")
    print(f"\nSelected: {source_model}")

    # Create destination filename
    dest_filename = f"{most_recent_date}-UMass-alloy.csv"
    dest_path = alloy_output_dir / dest_filename

    # Create UMass-alloy directory if needed
    alloy_output_dir.mkdir(parents=True, exist_ok=True)

    # Check if file already exists
    if dest_path.exists():
        overwrite = input(f"\n{dest_filename} already exists. Overwrite? (y/N): ").strip().lower()
        if overwrite != "y":
            print("Cancelled.")
            sys.exit(0)

    # Copy file
    import shutil
    shutil.copy2(selected_file, dest_path)
    print(f"\nCopied to: {dest_path}")

    # Git operations in flu-metrocast repo
    print("\n" + "=" * 50)
    print("Git operations in flu-metrocast repo")
    print("=" * 50)

    # Check current branch and status
    result = run_git_command(["git", "branch", "--show-current"], flu_metrocast_root)
    current_branch = result.stdout.strip()
    print(f"Current branch: {current_branch}")

    # Fetch latest from origin
    print("\nFetching latest from origin...")
    run_git_command(["git", "fetch", "origin"], flu_metrocast_root)

    # Create new branch from origin/main
    branch_name = f"umass-alloy-{most_recent_date}"
    print(f"\nCreating branch: {branch_name}")

    # Check if branch already exists
    result = run_git_command(
        ["git", "branch", "--list", branch_name],
        flu_metrocast_root,
        check=False
    )
    if result.stdout.strip():
        print(f"Branch {branch_name} already exists locally.")
        use_existing = input("Delete and recreate from origin/main? (y/N): ").strip().lower()
        if use_existing == "y":
            run_git_command(["git", "branch", "-D", branch_name], flu_metrocast_root)
        else:
            print("Using existing branch.")
            run_git_command(["git", "checkout", branch_name], flu_metrocast_root)
            # Still need to add and commit
            run_git_command(["git", "add", str(dest_path)], flu_metrocast_root)

            result = run_git_command(
                ["git", "status", "--porcelain", str(dest_path)],
                flu_metrocast_root
            )
            if result.stdout.strip():
                commit_msg = f"Add UMass-alloy forecast for {most_recent_date} (from {source_model})"
                run_git_command(["git", "commit", "-m", commit_msg], flu_metrocast_root)
                print(f"Committed: {commit_msg}")
            else:
                print("No changes to commit.")

            # Push and create PR
            print(f"\nPushing to origin/{branch_name}...")
            run_git_command(["git", "push", "-u", "origin", branch_name], flu_metrocast_root)

            print("\nCreating pull request...")
            pr_title = f"Add UMass-alloy forecast for {most_recent_date}"
            pr_body = f"Forecast submission for reference date {most_recent_date}.\n\nSource model: UMass-{source_model}"

            result = run_git_command([
                "gh", "pr", "create",
                "--title", pr_title,
                "--body", pr_body,
                "--base", "main"
            ], flu_metrocast_root, check=False)

            if result.returncode == 0:
                print(f"\nPR created successfully!")
                print(result.stdout)
            else:
                if "already exists" in result.stderr:
                    print("\nPR already exists for this branch.")
                    run_git_command(["gh", "pr", "view", "--web"], flu_metrocast_root, check=False)
                else:
                    print(f"Error creating PR: {result.stderr}")

            sys.exit(0)

    # Create new branch from origin/main
    run_git_command(["git", "checkout", "-b", branch_name, "origin/main"], flu_metrocast_root)

    # Add and commit
    run_git_command(["git", "add", str(dest_path)], flu_metrocast_root)

    commit_msg = f"Add UMass-alloy forecast for {most_recent_date} (from {source_model})"
    run_git_command(["git", "commit", "-m", commit_msg], flu_metrocast_root)
    print(f"Committed: {commit_msg}")

    # Push
    print(f"\nPushing to origin/{branch_name}...")
    run_git_command(["git", "push", "-u", "origin", branch_name], flu_metrocast_root)

    # Create PR
    print("\nCreating pull request...")
    pr_title = f"Add UMass-alloy forecast for {most_recent_date}"
    pr_body = f"Forecast submission for reference date {most_recent_date}.\n\nSource model: UMass-{source_model}"

    result = run_git_command([
        "gh", "pr", "create",
        "--title", pr_title,
        "--body", pr_body,
        "--base", "main"
    ], flu_metrocast_root, check=False)

    if result.returncode == 0:
        print(f"\nPR created successfully!")
        print(result.stdout)
    else:
        if "already exists" in result.stderr:
            print("\nPR already exists for this branch.")
            run_git_command(["gh", "pr", "view", "--web"], flu_metrocast_root, check=False)
        else:
            print(f"Error creating PR: {result.stderr}")
            sys.exit(1)

    # Return to original branch
    print(f"\nReturning to branch: {current_branch}")
    run_git_command(["git", "checkout", current_branch], flu_metrocast_root)

    print("\nDone!")


if __name__ == "__main__":
    main()
