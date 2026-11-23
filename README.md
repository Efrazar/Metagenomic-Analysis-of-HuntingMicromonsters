<p align="center">
  <img src="HMM.png" alt="Hunting MicroMonsters expedition banner" width="700"/>
</p>

<p align="center">
  <a href="https://hmicromonsters.wordpress.com/">
    <img src="https://img.shields.io/badge/Project_Website-hmicromonsters.wordpress.com-blue?style=for-the-badge&logo=wordpress" alt="Website"/>
  </a>
</p>

---
# Bioinformatic Analysis Workflow
## Project Overview
This project describes the workflow to perform bioinformatic analysis of the sequencing data obtained from the project "Hunting MicroMonsters".

**About the Expedition:** 
Hunting MicroMonsters is a scientific documentary that tells the story of an expedition led by PhD students from the University of Edinburgh. Supported by alumni and friends of the University through the Student Experience Grants scheme, the project aims to characterize the microbial diversity in iconic Scottish Lochs.

## Status
* **Done:** raw data handling, format conversion, basecalling, read QC, adapter trimming, quality filtering, and the Kraken2 classification setup.
* **In progress:** Kraken2/Bracken taxonomic profiles, Krona plots and the diversity analysis. These results will be added to this repository when they are complete.

## Repository Structure
```
HHM-Bioinformatic_Analysis.ipynb          # Step-by-step workflow with commentary
scripts/
  enhanced_filtlong_combined_nanoplot.sh  # Parallel Filtlong filtering + combined NanoPlot QC
  kraken2_batch_analysis.sh               # Batch Kraken2 classification (database loaded once)
HMM.png                                   # Project banner
```

## Workflow Description
This repository contains a comprehensive bioinformatic pipeline for processing Oxford Nanopore Technologies (ONT) sequencing data, specifically designed for environmental DNA (eDNA) shotgun metagenomics. The workflow takes raw sequencing files through basecalling, quality control, and taxonomic classification.

### 1. Data Preprocessing and Renaming
*   A bash script automates the conversion of long, complex ONT `.fast5` raw data file names into a simplified, short-consecutive-number format (e.g., `folder_name_counter.extension`).
*   The script executes recursively across subdirectories to ensure proper numbering and consistent file organization.

### 2. Format Conversion (`fast5` to `pod5`)
*   Single-read `.fast5` files are first converted into multi-read `.fast5` files using the `ont-fast5-api` module.
*   The multi-read files are subsequently converted to the `.pod5` format using the `pod5` tool to optimize downstream computing performance.

### 3. Basecalling
*   High-accuracy basecalling is performed on the `.pod5` files using the Guppy basecaller tool (`guppy_basecaller`).
*   The pipeline relies on the high accuracy (`hac`) configuration (`dna_r9.4.1_450bps_hac.cfg`), matching the R9.4.1 flow cells used for this run.
*   Note: ONT has since replaced Guppy with [Dorado](https://github.com/nanoporetech/dorado). New R10.4.1 data should be basecalled with Dorado.

### 4. Quality Control and Filtering
*   **Compression:** Multi-fastq outputs are compressed using `gzip` for efficient storage and integration with downstream tools.
*   **Initial QC:** Read quality is analyzed and visualized using `NanoPlot` based on the Guppy sequencing summary file.
*   **Adapter Trimming:** ONT sequencing adapters are removed using `porechop`.
*   **Quality Filtering:** High-quality reads are filtered using `filtlong` with strict parameters: a minimum mean quality score of 10, a minimum read length of 900 bp, and retaining the top 90% of bases up to a target of 500 million bases.
*   **Combined QC Script:** The repository includes a bash script (`scripts/enhanced_filtlong_combined_nanoplot.sh`) to automate parallel `filtlong` filtering and perform post-filtering QC analysis on the combined dataset.

### 5. Metagenomic and Taxonomic Analysis
*   **Database:** The workflow uses the PlusPFP-16 database for broad eDNA metagenomics, covering plants, fungi, protists, bacteria, and viruses.
*   **Classification:** Taxonomic classification is executed using `kraken2`.
*   **Batch Processing:** `scripts/kraken2_batch_analysis.sh` concatenates filtered reads and runs `kraken2` efficiently, loading the database into RAM only once to significantly reduce processing time.
*   **Downstream Compatibility:** Outputs are specifically structured for downstream species-level abundance estimation using `Bracken` and interactive hierarchical visualization using `Krona` (`kreport2krona.py`).

## System Requirements
*   The bash scripts in this pipeline—particularly for filtering and Kraken2 analysis—are tuned for a system equipped with an 8-core CPU and 32GB of RAM.
*   Memory limits and core utilization (e.g., staggering a maximum of 4 parallel jobs for `filtlong` to use ~24GB of RAM) are set as variables at the top of each script to maintain system stability and prevent resource overload.

## Software Dependencies
The workflow relies on Conda environments to isolate and manage dependencies. Key tools and libraries include:
*   `ont-fast5-api`, `pod5`
*   `guppy`
*   `NanoPlot`
*   `porechop`, `filtlong`
*   `kraken2`, `bracken`, `krakentools`, `krona`
*   `biopython`, `pandas`

## Usage
To replicate this analysis, clone the repository and follow the step-by-step commands in the Jupyter notebook. Create and activate the matching Conda environment (`fast5-to-pod5`, `guppy`, `ont-trimming`, `metagenomics`) before each section. For the two long-running steps, edit the paths at the top of each script and run it:

```bash
bash scripts/enhanced_filtlong_combined_nanoplot.sh
bash scripts/kraken2_batch_analysis.sh
```

The raw sequencing data are not included in this repository because of their size.

## Next Steps
* Species- and genus-level abundance estimation with Bracken
* Interactive Krona plots per sample
* Alpha and beta diversity across lochs
* Re-basecalling with Dorado to compare classification results

---
*Released under the [MIT License](LICENSE).*
