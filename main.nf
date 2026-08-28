#!/usr/bin/env nextflow

include { UTILS_NFSCHEMA_PLUGIN } from './subworkflows/nf-core/utils_nfschema_plugin'
include { GATHER_INPUT_READS    } from './subworkflows/local/gather_input_reads'
include { PREPARE_REFERENCES    } from './subworkflows/local/prepare_references'
include { SCREEN_READ_SETS      } from './subworkflows/local/screen_read_sets'
include { validate              } from 'plugin/nf-schema'

workflow {
    main:
    if (params.version) {
        println "${workflow.manifest.name} v${workflow.manifest.version}"
        exit 0
    }

    parameters_schema = "${projectDir}/nextflow_schema.json"

    UTILS_NFSCHEMA_PLUGIN(
        workflow,
        false,
        parameters_schema,
        params.help,
        params.help_full,
        params.show_hidden,
        '',
        '',
        'nextflow run nrminor/silly-fast-bfx --help',
        false,
    )

    if (params.validate_params) {
        validate(params, parameters_schema)
    }

    deacon_references = params.get('deacon')?.references ?: []
    sylph_references = params.get('sylph')?.references ?: []
    skope_references = params.get('skope')?.references ?: []

    deacon_enabled = !params.skip_deacon && !deacon_references.isEmpty()
    sylph_enabled = !params.skip_sylph && !sylph_references.isEmpty()
    skope_enabled = !params.skip_skope && !skope_references.isEmpty()

    ch_versions = channel.topic('versions')

    GATHER_INPUT_READS(params.input)

    active_deacon_references = deacon_references.findAll { deacon_enabled }
    active_sylph_references = sylph_references.findAll { sylph_enabled }
    active_skope_references = skope_references.findAll { skope_enabled }

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
