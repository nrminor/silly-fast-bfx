process VERIFY_REFERENCE {
    tag "${tool}:${reference.id}:${role}"

    input:
    tuple val(tool), val(reference), val(role), val(order), val(source), path(artifact)

    output:
    tuple val(tool), val(reference), val(role), val(order), val(source), path(artifact), path('observed.sha256'), emit: artifacts
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def expected_arg = source.sha256 ? "--expected ${source.sha256}" : ''
    def location = source.path ?: source.url
    """
    verify_reference.py \
        --artifact ${artifact} \
        --location "${location}" \
        ${expected_arg} \
        --output observed.sha256 \
        --versions-output versions.yml \
        --process ${task.process}
    """

    stub:
    def expected_arg = source.sha256 ? "--expected ${source.sha256}" : ''
    def location = source.path ?: source.url
    """
    verify_reference.py \
        --artifact ${artifact} \
        --location "${location}" \
        ${expected_arg} \
        --output observed.sha256 \
        --versions-output versions.yml \
        --process ${task.process}
    """
}
