include { ENCODE_READS_WITH_BQTOOLS } from '../../../modules/local/encode_reads_with_bqtools'
include { FILTER_READS_WITH_DEACON   } from '../../../modules/local/filter_reads_with_deacon'
include { SKETCH_READS_WITH_SYLPH    } from '../../../modules/local/sketch_reads_with_sylph'
include { PROFILE_READS_WITH_SYLPH   } from '../../../modules/local/profile_reads_with_sylph'

workflow SCREEN_READ_SETS {
    take:
    input_reads
    deacon_references
    sylph_references

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

    ch_post_deacon_reads = ch_filtered_reads
        .filter { meta, reads -> !params.skip_post_deacon }

    ch_search_reads = input_reads.mix(ch_post_deacon_reads)

    ch_sylph_sketch_settings = sylph_references
        .map { sample_sketch, reference, database -> sample_sketch }
        .unique()

    ch_sylph_sketch_jobs = ch_search_reads
        .combine(ch_sylph_sketch_settings)
        .map { meta, reads, sample_sketch -> tuple(sample_sketch, meta, reads) }

    SKETCH_READS_WITH_SYLPH(ch_sylph_sketch_jobs)

    ch_sylph_profile_jobs = SKETCH_READS_WITH_SYLPH.out.sketches
        .combine(sylph_references, by: 0)
        .map { sample_sketch, meta, sketch, reference, database ->
            tuple(meta, reference, sketch, database)
        }

    PROFILE_READS_WITH_SYLPH(ch_sylph_profile_jobs)

    ch_sylph_profiles = PROFILE_READS_WITH_SYLPH.out.profiles
        .filter { meta, reference, profile, has_profile_rows ->
            has_profile_rows == 'true'
        }
        .map { meta, reference, profile, has_profile_rows ->
            tuple(meta, reference, profile)
        }

    emit:
    deacon = FILTER_READS_WITH_DEACON.out.reads
    filtered_reads = ch_filtered_reads
    sylph = PROFILE_READS_WITH_SYLPH.out.profiles
    sylph_profiles = ch_sylph_profiles
}
