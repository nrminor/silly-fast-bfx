#!/usr/bin/env nextflow

include { UTILS_NFSCHEMA_PLUGIN } from './subworkflows/nf-core/utils_nfschema_plugin'

workflow {
    if (params.version) {
        println "${workflow.manifest.name} v${workflow.manifest.version}"
        exit 0
    }

    UTILS_NFSCHEMA_PLUGIN(
        workflow,
        params.validate_params,
        null,
        params.help,
        params.help_full,
        params.show_hidden,
        '',
        '',
        'nextflow run nrminor/silly-fast-bfx --help',
        false,
    )
}
