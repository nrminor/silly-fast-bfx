include { ENCODE_READS_WITH_BQTOOLS } from '../../../modules/local/encode_reads_with_bqtools'
include { FILTER_READS_WITH_DEACON   } from '../../../modules/local/filter_reads_with_deacon'
include { SKETCH_READS_WITH_SYLPH    } from '../../../modules/local/sketch_reads_with_sylph'
include { PROFILE_READS_WITH_SYLPH   } from '../../../modules/local/profile_reads_with_sylph'
include { SUMMARIZE_SYLPH_TAXONOMY   } from '../../../modules/local/summarize_sylph_taxonomy'
include { QUERY_READS_WITH_SKOPE      } from '../../../modules/local/query_reads_with_skope'

workflow SCREEN_READ_SETS {
    take:
    input_reads
    deacon_references
    sylph_references
    sylph_taxonomy
    skope_references

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

    ch_read_sets_by_source = input_reads
        .map { meta, reads -> tuple('input', meta, reads) }
        .mix(
            ch_filtered_reads.map { meta, reads ->
                tuple("deacon:${meta.deacon_id}", meta, reads)
            }
        )

    ch_sylph_routes = sylph_references.flatMap { sample_sketch, reference, database ->
        def sources = (reference.read_sets.input ? ['input'] : []) +
            reference.read_sets.deacon_filtered.collect { deacon_id -> "deacon:${deacon_id}" }

        sources.collect { source -> tuple(source, sample_sketch, reference, database) }
    }

    ch_selected_sylph_reads = ch_read_sets_by_source
        .combine(ch_sylph_routes, by: 0)

    ch_sylph_sketch_jobs = ch_selected_sylph_reads
        .map { source, meta, reads, sample_sketch, reference, database ->
            tuple(sample_sketch, meta, reads)
        }
        .unique()

    SKETCH_READS_WITH_SYLPH(ch_sylph_sketch_jobs)

    ch_sylph_profile_routes = ch_selected_sylph_reads
        .map { source, meta, reads, sample_sketch, reference, database ->
            tuple([sample_sketch, meta], reference, database)
        }

    ch_sylph_sketches_by_route = SKETCH_READS_WITH_SYLPH.out.sketches
        .map { sample_sketch, meta, sketch -> tuple([sample_sketch, meta], sketch) }

    ch_sylph_profile_jobs = ch_sylph_sketches_by_route
        .combine(ch_sylph_profile_routes, by: 0)
        .map { route, sketch, reference, database ->
            tuple(route[1], reference, sketch, database)
        }

    PROFILE_READS_WITH_SYLPH(ch_sylph_profile_jobs)

    ch_sylph_profiles = PROFILE_READS_WITH_SYLPH.out.profiles
        .filter { meta, reference, profile, has_profile_rows ->
            has_profile_rows == 'true'
        }
        .map { meta, reference, profile, has_profile_rows ->
            tuple(meta, reference, profile)
        }

    ch_sylph_profiles_by_reference = ch_sylph_profiles.map { meta, reference, profile ->
        tuple(reference.id, meta, reference, profile)
    }

    ch_sylph_taxonomy_by_reference = sylph_taxonomy.map { reference, sources, taxonomy_metadata ->
        tuple(reference.id, taxonomy_metadata)
    }

    ch_sylph_taxonomy_jobs = ch_sylph_profiles_by_reference
        .combine(ch_sylph_taxonomy_by_reference, by: 0)
        .map { reference_id, meta, reference, profile, taxonomy_metadata ->
            tuple(meta, reference, profile, taxonomy_metadata)
        }

    SUMMARIZE_SYLPH_TAXONOMY(ch_sylph_taxonomy_jobs)

    ch_skope_routes = skope_references.flatMap { reference, query_index ->
        def sources = (reference.read_sets.input ? ['input'] : []) +
            reference.read_sets.deacon_filtered.collect { deacon_id -> "deacon:${deacon_id}" }

        sources.collect { source -> tuple(source, reference, query_index) }
    }

    ch_requested_deacon_sources = ch_sylph_routes
        .map { source, sample_sketch, reference, database -> source }
        .mix(
            ch_skope_routes.map { source, reference, query_index -> source }
        )
        .filter { source -> source != 'input' }
        .unique()
        .map { source -> tuple(source, true) }

    ch_available_deacon_sources = deacon_references
        .map { reference, index -> tuple("deacon:${reference.id}", true) }

    ch_requested_deacon_sources
        .join(ch_available_deacon_sources, by: 0, remainder: true)
        .filter { source, requested, available ->
            requested != null && available == null
        }
        .view { source, requested, available ->
            "WARN: Search reference specifications select unavailable ${source}; no tasks will be created for that selection."
        }

    ch_skope_jobs = ch_read_sets_by_source
        .combine(ch_skope_routes, by: 0)
        .map { source, meta, reads, reference, query_index ->
            tuple(meta, reference, reads, query_index)
        }

    QUERY_READS_WITH_SKOPE(ch_skope_jobs)

    emit:
    deacon = FILTER_READS_WITH_DEACON.out.reads
    filtered_reads = ch_filtered_reads
    sylph = PROFILE_READS_WITH_SYLPH.out.profiles
    sylph_profiles = ch_sylph_profiles
    sylph_taxonomy = SUMMARIZE_SYLPH_TAXONOMY.out.taxonomy_profiles
    skope = QUERY_READS_WITH_SKOPE.out.results
}
