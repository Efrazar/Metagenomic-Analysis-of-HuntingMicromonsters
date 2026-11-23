#!/bin/bash

# Kraken2 Batch Analysis Script for Environmental DNA Shotgun Metagenomics
# Author: Efrain Zarazua-Arvizu
# Description: Processes multiple filtered FASTQ.gz files for taxonomic classification
# Compatible with downstream Bracken and Krona analysis

# Set script parameters
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration variables
KRAKEN2_DB="/path/to/kraken2_db/k2_pluspfp_16gb"   # Path to the extracted Kraken2 database
INPUT_DIR="/path/to/filtered/fastq/files"        # Directory containing filtered FASTQ.gz files
OUTPUT_DIR="/path/to/kraken2/output"             # Output directory for results (keep separate from the input)
THREADS=8                               # Number of CPU threads (8-core workstation)
CONFIDENCE=0.0                          # Kraken2 default; 0.05-0.1 reduces false positives in eDNA data
MIN_BASE_QUALITY=10                     # Minimum base quality (matches the Filtlong Q10 filter)

# Create output directories
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}/individual_reports"
mkdir -p "${OUTPUT_DIR}/individual_outputs"

# Log file for tracking progress
LOG_FILE="${OUTPUT_DIR}/kraken2_batch_analysis.log"
echo "Starting Kraken2 batch analysis: $(date)" > "${LOG_FILE}"

# Verify database exists
if [ ! -d "${KRAKEN2_DB}" ]; then
    echo "ERROR: Kraken2 database not found at ${KRAKEN2_DB}" | tee -a "${LOG_FILE}"
    echo "Please update the KRAKEN2_DB variable with the correct path"
    exit 1
fi

# Find all FASTQ.gz files and store in array
mapfile -t FASTQ_FILES < <(find "${INPUT_DIR}" -name "*.fastq.gz" -o -name "*.fq.gz" | sort)

# Check if files were found
if [ ${#FASTQ_FILES[@]} -eq 0 ]; then
    echo "ERROR: No FASTQ.gz files found in ${INPUT_DIR}" | tee -a "${LOG_FILE}"
    exit 1
fi

echo "Found ${#FASTQ_FILES[@]} FASTQ.gz files for analysis" | tee -a "${LOG_FILE}"

# Concatenate all FASTQ files for combined analysis
COMBINED_FASTQ="${OUTPUT_DIR}/combined_filtered_reads.fastq.gz"
echo "Concatenating ${#FASTQ_FILES[@]} files into combined dataset..." | tee -a "${LOG_FILE}"

cat "${FASTQ_FILES[@]}" > "${COMBINED_FASTQ}"

echo "Combined FASTQ file created: ${COMBINED_FASTQ}" | tee -a "${LOG_FILE}"

# Run Kraken2 on combined dataset
echo "Starting Kraken2 taxonomic classification on combined dataset..." | tee -a "${LOG_FILE}"

kraken2 \
    --db "${KRAKEN2_DB}" \
    --threads "${THREADS}" \
    --confidence "${CONFIDENCE}" \
    --minimum-base-quality "${MIN_BASE_QUALITY}" \
    --gzip-compressed \
    --use-names \
    --report "${OUTPUT_DIR}/combined_kraken2_report.txt" \
    --output "${OUTPUT_DIR}/combined_kraken2_output.txt" \
    --classified-out "${OUTPUT_DIR}/combined_classified_reads.fastq" \
    --unclassified-out "${OUTPUT_DIR}/combined_unclassified_reads.fastq" \
    "${COMBINED_FASTQ}" 2>&1 | tee -a "${LOG_FILE}"

# Generate Kraken2 summary statistics
echo "Generating classification statistics..." | tee -a "${LOG_FILE}"

TOTAL_READS=$(zcat "${COMBINED_FASTQ}" | wc -l | awk '{print $1/4}')
CLASSIFIED_READS=$(grep -c "^C" "${OUTPUT_DIR}/combined_kraken2_output.txt" || echo "0")
UNCLASSIFIED_READS=$(grep -c "^U" "${OUTPUT_DIR}/combined_kraken2_output.txt" || echo "0")
CLASSIFICATION_RATE=$(echo "scale=2; ${CLASSIFIED_READS} * 100 / ${TOTAL_READS}" | bc -l)

# Create summary report
SUMMARY_FILE="${OUTPUT_DIR}/classification_summary.txt"
cat > "${SUMMARY_FILE}" << EOF
Kraken2 Environmental DNA Metagenomics Analysis Summary
======================================================
Analysis Date: $(date)
Database: ${KRAKEN2_DB}
Input Files: ${#FASTQ_FILES[@]} FASTQ.gz files
Combined Dataset: ${COMBINED_FASTQ}

Classification Parameters:
- Threads: ${THREADS}
- Confidence Threshold: ${CONFIDENCE}
- Minimum Base Quality: ${MIN_BASE_QUALITY}

Results:
- Total Reads Processed: ${TOTAL_READS}
- Classified Reads: ${CLASSIFIED_READS}
- Unclassified Reads: ${UNCLASSIFIED_READS}
- Classification Rate: ${CLASSIFICATION_RATE}%

Output Files:
- Kraken2 Report: combined_kraken2_report.txt
- Kraken2 Output: combined_kraken2_output.txt
- Classified Reads: combined_classified_reads.fastq
- Unclassified Reads: combined_unclassified_reads.fastq

Files ready for downstream analysis with:
- Bracken: Use combined_kraken2_report.txt as input
- Krona: Convert combined_kraken2_report.txt using kreport2krona.py
EOF

echo "${SUMMARY_FILE} created" | tee -a "${LOG_FILE}"

# Optional: Process individual files for comparative analysis
if [ "${1:-}" == "--individual" ]; then
    echo "Processing individual files for comparative analysis..." | tee -a "${LOG_FILE}"
    
    for fastq_file in "${FASTQ_FILES[@]}"; do
        filename=$(basename "${fastq_file}" .fastq.gz)
        filename=$(basename "${filename}" .fq.gz)
        
        echo "Processing ${filename}..." | tee -a "${LOG_FILE}"
        
        kraken2 \
            --db "${KRAKEN2_DB}" \
            --threads "${THREADS}" \
            --confidence "${CONFIDENCE}" \
            --minimum-base-quality "${MIN_BASE_QUALITY}" \
            --gzip-compressed \
            --use-names \
            --report "${OUTPUT_DIR}/individual_reports/${filename}_kraken2_report.txt" \
            --output "${OUTPUT_DIR}/individual_outputs/${filename}_kraken2_output.txt" \
            "${fastq_file}" 2>&1 | tee -a "${LOG_FILE}"
    done
fi

# Clean up combined FASTQ file to save space (optional)
if [ "${2:-}" == "--cleanup" ]; then
    echo "Cleaning up temporary combined FASTQ file..." | tee -a "${LOG_FILE}"
    rm "${COMBINED_FASTQ}"
fi

echo "Kraken2 batch analysis completed successfully: $(date)" | tee -a "${LOG_FILE}"
echo "Results are ready for downstream analysis with Bracken and Krona tools"
echo "Summary: ${SUMMARY_FILE}"
