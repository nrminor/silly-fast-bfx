include { DOWNLOAD_REFERENCE         } from '../../../modules/local/download_reference'
include { VERIFY_REFERENCE           } from '../../../modules/local/verify_reference'
include { RECORD_REFERENCE_CHECKSUMS } from '../../../modules/local/record_reference_checksums'
include { BUILD_DEACON_INDEX          } from '../../../modules/local/build_deacon_index'
include { BUILD_SYLPH_DATABASE        } from '../../../modules/local/build_sylph_database'
include { BUILD_SKOPE_QUERY_INDEX     } from '../../../modules/local/build_skope_query_index'

workflow PREPARE_REFERENCES {
    take:
    deacon_references
    sylph_references
    skope_references

    main:
    normalized_deacon_references = deacon_references.collect { reference ->
        def normalized = reference + [
            filter: [
                abs_threshold: 2,
                rel_threshold: 0.01,
                prefix_length: 0,
                complexity_threshold: null,
                deplete: false,
            ] + (reference.filter ?: [:]),
        ]

        reference.fasta
            ? normalized + [
                build: [kmer_length: 31, window_size: 15] + (reference.build ?: [:]),
            ]
            : normalized
    }

    normalized_sylph_references = sylph_references.collect { reference ->
        def build = reference.fastas
            ? [
                kmer_length: 31,
                compression: 200,
                individual_records: false,
                min_spacing: 30,
            ] + (reference.build ?: [:])
            : null
        def sample_sketch = [
            kmer_length: build?.kmer_length ?: 31,
            compression: build?.compression ?: 200,
            no_dedup: false,
        ] + (reference.sample_sketch ?: [:])

        if (build && sample_sketch.kmer_length != build.kmer_length) {
            error "Sylph reference '${reference.id}' sample_sketch.kmer_length must match build.kmer_length."
        }
        if (build && sample_sketch.compression > build.compression) {
            error "Sylph reference '${reference.id}' sample_sketch.compression cannot exceed build.compression."
        }

        def normalized = reference + [
            sample_sketch: sample_sketch,
            profile: [
                minimum_ani: 95,
                min_count_correct: 3,
                min_number_kmers: 50,
                estimate_unknown: false,
                estimate_read_counts: false,
                read_seq_id: null,
            ] + (reference.profile ?: [:]),
        ]

        reference.fastas
            ? normalized + [
                build: build,
            ]
            : normalized
    }

    normalized_skope_references = skope_references.collect { reference ->
        def query = [
            fraction: 1.0,
            abundance_thresholds: [10],
            discriminatory: false,
            confidence: false,
            limit: null,
        ] + (reference.query ?: [:])
        def normalized = reference + [
            query: query + [fraction: query.fraction.toDouble()],
        ]
        def build = reference.targets
            ? [
                kmer_length: 31,
                smer_length: 9,
                fraction: 1.0,
                individual: false,
            ] + (reference.build ?: [:])
            : null

        reference.targets
            ? normalized + [
                build: build + [
                    fraction: build.fraction.toDouble(),
                    positions: normalized.query.confidence,
                ],
            ]
            : normalized
    }

    ch_deacon_source_uses = channel.fromList(normalized_deacon_references).map { reference ->
        def role = reference.fasta ? 'fasta' : 'index'
        def source = reference[role]
        tuple(source.path ?: source.url, 'deacon', reference, role, 0, source)
    }

    ch_sylph_source_uses = channel.fromList(normalized_sylph_references).flatMap { reference ->
        def primary = reference.fastas
            ? reference.fastas.withIndex().collect { source, order ->
                tuple(source.path ?: source.url, 'sylph', reference, 'fasta', order, source)
            }
            : [tuple(reference.database.path ?: reference.database.url, 'sylph', reference, 'database', 0, reference.database)]

        primary + (reference.taxonomy?.metadata ?: []).withIndex().collect { source, order ->
            tuple(source.path ?: source.url, 'sylph', reference, 'taxonomy_metadata', primary.size() + order, source)
        }
    }

    ch_skope_source_uses = channel.fromList(normalized_skope_references).map { reference ->
        def role = reference.targets ? 'targets' : 'query_index'
        def source = reference[role]
        tuple(source.path ?: source.url, 'skope', reference, role, 0, source)
    }

    ch_source_uses = ch_deacon_source_uses
        .mix(ch_sylph_source_uses)
        .mix(ch_skope_source_uses)
        .map { location, tool, reference, role, order, source ->
            def acquisition_key = source.kind == 'local'
                ? java.nio.file.Paths.get(location).toAbsolutePath().normalize().toString()
                : location
            tuple(acquisition_key, tool, reference, role, order, source)
        }

    ch_unique_sources = ch_source_uses
        .map { location, tool, reference, role, order, source -> tuple(location, source) }
        .unique { location, source -> location }
        .branch {
            local: it[1].kind == 'local'
            https: it[1].kind == 'https'
        }

    ch_local_artifacts = ch_unique_sources.local.map { location, source ->
        tuple(location, file(location, checkIfExists: true, glob: false))
    }

    ch_https_requests = ch_unique_sources.https.map { location, source ->
        tuple(location, new java.net.URI(source.url).path.tokenize('/').last())
    }

    DOWNLOAD_REFERENCE(ch_https_requests)

    ch_acquired_artifacts = ch_local_artifacts.mix(DOWNLOAD_REFERENCE.out.artifacts)

    ch_verification_jobs = ch_source_uses
        .combine(ch_acquired_artifacts, by: 0)
        .map { location, tool, reference, role, order, source, artifact ->
            tuple(tool, reference, role, order, source, artifact)
        }

    VERIFY_REFERENCE(ch_verification_jobs)

    ch_verified_sources = VERIFY_REFERENCE.out.artifacts.map {
        tool, reference, role, order, source, artifact, observed_sha256_file ->

        tuple(
            tool,
            reference,
            role,
            order,
            source + [
                logical_basename: artifact.name,
                observed_sha256: observed_sha256_file.text.trim(),
            ],
            artifact,
        )
    }

    ch_reference_sources = ch_verified_sources.branch {
        deacon: it[0] == 'deacon'
        sylph: it[0] == 'sylph'
        skope: it[0] == 'skope'
    }

    ch_deacon_sources = ch_reference_sources.deacon.map {
        tool, reference, role, order, source, artifact -> tuple(reference, source, artifact)
    }

    ch_deacon_build_uses = ch_deacon_sources
        .filter { reference, source, artifact -> reference.fasta }
        .map { reference, source, fasta ->
            tuple(
                [
                    observed_sha256: source.observed_sha256,
                    settings: reference.build,
                ],
                reference,
                fasta,
            )
        }

    ch_deacon_source_builds = ch_deacon_build_uses
        .map { build, reference, fasta -> tuple(build, fasta) }
        .unique { build, fasta -> build }

    BUILD_DEACON_INDEX(ch_deacon_source_builds)

    ch_deacon_built_references = ch_deacon_build_uses
        .map { build, reference, fasta -> tuple(build, reference) }
        .combine(BUILD_DEACON_INDEX.out.indexes, by: 0)
        .map { build, reference, index -> tuple(reference, index) }

    ch_deacon_prebuilt_references = ch_deacon_sources
        .filter { reference, source, artifact -> reference.index }
        .map { reference, source, index -> tuple(reference, index) }

    ch_deacon_references = ch_deacon_prebuilt_references.mix(ch_deacon_built_references)

    ch_sylph_grouped = ch_reference_sources.sylph
        .map { tool, reference, role, order, source, artifact ->
            tuple(
                reference,
                [role: role, order: order, source: source, artifact: artifact],
            )
        }
        .groupTuple()
        .map { reference, entries ->
            tuple(reference, entries.sort { left, right -> left.order <=> right.order })
        }

    ch_sylph_sources = ch_sylph_grouped.map { reference, entries ->
        def primary = entries.findAll { entry -> entry.role != 'taxonomy_metadata' }
        tuple(reference, primary*.source, primary*.artifact)
    }

    ch_sylph_build_uses = ch_sylph_sources
        .filter { reference, sources, artifacts -> reference.fastas }
        .map { reference, sources, fastas ->
            tuple(
                [
                    sources: sources.collect { source ->
                        [
                            observed_sha256: source.observed_sha256,
                            logical_basename: source.logical_basename,
                        ]
                    },
                    settings: reference.build,
                ],
                reference,
                fastas,
            )
        }

    ch_sylph_source_builds = ch_sylph_build_uses
        .map { build, reference, fastas -> tuple(build, fastas) }
        .unique { build, fastas -> build }

    BUILD_SYLPH_DATABASE(ch_sylph_source_builds)

    ch_sylph_built_references = ch_sylph_build_uses
        .map { build, reference, fastas -> tuple(build, reference) }
        .combine(BUILD_SYLPH_DATABASE.out.databases, by: 0)
        .map { build, reference, database ->
            tuple(reference.sample_sketch, reference, database)
        }

    ch_sylph_prebuilt_references = ch_sylph_sources
        .filter { reference, sources, artifacts -> reference.database }
        .map { reference, sources, databases ->
            tuple(reference.sample_sketch, reference, databases[0])
        }

    ch_sylph_references = ch_sylph_prebuilt_references.mix(ch_sylph_built_references)

    ch_sylph_taxonomy = ch_sylph_grouped
        .map { reference, entries ->
            def taxonomy = entries.findAll { entry -> entry.role == 'taxonomy_metadata' }
            tuple(reference, taxonomy*.source, taxonomy*.artifact)
        }
        .filter { reference, sources, artifacts -> !artifacts.isEmpty() }

    ch_skope_sources = ch_reference_sources.skope.map {
        tool, reference, role, order, source, artifact -> tuple(reference, source, artifact)
    }

    ch_skope_build_uses = ch_skope_sources
        .filter { reference, source, artifact -> reference.targets }
        .map { reference, source, targets ->
            tuple(
                [
                    tool: [name: 'skope', version: '0.4.0'],
                    sources: [[
                        observed_sha256: source.observed_sha256,
                        logical_basename: source.logical_basename,
                    ]],
                    settings: reference.build,
                ],
                reference,
                targets,
            )
        }

    ch_skope_source_builds = ch_skope_build_uses
        .map { build, reference, targets -> tuple(build, targets) }
        .unique { build, targets -> build }

    BUILD_SKOPE_QUERY_INDEX(ch_skope_source_builds)

    ch_skope_built_references = ch_skope_build_uses
        .map { build, reference, targets -> tuple(build, reference) }
        .combine(BUILD_SKOPE_QUERY_INDEX.out.query_indexes, by: 0)
        .map { build, reference, query_index -> tuple(reference, query_index) }

    ch_skope_prebuilt_references = ch_skope_sources
        .filter { reference, source, artifact -> reference.query_index }
        .map { reference, source, query_index -> tuple(reference, query_index) }

    ch_skope_references = ch_skope_prebuilt_references.mix(ch_skope_built_references)

    ch_deacon_manifest_jobs = ch_deacon_sources.map { reference, source, artifact ->
        tuple('deacon', reference, [source])
    }
    ch_sylph_manifest_jobs = ch_sylph_grouped.map { reference, entries ->
        tuple('sylph', reference, entries*.source)
    }
    ch_skope_manifest_jobs = ch_skope_sources.map { reference, source, artifact ->
        tuple('skope', reference, [source])
    }
    ch_manifest_jobs = ch_deacon_manifest_jobs
        .mix(ch_sylph_manifest_jobs)
        .mix(ch_skope_manifest_jobs)

    RECORD_REFERENCE_CHECKSUMS(ch_manifest_jobs)

    emit:
    deacon = ch_deacon_references
    deacon_sources = ch_deacon_sources
    sylph = ch_sylph_references
    sylph_sources = ch_sylph_sources
    sylph_taxonomy = ch_sylph_taxonomy
    skope = ch_skope_references
    skope_sources = ch_skope_sources
    checksum_manifests = RECORD_REFERENCE_CHECKSUMS.out.manifests
}
