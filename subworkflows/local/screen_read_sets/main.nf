include { ENCODE_READS_WITH_BQTOOLS } from '../../../modules/local/encode_reads_with_bqtools'
include { FILTER_READS_WITH_DEACON   } from '../../../modules/local/filter_reads_with_deacon'

workflow SCREEN_READ_SETS {
    take:
    input_reads
    deacon_references

    main:
    ch_deacon_gate = deacon_references
        .map { reference, index -> true }
        .first()

    ch_deacon_input_reads = input_reads
        .combine(ch_deacon_gate)
        .map { meta, reads, enabled -> tuple(meta, reads) }

    ENCODE_READS_WITH_BQTOOLS(ch_deacon_input_reads)

    ch_deacon_jobs = ENCODE_READS_WITH_BQTOOLS.out.encodings
        .combine(deacon_references)
        .map { meta, cbq, reference, index ->
            tuple(meta, reference, cbq, index)
        }

    FILTER_READS_WITH_DEACON(ch_deacon_jobs)

    ch_filtered_reads = FILTER_READS_WITH_DEACON.out.reads
        .filter { meta, reference, reads, summary, has_reads ->
            has_reads == 'true'
        }
        .map { meta, reference, reads, summary, has_reads ->
            tuple(
                meta + [
                    read_set: 'deacon_filtered',
                    deacon_id: reference.id,
                ],
                reads,
            )
        }

    emit:
    deacon = FILTER_READS_WITH_DEACON.out.reads
    filtered_reads = ch_filtered_reads
}
