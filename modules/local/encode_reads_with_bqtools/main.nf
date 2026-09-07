process ENCODE_READS_WITH_BQTOOLS {
    tag "${meta.id}"

    input:
    tuple val(meta), path(reads, stageAs: 'reads??????/*', arity: '1..*')

    output:
    tuple val(meta), path("${meta.id}.cbq"), emit: encodings
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

    if (( \${#staged_reads[@]} == 1 )); then
        bqtools encode \
            "\${encode_args[@]}" \
            --output ${meta.id}.cbq \
            "\${staged_reads[0]}"
    else
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

        bqtools cat \
            "\${encoded_reads[@]}" \
            --threads ${task.cpus} \
            --output ${meta.id}.cbq
        rm -- "\${encoded_reads[@]}"
    fi

    BQTOOLS_VERSION="\$(bqtools --version)"
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bqtools: "\${BQTOOLS_VERSION#bqtools }"
    END_VERSIONS
    """

    stub:
    """
    printf 'stub cbq' > ${meta.id}.cbq
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bqtools: "stub"
    END_VERSIONS
    """
}
