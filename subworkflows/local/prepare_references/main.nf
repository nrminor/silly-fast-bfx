include { DOWNLOAD_REFERENCE         } from '../../../modules/local/download_reference'
include { VERIFY_REFERENCE           } from '../../../modules/local/verify_reference'
include { RECORD_REFERENCE_CHECKSUMS } from '../../../modules/local/record_reference_checksums'

def rejectDuplicateReferenceIds(tool, references) {
    def duplicates = references
        .groupBy { reference -> reference.id }
        .findAll { id, matches -> matches.size() > 1 }
        .keySet()
        .sort()

    if (duplicates) {
        throw new IllegalArgumentException("Duplicate ${tool} reference ID: ${duplicates.join(', ')}")
    }
}

def logicalBasename(source) {
    def remote_path = source.kind == 'https' ? new java.net.URI(source.url).rawPath : null
    def basename = source.kind == 'local'
        ? java.nio.file.Paths.get(source.path).fileName?.toString()
        : remote_path && !remote_path.endsWith('/') ? remote_path.tokenize('/').last() : null

    if (
        !basename ||
        basename.startsWith('-') ||
        basename.startsWith('.command') ||
        basename in ['.', '..', '.exitcode', 'observed.sha256', 'source.sha256', 'versions.yml']
    ) {
        throw new IllegalArgumentException("Reference source has no usable logical basename: ${source.path ?: source.url}")
    }
    if (basename.find(/[\x00-\x1f\x7f*?\[\]{}\\]/)) {
        throw new IllegalArgumentException("Reference source has an unsafe logical basename: ${basename}")
    }

    basename
}

def acquisitionKey(source) {
    source.kind == 'local'
        ? java.nio.file.Paths.get(source.path).toAbsolutePath().normalize().toString()
        : source.url
}

def declaration(tool, reference, role, order, source) {
    def basename = logicalBasename(source)
    [
        acquisition_key: acquisitionKey(source),
        tool: tool,
        reference: reference,
        role: role,
        order: order,
        source: source + [logical_basename: basename],
    ]
}

def declarationsForReference(tool, reference) {
    def declarations

    if (tool == 'deacon') {
        def role = reference.fasta ? 'fasta' : 'index'
        declarations = [declaration(tool, reference, role, 0, reference[role])]
    } else if (tool == 'sylph') {
        def primary = reference.fastas
            ? reference.fastas.withIndex().collect { source, index ->
                declaration(tool, reference, 'fasta', index, source)
            }
            : [declaration(tool, reference, 'database', 0, reference.database)]
        def taxonomy_offset = primary.size()
        def taxonomy = (reference.taxonomy?.metadata ?: []).withIndex().collect { source, index ->
            declaration(tool, reference, 'taxonomy_metadata', taxonomy_offset + index, source)
        }
        declarations = primary + taxonomy
    } else {
        def role = reference.targets ? 'targets' : 'query_index'
        declarations = [declaration(tool, reference, role, 0, reference[role])]
    }

    def duplicates = declarations
        .groupBy { item -> item.source.logical_basename }
        .findAll { basename, matches -> matches.size() > 1 }
        .keySet()
        .sort()
    if (duplicates) {
        throw new IllegalArgumentException(
            "Duplicate logical basename in ${tool} reference '${reference.id}': ${duplicates.join(', ')}",
        )
    }

    declarations
}

def allDeclarations(deacon, sylph, skope) {
    rejectDuplicateReferenceIds('Deacon', deacon)
    rejectDuplicateReferenceIds('Sylph', sylph)
    rejectDuplicateReferenceIds('Skope', skope)

    deacon.collectMany { reference -> declarationsForReference('deacon', reference) } +
        sylph.collectMany { reference -> declarationsForReference('sylph', reference) } +
        skope.collectMany { reference -> declarationsForReference('skope', reference) }
}

def resolvedSources(entries) {
    def ordered = entries.sort { left, right -> left.order <=> right.order }
    def tool = ordered.first().tool
    def reference = ordered.first().reference
    def enriched = ordered.collect { entry ->
        entry + [source: entry.source + [observed_sha256: entry.observed_sha256]]
    }
    def primary = enriched.findAll { entry -> entry.role != 'taxonomy_metadata' }
    def taxonomy = enriched.findAll { entry -> entry.role == 'taxonomy_metadata' }

    [
        tool: tool,
        reference: reference,
        sources: enriched.collect { entry ->
            [
                role: entry.role,
                order: entry.order,
                location: entry.acquisition_key,
                logical_basename: entry.source.logical_basename,
                observed_sha256: entry.source.observed_sha256,
            ]
        },
        primary_sources: primary.collect { entry -> entry.source },
        primary_artifacts: primary.collect { entry -> entry.artifact },
        taxonomy_sources: taxonomy.collect { entry -> entry.source },
        taxonomy_artifacts: taxonomy.collect { entry -> entry.artifact },
    ]
}

workflow PREPARE_REFERENCES {
    take:
    deacon_references
    sylph_references
    skope_references

    main:
    declarations = allDeclarations(deacon_references, sylph_references, skope_references)
    ch_declarations = channel.fromList(declarations)

    ch_expectations = ch_declarations
        .map { item -> tuple(item.acquisition_key, item.source.sha256 ?: '') }
        .groupTuple()
        .map { location, expected ->
            tuple(location, expected.findAll().collect { it.toLowerCase() }.unique().sort())
        }

    ch_unique_sources = ch_declarations
        .map { item -> tuple(item.acquisition_key, item.source) }
        .unique { location, source -> location }
        .branch {
            local: it[1].kind == 'local'
            https: it[1].kind == 'https'
        }

    ch_local_artifacts = ch_unique_sources.local.map { location, source ->
        tuple(
            location,
            source.logical_basename,
            file(location, checkIfExists: true, glob: false),
        )
    }

    ch_https_requests = ch_unique_sources.https.map { location, source ->
        tuple(location, source.logical_basename)
    }

    DOWNLOAD_REFERENCE(ch_https_requests)

    ch_acquired_artifacts = ch_local_artifacts.mix(DOWNLOAD_REFERENCE.out.artifacts)

    VERIFY_REFERENCE(ch_acquired_artifacts.combine(ch_expectations, by: 0))

    ch_verified_artifacts = VERIFY_REFERENCE.out.artifacts.map {
        location, basename, artifact, observed_sha256 ->
        tuple(location, basename, artifact, observed_sha256.text.trim())
    }

    ch_resolved_entries = ch_declarations
        .map { item -> tuple(item.acquisition_key, item) }
        .combine(ch_verified_artifacts, by: 0)
        .map { location, item, basename, artifact, observed_sha256 ->
            tuple(
                [item.tool, item.reference.id],
                item + [artifact: artifact, observed_sha256: observed_sha256],
            )
        }

    ch_resolved_sources = ch_resolved_entries
        .groupTuple()
        .map { key, entries -> resolvedSources(entries) }

    ch_reference_sources = ch_resolved_sources.branch {
        deacon: it.tool == 'deacon'
        sylph: it.tool == 'sylph'
        skope: it.tool == 'skope'
    }

    ch_deacon_sources = ch_reference_sources.deacon.map { item ->
        tuple(item.reference, item.primary_sources.first(), item.primary_artifacts.first())
    }
    ch_sylph_sources = ch_reference_sources.sylph.map { item ->
        tuple(item.reference, item.primary_sources, item.primary_artifacts)
    }
    ch_sylph_taxonomy = ch_reference_sources.sylph
        .filter { item -> !item.taxonomy_artifacts.isEmpty() }
        .map { item -> tuple(item.reference, item.taxonomy_sources, item.taxonomy_artifacts) }
    ch_skope_sources = ch_reference_sources.skope.map { item ->
        tuple(item.reference, item.primary_sources.first(), item.primary_artifacts.first())
    }

    RECORD_REFERENCE_CHECKSUMS(
        ch_resolved_sources.map { item -> tuple(item.tool, item.reference, item.sources) },
    )

    emit:
    deacon_sources = ch_deacon_sources
    sylph_sources = ch_sylph_sources
    sylph_taxonomy = ch_sylph_taxonomy
    skope_sources = ch_skope_sources
    checksum_manifests = RECORD_REFERENCE_CHECKSUMS.out.manifests
}
