#!/usr/bin/env nextflow

include { UTILS_NFSCHEMA_PLUGIN } from './subworkflows/nf-core/utils_nfschema_plugin'
include { GATHER_INPUT_READS    } from './subworkflows/local/gather_input_reads'
include { validate              } from 'plugin/nf-schema'

workflow {
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

    if (deacon_enabled) {
        error 'Deacon screening is available in a later review unit'
    }
    if (sylph_enabled) {
        error 'Sylph screening is available in a later review unit'
    }
    if (skope_enabled) {
        error 'Skope screening is available in a later review unit'
    }

    GATHER_INPUT_READS(params.input)
}
