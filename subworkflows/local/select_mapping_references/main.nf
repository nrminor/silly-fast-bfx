include { SUBSET_MAPPING_REFERENCE } from '../../../modules/local/subset_mapping_reference'

workflow SELECT_MAPPING_REFERENCES {
    take:
    sylph_profiles
    mapping_references

    main:
    ch_profiles_by_source = sylph_profiles.map { meta, sylph_reference, profile, has_profile_rows ->
        def source = meta.read_set == 'input' ? 'input' : "deacon:${meta.deacon_id}"
        tuple([sylph_reference.id, source], meta, sylph_reference, profile, has_profile_rows)
    }

    ch_mapping_routes = mapping_references.map { reference, fasta ->
        def source = reference.profile.read_set.input ? 'input' : "deacon:${reference.profile.read_set.deacon_filtered}"
        tuple([reference.profile.reference, source], reference, fasta)
    }

    ch_selection_jobs = ch_profiles_by_source
        .combine(ch_mapping_routes, by: 0)
        .map { route, meta, sylph_reference, profile, has_profile_rows, reference, fasta ->
            tuple(meta, reference, profile, fasta)
        }

    SUBSET_MAPPING_REFERENCE(ch_selection_jobs)

    ch_empty_mapping_selections = SUBSET_MAPPING_REFERENCE.out.selections
        .filter { meta, reference, fasta, report, has_selected_records -> has_selected_records == 'false' }
    ch_empty_mapping_selections.view { meta, reference, fasta, report, has_selected_records ->
            "WARN: No mapping reference records selected for ${meta.id}:${reference.id}; no mapping task will be created."
        }

    ch_selected_references = SUBSET_MAPPING_REFERENCE.out.selections
        .filter { meta, reference, fasta, report, has_selected_records -> has_selected_records == 'true' }
        .map { meta, reference, fasta, report, has_selected_records -> tuple(meta, reference, fasta) }

    emit:
    selected = ch_selected_references
    reports = SUBSET_MAPPING_REFERENCE.out.selections
        .map { meta, reference, fasta, report, has_selected_records -> tuple(meta, reference, report) }
}
