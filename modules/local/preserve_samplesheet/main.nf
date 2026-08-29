process PRESERVE_SAMPLESHEET {

    input:
    path samplesheet, stageAs: 'submitted.csv'

    output:
    path 'samplesheet.csv', emit: samplesheet
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    cp submitted.csv samplesheet.csv

    COREUTILS_VERSION="\$(cp --version | head -n 1 | cut -d ' ' -f 4)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coreutils: "\${COREUTILS_VERSION}"
    END_VERSIONS
    """

    stub:
    """
    cp submitted.csv samplesheet.csv
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coreutils: "stub"
    END_VERSIONS
    """
}
