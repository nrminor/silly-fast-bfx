process ENCODE_READS_WITH_BQTOOLS {
    tag "${meta.id}"

    input:
    tuple val(meta), path(reads, stageAs: 'reads??????/*', arity: '1..*')

    output:
    tuple val(meta), path('reads??????/*.cbq', arity: '1..*'), emit: encodings
    path 'versions.yml', topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    set -o pipefail
    shopt -s nullglob

    staged_reads=(reads??????/*)
    encode_args=(
        --mode cbq
        --block-size 128K
        --level 3
        --threads ${task.cpus}
    )

    printf '%s\n' "\${staged_reads[@]}" |
        bqtools encode \
            "\${encode_args[@]}" \
            --manifest /dev/stdin

    encoded_reads=(reads??????/*.cbq)
    if (( \${#encoded_reads[@]} != \${#staged_reads[@]} )); then
        printf 'Expected %s CBQ files, but bqtools encoded %s\n' \
            "\${#staged_reads[@]}" \
            "\${#encoded_reads[@]}" >&2
        exit 1
    fi

    BQTOOLS_VERSION="\$(bqtools --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bqtools: "\${BQTOOLS_VERSION#bqtools }"
    END_VERSIONS
    """

    stub:
    """
    staged_reads=(reads??????/*)
    for read in "\${staged_reads[@]}"; do
        output="\${read%.gz}"
        output="\${output%.zst}"
        output="\${output%.*}.cbq"
        printf 'stub cbq' > "\${output}"
    done
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bqtools: "stub"
    END_VERSIONS
    """
}
