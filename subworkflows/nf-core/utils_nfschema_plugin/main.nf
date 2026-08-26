//
// Subworkflow that uses the nf-schema plugin to validate parameters and render the parameter summary
//

include { paramsSummaryLog   } from 'plugin/nf-schema'
include { validateParameters } from 'plugin/nf-schema'
include { paramsHelp         } from 'plugin/nf-schema'

workflow UTILS_NFSCHEMA_PLUGIN {

    take:
    input_workflow
    validate_params
    parameters_schema
    help
    help_full
    show_hidden
    before_text
    after_text
    command
    cli_typecast

    main:

    if(help || help_full) {
        help_options = [
            beforeText: before_text,
            afterText: after_text,
            command: command,
            showHidden: show_hidden,
            fullHelp: help_full,
        ]
        if(parameters_schema) {
            help_options << [parameters_schema: parameters_schema]
        }
        log.info paramsHelp(
            help_options,
            (help instanceof String && help != "true") ? help : "",
        )
        exit 0
    }

    summary_options = [:]
    if(parameters_schema) {
        summary_options << [parameters_schema: parameters_schema]
    }
    log.info before_text
    log.info paramsSummaryLog(summary_options, input_workflow)
    log.info after_text

    if(validate_params) {
        validateOptions = [:]
        if(parameters_schema) {
            validateOptions << [parameters_schema: parameters_schema]
        }
        if(cli_typecast != null) {
            validateOptions << [cast_cli_params: cli_typecast]
        }
        validateParameters(validateOptions)
    }

    emit:
    dummy_emit = true
}
