include { SUBSET_MAPPING_REFERENCE } from '../../../modules/local/subset_mapping_reference'
include { PREPARE_MAPPING_IDENTITIES } from '../../../modules/local/prepare_mapping_identities'
include { MAP_READS_WITH_MINIMAP2 } from '../../../modules/local/map_reads_with_minimap2'
include { SUMMARIZE_MAPPING_COVERAGE } from '../../../modules/local/summarize_mapping_coverage'
include { RENDER_MAPPING_PILEUPS_WITH_ALIGNOTH } from '../../../modules/local/render_mapping_pileups_with_alignoth'
include { STORE_CLASSIFIED_READS } from '../../../modules/local/store_classified_reads'

workflow MAP_READ_SETS {
    take:
    sylph_profiles
    read_sets
    mapping_references
    mapping_allowlists

    main:
    ch_profiles_by_source = sylph_profiles.map { meta, sylph_reference, profile, has_profile_rows ->
        def source = meta.read_set == 'input' ? 'input' : "deacon:${meta.deacon_id}"
        tuple([sylph_reference.id, source], meta, profile)
    }

    ch_selection_routes = mapping_references.map { reference, fasta ->
        def source = reference.profile.read_set.input ? 'input' : "deacon:${reference.profile.read_set.deacon_filtered}"
        tuple([reference.profile.reference, source], reference, fasta)
    }

    ch_selection_jobs = ch_profiles_by_source
        .combine(ch_selection_routes, by: 0)
        .map { route, meta, profile, reference, fasta -> tuple(meta, reference, profile, fasta) }

    SUBSET_MAPPING_REFERENCE(ch_selection_jobs)

    ch_empty_mapping_selections = SUBSET_MAPPING_REFERENCE.out.selections
        .filter { meta, reference, fasta, report, has_selected_records, profile -> has_selected_records == 'false' }
    ch_empty_mapping_selections.view { meta, reference, fasta, report, has_selected_records, profile ->
        "WARN: No mapping reference records selected for ${meta.id}:${reference.id}; no mapping task will be created."
    }

    ch_selected_references = SUBSET_MAPPING_REFERENCE.out.selections
        .filter { meta, reference, fasta, report, has_selected_records, profile -> has_selected_records == 'true' }
        .map { meta, reference, fasta, report, has_selected_records, profile -> tuple(meta, reference, fasta, profile) }

    ch_selected_mapping_jobs = ch_selected_references.flatMap { profile_meta, reference, fasta, profile ->
        def sources = (reference.read_sets.input ? ['input'] : []) +
            (reference.read_sets.deacon_filtered ?: []).collect { deacon_id -> "deacon:${deacon_id}" }
        sources.collect { source ->
            tuple([profile_meta.id, source], profile_meta, reference, fasta, profile)
        }
    }

    ch_available_read_sets = read_sets.map { meta, reads ->
        def source = meta.read_set == 'input' ? 'input' : "deacon:${meta.deacon_id}"
        tuple([meta.id, source], meta, reads)
    }

    ch_requested_read_sets = ch_available_read_sets
        .combine(ch_selected_mapping_jobs.map { route, profile_meta, reference, fasta, profile -> tuple(route, true) }, by: 0)
        .map { route, meta, reads, requested -> tuple(meta, reads) }
        .unique { meta, reads -> [meta.id, meta.read_set, meta.deacon_id] }

    PREPARE_MAPPING_IDENTITIES(ch_requested_read_sets)

    ch_prepared_read_sets = PREPARE_MAPPING_IDENTITIES.out.identities
        .filter { meta, reads, collisions, read_count, has_reads -> has_reads == 'true' }
        .map { meta, reads, collisions, read_count, has_reads ->
            def source = meta.read_set == 'input' ? 'input' : "deacon:${meta.deacon_id}"
            tuple([meta.id, source], meta, reads, collisions, read_count)
        }

    ch_selected_prepared_read_sets = ch_selected_mapping_jobs
        .combine(ch_prepared_read_sets, by: 0)
        .map { route, profile_meta, reference, fasta, profile, mapping_meta, reads, collisions, read_count ->
            tuple(route, profile_meta, reference, fasta, profile, mapping_meta, reads, collisions, read_count)
        }

    ch_alignment_jobs = ch_selected_prepared_read_sets
        .map { route, profile_meta, reference, fasta, profile, mapping_meta, reads, collisions, read_count ->
            def profile_source = profile_meta.read_set == 'input' ? 'input' : "deacon:${profile_meta.deacon_id}"
            tuple(mapping_meta + [profile_read_set: profile_source], reference, fasta, profile, reads, collisions, read_count)
        }

    MAP_READS_WITH_MINIMAP2(ch_alignment_jobs)

    SUMMARIZE_MAPPING_COVERAGE(MAP_READS_WITH_MINIMAP2.out.alignments)

    ch_read_store_sources = MAP_READS_WITH_MINIMAP2.out.read_store_sources
        .filter { meta, reference, fasta, bam, reads, collisions -> reference.read_store?.enabled != false }
    ch_unrestricted_read_store_jobs = ch_read_store_sources
        .filter { meta, reference, fasta, bam, reads, collisions -> !reference.read_store?.reference_allowlist }
        .map { meta, reference, fasta, bam, reads, collisions ->
            tuple(meta, reference, fasta, bam, reads, collisions, [])
        }
    ch_allowed_read_store_jobs = ch_read_store_sources
        .filter { meta, reference, fasta, bam, reads, collisions -> reference.read_store?.reference_allowlist }
        .map { meta, reference, fasta, bam, reads, collisions ->
            tuple(reference.id, meta, reference, fasta, bam, reads, collisions)
        }
        .combine(mapping_allowlists, by: 0)
        .map { reference_id, meta, reference, fasta, bam, reads, collisions, allowlist ->
            tuple(meta, reference, fasta, bam, reads, collisions, allowlist)
        }

    ch_read_store_jobs = ch_unrestricted_read_store_jobs.mix(ch_allowed_read_store_jobs)
    STORE_CLASSIFIED_READS(ch_read_store_jobs)

    ch_pileup_jobs = SUMMARIZE_MAPPING_COVERAGE.out.coverage
        .filter { meta, reference, fasta, bam, csi, counts, coverage, intervals -> reference.pileups?.enabled != false }
        .map { meta, reference, fasta, bam, csi, counts, coverage, intervals ->
            tuple(
                meta,
                reference,
                fasta,
                bam,
                csi,
                counts,
                coverage,
                intervals,
                reference.pileups?.max_read_depth ?: 500,
            )
        }

    RENDER_MAPPING_PILEUPS_WITH_ALIGNOTH(ch_pileup_jobs)

    emit:
    selected = ch_selected_references
    reports = SUBSET_MAPPING_REFERENCE.out.selections
        .map { meta, reference, fasta, report, has_selected_records, profile -> tuple(meta, reference, report) }
    alignments = MAP_READS_WITH_MINIMAP2.out.alignments
    coverage = SUMMARIZE_MAPPING_COVERAGE.out.coverage
    pileups = RENDER_MAPPING_PILEUPS_WITH_ALIGNOTH.out.pileups
    classified_reads = STORE_CLASSIFIED_READS.out.stores
}
