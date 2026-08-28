include { samplesheetToList } from 'plugin/nf-schema'
include { PRESERVE_SAMPLESHEET } from '../../../modules/local/preserve_samplesheet'

def normalizePlatform(platform) {
    def normalized_platform = platform.toString().toLowerCase()

    normalized_platform in ['nanopore', 'oxford_nanopore', 'oxford-nanopore']
        ? 'ont'
        : normalized_platform
}

workflow GATHER_INPUT_READS {
    take:
    samplesheet

    main:
    rows = samplesheetToList(
        samplesheet,
        "${projectDir}/assets/samplesheet_schema.json",
    )

    PRESERVE_SAMPLESHEET(samplesheet)

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
        .branch { _meta, srr, fastq1, _fastq2, fastq1_glob, _fastq2_glob ->
            exact: fastq1
            grouped: fastq1_glob
            sra: srr
        }

    ch_exact_reads = ch_input_rows.exact.map {
        meta, _srr, fastq1, fastq2, _fastq1_glob, _fastq2_glob ->

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
        _meta, _srr, _fastq1, _fastq2, _fastq1_glob, _fastq2_glob ->

        error 'Grouped FASTQ input is available in a later review unit'
    }
    ch_sra_guard = ch_input_rows.sra.map {
        _meta, _srr, _fastq1, _fastq2, _fastq1_glob, _fastq2_glob ->

        error 'SRA input is available in a later review unit'
    }

    ch_input_reads = ch_exact_reads
        .mix(ch_grouped_guard)
        .mix(ch_sra_guard)

    emit:
    reads = ch_input_reads
    samplesheet = PRESERVE_SAMPLESHEET.out.samplesheet
}
