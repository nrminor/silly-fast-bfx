#!/usr/bin/env nextflow

include { UTILS_NFSCHEMA_PLUGIN } from './subworkflows/nf-core/utils_nfschema_plugin'
include { GATHER_INPUT_READS    } from './subworkflows/local/gather_input_reads'
include { PREPARE_REFERENCES    } from './subworkflows/local/prepare_references'
include { SCREEN_READ_SETS      } from './subworkflows/local/screen_read_sets'
include { validate              } from 'plugin/nf-schema'

def describeReadSets(read_sets) {
    ((read_sets?.input ? ['input'] : []) +
        (read_sets?.deacon_filtered ?: []).collect { deacon_id -> "deacon:${deacon_id}" })
        .join(', ')
}

def chooseLaunchColors(ansi_enabled) {
    ansi_enabled
        ? [reset: '\033[0m', bold: '\033[1m', dim: '\033[2m', blue: '\033[0;34m', green: '\033[0;32m']
        : [reset: '', bold: '', dim: '', blue: '', green: '']
}

def formatReference(reference, fields, colors) {
    def configured_fields = fields.findAll { _label, value -> value != null }
    ["  ${reference.id}"] + configured_fields.collect { label, value ->
        "    ${colors.blue}${label}: ${colors.green}${value}${colors.reset}"
    }
}

workflow {
    main:
    if (params.version) {
        println "${workflow.manifest.name} v${workflow.manifest.version}"
        exit 0
    }

    parameters_schema = "${projectDir}/nextflow_schema.json"

    deacon_references = params.get('deacon')?.references ?: []
    sylph_references = params.get('sylph')?.references ?: []
    skope_references = params.get('skope')?.references ?: []

    deacon_enabled = !params.skip_deacon && !deacon_references.isEmpty()
    sylph_enabled = !params.skip_sylph && !sylph_references.isEmpty()
    skope_enabled = !params.skip_skope && !skope_references.isEmpty()

    active_deacon_references = deacon_references.findAll { deacon_enabled }
    active_sylph_references = sylph_references.findAll { sylph_enabled }
    active_skope_references = skope_references.findAll { skope_enabled }

    ansi_enabled = workflow.session.ansiLog &&
        !workflow.session.config.navigate('validation.monochromeLogs')
    colors = chooseLaunchColors(ansi_enabled)

    deacon_summary = active_deacon_references.collect { reference ->
        formatReference(reference, [
            'minimum index hits': reference.filter?.abs_threshold,
            'minimum hit proportion': reference.filter?.rel_threshold,
            'minimum minimizer complexity': reference.filter?.complexity_threshold,
            'discard matching reads': reference.filter?.deplete ? true : null,
        ], colors)
    }.flatten()

    sylph_summary = active_sylph_references.collect { reference ->
        formatReference(reference, [
            'read sets': describeReadSets(reference.read_sets),
            'sample sketch compression': reference.sample_sketch?.compression,
            'minimum ANI': reference.profile?.minimum_ani,
            'minimum k-mer multiplicity': reference.profile?.min_count_correct,
            'minimum sampled k-mers': reference.profile?.min_number_kmers,
        ], colors)
    }.flatten()

    skope_summary = active_skope_references.collect { reference ->
        formatReference(reference, [
            'read sets': describeReadSets(reference.read_sets),
            'syncmer abundance thresholds': reference.query?.abundance_thresholds?.join(', '),
            'confidence intervals': reference.query?.confidence ? 'enabled' : null,
            'unique target syncmers': reference.query?.discriminatory ? 'enabled' : null,
            'sample base limit': reference.query?.limit,
        ], colors)
    }.flatten()

    search_summary = [
        active_deacon_references ? ["${colors.bold}Deacon searches${colors.reset}"] + deacon_summary + [''] : [],
        active_sylph_references ? ["${colors.bold}Sylph searches${colors.reset}"] + sylph_summary + [''] : [],
        active_skope_references ? ["${colors.bold}Skope searches${colors.reset}"] + skope_summary + [''] : [],
    ].flatten()

    pipeline_name = workflow.manifest.name.tokenize('/').last()
    launch_summary = ([
        "${colors.bold}${pipeline_name} (pre-versioned)${colors.reset}",
        "-${colors.dim}----------------------------------------------------${colors.reset}-",
        '',
    ] + (search_summary ?: ["${colors.bold}No searches enabled${colors.reset}", '']) + [
        "${colors.bold}Input and output${colors.reset}",
        "  ${colors.blue}samplesheet: ${colors.green}${params.input}${colors.reset}",
        "  ${colors.blue}results: ${colors.green}${params.results}${colors.reset}",
    ]).join('\n') + '\n'

    UTILS_NFSCHEMA_PLUGIN(
        workflow,
        false,
        parameters_schema,
        params.help,
        params.help_full,
        params.show_hidden,
        launch_summary,
        '',
        'nextflow run nrminor/silly-fast-bfx --help',
        false,
    )

    if (params.validate_params) {
        validate(params, parameters_schema)
    }

    ch_versions = channel.topic('versions')

    GATHER_INPUT_READS(params.input)

    PREPARE_REFERENCES(
        active_deacon_references,
        active_sylph_references,
        active_skope_references,
    )

    SCREEN_READ_SETS(
        GATHER_INPUT_READS.out.reads,
        PREPARE_REFERENCES.out.deacon,
        PREPARE_REFERENCES.out.sylph,
        PREPARE_REFERENCES.out.sylph_taxonomy,
        PREPARE_REFERENCES.out.skope,
    )

    ch_workflow_version = channel.of("""
    Workflow:
        ${workflow.manifest.name}: v${workflow.manifest.version}
        Nextflow: ${workflow.nextflow.version}
    """.stripIndent().trim())

    ch_software_versions = ch_versions
        .map { versions -> versions.text.trim() }
        .unique()
        .mix(ch_workflow_version)
        .collectFile(
            storeDir: "${params.results}/pipeline_info",
            name: 'software_versions.yml',
            sort: true,
            newLine: true,
        )

    publish:
    submitted_samplesheet = GATHER_INPUT_READS.out.samplesheet
}

output {
    submitted_samplesheet {
        path 'pipeline_info'
    }
}
