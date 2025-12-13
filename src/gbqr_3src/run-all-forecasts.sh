#!/bin/bash
# Sequential script for running all forecasts locally

# Array of dates to process (2025-2026 season)
# Note: iddata NSSP loading requires as_of dates >= 2025-09-17
dates=(
  "2025-11-19"
  "2025-11-26"
  "2025-12-03"
  "2025-12-10"
)

echo "Running ${#dates[@]} forecasts sequentially..."
echo "=========================================="

for date in "${dates[@]}"; do
    echo "Processing date: $date"
    python main.py --today_date="$date"

    if [ $? -ne 0 ]; then
        echo "Error: Forecast failed for $date"
        exit 1
    fi

    echo "Completed: $date"
    echo "------------------------------------------"
done

echo "=========================================="
echo "All forecasts completed successfully!"
