#!/bin/bash

# =============================================================================
# ENHANCED FILTLONG + NANOPLOT COMBINED MODE PIPELINE - OPTIMIZED FOR 8 CORES, 32GB RAM
# =============================================================================

# Configuration
INPUT_DIR="/path/to/trimmed/fastq/files"
OUTPUT_DIR="/path/to/output/directory"
TEMP_DIR="/tmp/filtlong_nanoplot_processing"

# System-optimized settings for 8 cores, 32GB RAM
MAX_PARALLEL_JOBS=4  # ~6 GB RAM per Filtlong job; NanoPlot runs once at the end
MEMORY_PER_JOB="6G"  # Memory per Filtlong job

# Filtlong parameters
KEEP_PERCENT=90
TARGET_BASES=500000000
MIN_LENGTH=900
MIN_MEAN_Q=10

# NanoPlot Combined Mode parameters
NANOPLOT_THREADS=4      # Use more threads since it's a single NanoPlot job
NANOPLOT_PLOTS="kde hex dot"  # Plot types to generate
NANOPLOT_PREFIX="Combined_Dataset"  # Prefix for combined analysis
ENABLE_QC=true          # Set to false to skip QC step

# =============================================================================
# SETUP AND VALIDATION
# =============================================================================

# Create directories
mkdir -p "$OUTPUT_DIR"/{filtered,combined_qc,logs} "$TEMP_DIR"

# Check system resources
AVAILABLE_RAM=$(free -g | awk '/^Mem:/{print $7}')
AVAILABLE_CORES=$(nproc)

echo "=== Enhanced Filtlong + NanoPlot Combined Mode Pipeline Started ==="
echo "Available RAM: ${AVAILABLE_RAM}GB"
echo "Available CPU cores: $AVAILABLE_CORES"
echo "Max parallel Filtlong jobs: $MAX_PARALLEL_JOBS"
echo "NanoPlot Combined Mode: $ENABLE_QC"
echo "=========================================="

# Validate system requirements
if [ "$AVAILABLE_RAM" -lt 20 ]; then
    echo "Warning: Less than 20GB available RAM. Consider reducing MAX_PARALLEL_JOBS."
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if NanoPlot is available
if ! command -v NanoPlot &> /dev/null && [ "$ENABLE_QC" = true ]; then
    echo "Error: NanoPlot not found. Install it with: pip install NanoPlot"
    echo "Or set ENABLE_QC=false to skip QC analysis"
    exit 1
fi

# =============================================================================
# PROCESSING FUNCTIONS
# =============================================================================

# Function to process a single file through Filtlong
process_filtlong() {
    local input_file="$1"
    local job_id="$2"
    
    local filename=$(basename "$input_file" .fastq.gz)
    local output_file="$OUTPUT_DIR/filtered/${filename}_filtered.fastq.gz"
    local temp_output="$TEMP_DIR/${filename}_temp_${job_id}.fastq"
    local log_file="$OUTPUT_DIR/logs/${filename}_filtlong.log"
    
    echo "[Filtlong Job $job_id] Starting: $filename"
    echo "[Job $job_id] $(date): Filtlong processing started" > "$log_file"
    
    local start_time=$(date +%s)
    
    {
        # Memory limit
        local memory_limit_kb=$((${MEMORY_PER_JOB%G} * 1024 * 1024))
        ulimit -v $memory_limit_kb
        
        # Run Filtlong
        filtlong \
            --keep_percent "$KEEP_PERCENT" \
            --target_bases "$TARGET_BASES" \
            --min_length "$MIN_LENGTH" \
            --min_mean_q "$MIN_MEAN_Q" \
            --verbose \
            "$input_file" > "$temp_output" 2>>"$log_file"
        
        if [ $? -eq 0 ] && [ -s "$temp_output" ]; then
            gzip -c "$temp_output" > "$output_file"
            rm "$temp_output"
            
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            echo "[Job $job_id] $(date): Filtlong completed in ${duration}s" >> "$log_file"
            echo "[Filtlong Job $job_id] Completed: $filename (${duration}s)"
            return 0
        else
            echo "[Filtlong Job $job_id] ERROR: Failed to process $filename" | tee -a "$log_file"
            rm -f "$temp_output" "$output_file"
            return 1
        fi
    }
}

# Function to run NanoPlot in Combined Mode on all filtered files
run_combined_nanoplot() {
    echo "=== Starting NanoPlot Combined Mode Analysis ==="
    
    # Find all filtered files
    local filtered_files=("$OUTPUT_DIR/filtered"/*_filtered.fastq.gz)
    
    if [ ${#filtered_files[@]} -eq 0 ]; then
        echo "No filtered files found for combined QC analysis"
        return 1
    fi
    
    echo "Found ${#filtered_files[@]} filtered files for combined analysis"
    
    local qc_output_dir="$OUTPUT_DIR/combined_qc"
    local qc_log_file="$OUTPUT_DIR/logs/combined_nanoplot.log"
    
    echo "$(date): NanoPlot Combined Mode started" > "$qc_log_file"
    echo "Input files:" >> "$qc_log_file"
    for file in "${filtered_files[@]}"; do
        echo "  - $(basename "$file")" >> "$qc_log_file"
    done
    
    local start_time=$(date +%s)
    
    {
        # Memory limit for NanoPlot (use more memory since it's processing all files)
        local memory_limit_kb=$((24 * 1024 * 1024))  # 24GB for combined processing
        ulimit -v $memory_limit_kb
        
        # Run NanoPlot in Combined Mode[159][166][208]
        NanoPlot \
            --fastq "${filtered_files[@]}" \
            --outdir "$qc_output_dir" \
            --prefix "${NANOPLOT_PREFIX}_" \
            --threads "$NANOPLOT_THREADS" \
            --plots $NANOPLOT_PLOTS \
            --N50 \
            --loglength \
            --drop_outliers \
            --verbose 2>>"$qc_log_file"
        
        if [ $? -eq 0 ]; then
            # Generate enhanced summary statistics
            local stats_file="$qc_output_dir/${NANOPLOT_PREFIX}_combined_summary.txt"
            {
                echo "=== Combined QC Summary for All Filtered Files ==="
                echo "Generated on: $(date)"
                echo "Analysis mode: Combined Mode (all files processed as single dataset)"
                echo "Number of input files: ${#filtered_files[@]}"
                echo "Output directory: $qc_output_dir"
                echo ""
                
                echo "=== Input Files Processed ==="
                for file in "${filtered_files[@]}"; do
                    local file_size=$(du -h "$file" | cut -f1)
                    echo "  - $(basename "$file") (${file_size})"
                done
                echo ""
                
                # Extract key stats from NanoStats.txt if available[160]
                if [ -f "$qc_output_dir/NanoStats.txt" ]; then
                    echo "=== Combined Dataset Statistics ==="
                    cat "$qc_output_dir/NanoStats.txt"
                    echo ""
                fi
                
                echo "=== Available Reports and Plots ==="
                echo "Main HTML report: ${NANOPLOT_PREFIX}_NanoPlot-report.html"
                echo "Statistics file: NanoStats.txt"
                echo "Individual plots: Available as PNG and HTML files"
                
            } > "$stats_file"
            
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            
            echo "$(date): NanoPlot Combined Mode completed in ${duration}s" >> "$qc_log_file"
            echo "[Combined QC] Completed: All filtered files analyzed in ${duration}s"
            echo "[Combined QC] Main report: $qc_output_dir/${NANOPLOT_PREFIX}_NanoPlot-report.html"
            return 0
        else
            echo "[Combined QC] ERROR: NanoPlot Combined Mode failed" | tee -a "$qc_log_file"
            return 1
        fi
    }
}

# Export functions
export -f process_filtlong
export OUTPUT_DIR TEMP_DIR KEEP_PERCENT TARGET_BASES MIN_LENGTH MIN_MEAN_Q MEMORY_PER_JOB

# =============================================================================
# PARALLEL FILTLONG PROCESSING
# =============================================================================

echo "=== Phase 1: Parallel Filtlong Processing ==="

# Find all FASTQ.gz files
mapfile -t fastq_files < <(find "$INPUT_DIR" -name "*.fastq.gz" -type f)

if [ ${#fastq_files[@]} -eq 0 ]; then
    echo "No FASTQ.gz files found in $INPUT_DIR"
    exit 1
fi

echo "Found ${#fastq_files[@]} FASTQ.gz files to process with Filtlong"

# Process files with controlled parallelism
job_counter=0
active_jobs=()
failed_files=()

for file in "${fastq_files[@]}"; do
    # Wait if we've reached the maximum number of parallel jobs
    while [ ${#active_jobs[@]} -ge $MAX_PARALLEL_JOBS ]; do
        new_active_jobs=()
        for pid in "${active_jobs[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                new_active_jobs+=("$pid")
            else
                wait "$pid"
                if [ $? -ne 0 ]; then
                    echo "Warning: Filtlong job with PID $pid failed"
                fi
            fi
        done
        active_jobs=("${new_active_jobs[@]}")
        
        # Resource monitoring
        used_memory=$(free | awk '/^Mem:/{printf "%.1f", $3/$2 * 100.0}')
        echo "Filtlong Status: Memory ${used_memory}% | Active jobs: ${#active_jobs[@]}/$MAX_PARALLEL_JOBS"
        
        sleep 3
    done
    
    # Start new Filtlong job
    ((job_counter++))
    echo "Starting Filtlong job $job_counter for: $(basename "$file")"
    
    process_filtlong "$file" "$job_counter" &
    job_pid=$!
    active_jobs+=("$job_pid")
    
    # Staggered start
    sleep 2
done

# Wait for all Filtlong jobs to complete
echo "Waiting for remaining Filtlong jobs to complete..."
for pid in "${active_jobs[@]}"; do
    wait "$pid"
    if [ $? -ne 0 ]; then
        echo "Warning: Filtlong job with PID $pid failed"
    fi
done

echo "=== Phase 1 Complete: Filtlong Processing Finished ==="

# =============================================================================
# COMBINED NANOPLOT QC ANALYSIS
# =============================================================================

if [ "$ENABLE_QC" = true ]; then
    echo ""
    echo "=== Phase 2: Combined NanoPlot QC Analysis ==="
    
    # Count successful Filtlong outputs
    successful_filtered=$(find "$OUTPUT_DIR/filtered" -name "*_filtered.fastq.gz" -type f | wc -l)
    
    if [ "$successful_filtered" -eq 0 ]; then
        echo "No successfully filtered files found. Skipping QC analysis."
    else
        echo "Processing $successful_filtered filtered files in Combined Mode..."
        
        # Run combined NanoPlot analysis
        if run_combined_nanoplot; then
            echo "Combined QC analysis completed successfully!"
        else
            echo "Combined QC analysis failed. Check logs for details."
        fi
    fi
else
    echo "=== Phase 2 Skipped: QC analysis disabled ==="
fi

# =============================================================================
# FINAL SUMMARY AND CLEANUP
# =============================================================================

echo ""
echo "=== Processing Complete - Generating Final Summary ==="

# Count results
successful_filtered=$(find "$OUTPUT_DIR/filtered" -name "*_filtered.fastq.gz" -type f | wc -l)
qc_report_exists=false

if [ "$ENABLE_QC" = true ] && [ -f "$OUTPUT_DIR/combined_qc/${NANOPLOT_PREFIX}_NanoPlot-report.html" ]; then
    qc_report_exists=true
fi

# Generate comprehensive summary report
summary_report="$OUTPUT_DIR/pipeline_summary.txt"
{
    echo "=== Enhanced Filtlong + NanoPlot Combined Mode Pipeline Summary ==="
    echo "Execution date: $(date)"
    echo "Input directory: $INPUT_DIR"
    echo "Output directory: $OUTPUT_DIR"
    echo ""
    echo "=== Processing Parameters ==="
    echo "Filtlong settings:"
    echo "  - Keep percent: $KEEP_PERCENT%"
    echo "  - Target bases: $TARGET_BASES"
    echo "  - Minimum length: $MIN_LENGTH bp"
    echo "  - Minimum mean quality: $MIN_MEAN_Q"
    echo "  - Max parallel jobs: $MAX_PARALLEL_JOBS"
    echo ""
    echo "NanoPlot Combined Mode settings:"
    echo "  - QC enabled: $ENABLE_QC"
    echo "  - Analysis mode: Combined (all files as single dataset)"
    echo "  - Threads: $NANOPLOT_THREADS"
    echo "  - Plot types: $NANOPLOT_PLOTS"
    echo "  - Prefix: $NANOPLOT_PREFIX"
    echo ""
    echo "=== Results Summary ==="
    echo "Total input files: ${#fastq_files[@]}"
    echo "Successfully filtered: $successful_filtered"
    echo "Combined QC analysis: $($qc_report_exists && echo "✓ Success" || echo "✗ Failed/Skipped")"
    echo ""
    echo "=== Output Structure ==="
    echo "Filtered reads: $OUTPUT_DIR/filtered/"
    if [ "$ENABLE_QC" = true ]; then
        echo "Combined QC report: $OUTPUT_DIR/combined_qc/"
    fi
    echo "Log files: $OUTPUT_DIR/logs/"
    echo ""
    
    if [ "$qc_report_exists" = true ]; then
        echo "=== Combined Dataset QC Statistics ==="
        if [ -f "$OUTPUT_DIR/combined_qc/NanoStats.txt" ]; then
            echo "Key metrics from combined analysis:"
            grep -E "(Mean read length|Median read length|N50|Total bases|Number of reads|Mean read quality)" "$OUTPUT_DIR/combined_qc/NanoStats.txt" 2>/dev/null || echo "Stats extraction failed"
        fi
        echo ""
    fi
    
    echo "=== Individual File Processing Status ==="
    for file in "${fastq_files[@]}"; do
        filename=$(basename "$file" .fastq.gz)
        filtered_file="$OUTPUT_DIR/filtered/${filename}_filtered.fastq.gz"
        
        echo "File: $filename"
        if [ -f "$filtered_file" ]; then
            filtered_size=$(du -h "$filtered_file" | cut -f1)
            echo "  ✓ Filtered: ${filtered_size}"
        else
            echo "  ✗ Filtering failed"
        fi
    done
    
} > "$summary_report"

# Display key information
echo ""
echo "=== Output Locations ==="
echo "📁 Filtered reads: $OUTPUT_DIR/filtered/"
if [ "$qc_report_exists" = true ]; then
    echo "📊 Combined QC report: $OUTPUT_DIR/combined_qc/${NANOPLOT_PREFIX}_NanoPlot-report.html"
    echo "📈 Combined statistics: $OUTPUT_DIR/combined_qc/NanoStats.txt"
    echo "📋 QC summary: $OUTPUT_DIR/combined_qc/${NANOPLOT_PREFIX}_combined_summary.txt"
fi
echo "📋 Log files: $OUTPUT_DIR/logs/"
echo "📄 Pipeline summary: $summary_report"

# Cleanup temporary directory
rm -rf "$TEMP_DIR"

# Final system status
final_memory=$(free -h | awk '/^Mem:/{print "Used: " $3 ", Available: " $7}')
echo ""
echo "Final memory status: $final_memory"
echo "=== Pipeline Complete ==="

if [ "$qc_report_exists" = true ]; then
    echo ""
    echo "🎯 **MAIN RESULT**: Open the combined QC report in a browser:"
    echo "   $OUTPUT_DIR/combined_qc/${NANOPLOT_PREFIX}_NanoPlot-report.html"
    echo ""
    echo "This report contains comprehensive quality analysis of ALL filtered files"
    echo "processed as a single combined dataset with unified statistics and plots."
fi
