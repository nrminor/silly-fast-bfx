include { samplesheetToList } from 'plugin/nf-schema'

def normalizePlatform(platform) {
    def normalized_platform = platform.toString().toLowerCase()

    normalized_platform in ['nanopore', 'oxford_nanopore', 'oxford-nanopore']
        ? 'ont'
        : normalized_platform
}

def rejectDuplicateSampleIds(rows) {
    def duplicates = rows
        .groupBy { row -> row[0].id }
        .findAll { id, matching_rows -> matching_rows.size() > 1 }
        .keySet()
        .sort()

    if (duplicates) {
        throw new IllegalArgumentException(
            "Duplicate sample ID: ${duplicates.join(', ')}",
        )
    }
}

workflow GATHER_INPUT_READS {
    take:
    samplesheet

    main:
    rows = samplesheetToList(
        samplesheet,
        "${projectDir}/assets/samplesheet_schema.json",
    )
    rejectDuplicateSampleIds(rows)

    ch_input_rows = channel
        .fromList(rows)
        .map { meta, srr, fastq1, fastq2, fastq1_glob, fastq2_glob ->
            tuple(
                meta + [platform: normalizePlatform(meta.platform)],
                srr ?: '',
                fastq1 ?: '',
                fastq2 ?: '',
                fastq1_glob ?: '',
                fastq2_glob ?: '',
            )
        }
        .branch { meta, srr, fastq1, fastq2, fastq1_glob, fastq2_glob ->
            exact: fastq1
            grouped: fastq1_glob
            sra: srr
        }

    ch_exact_reads = ch_input_rows.exact.map {
        meta, srr, fastq1, fastq2, fastq1_glob, fastq2_glob ->

        tuple(
            meta + [
                single_end: !fastq2,
                read_set: 'input',
            ],
            fastq2
                ? [file(fastq1, checkIfExists: true), file(fastq2, checkIfExists: true)]
                : [file(fastq1, checkIfExists: true)],
        )
    }

    ch_grouped_guard = ch_input_rows.grouped.map {
        error 'Grouped FASTQ input is available in a later review unit'
    }
    ch_sra_guard = ch_input_rows.sra.map {
        error 'SRA input is available in a later review unit'
    }

    ch_input_reads = ch_exact_reads
        .mix(ch_grouped_guard)
        .mix(ch_sra_guard)

    emit:
    reads = ch_input_reads
}
