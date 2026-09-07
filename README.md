# nrminor/silly-fast-bfx

`nrminor/silly-fast-bfx` is an nf-core-style Nextflow pipeline for comparing rapid metagenomic searches across samples, read sets, reference specifications, and three screening tools: Deacon, Sylph, and Skope.

## Overview

The pipeline begins with one input read set per samplesheet row. It can then run three paths:

1. **Deacon** builds or accepts a minimizer index and filters every input read set. Each Deacon reference specification produces a distinct filtered read set for each sample.
2. **Sylph** sketches selected read sets, profiles each sample sketch against a source-built or prebuilt database, and optionally applies configured taxonomy metadata to meaningful profiles.
3. **Skope** queries selected read sets against a source-built or prebuilt query index and reports one row per target.

Read-set routing is explicit for every Sylph and Skope reference specification. Its `read_sets` block selects the input read set, named Deacon-filtered read sets, or both. The pipeline does not implicitly send every filtered read set to every search. Empty Deacon FASTQs are retained in the results bundle for inspection, but empty filtered read sets are not routed to Sylph or Skope.

## Quick Start

With Nextflow 26.04.6 or later and Docker available, copy and edit [`assets/params.example.yaml`](assets/params.example.yaml) and [`assets/samplesheet.example.csv`](assets/samplesheet.example.csv). Replace the illustrative `/data`, `/refs`, and `example.org` locations, point `input` at your local samplesheet, and set the relevant `skip_*` flags to `false`. Then launch from the directory where Nextflow should create `work/` and the results bundle:

```bash
nextflow run nrminor/silly-fast-bfx \
    -r main \
    -profile docker \
    --monoimage nrminor/silly-fast-bfx:dev \
    -params-file params.yaml
```

> [!WARNING]
> The `main` branch and `nrminor/silly-fast-bfx:dev` image may change without notice until versioned releases begin. Once release tags are available, use a pipeline tag with its corresponding versioned monoimage instead.

## Results Bundle

By default, published results are written under `results/`:

```text
results/
├── pipeline_info/
│   ├── samplesheet.csv
│   ├── software_versions.yml
│   ├── execution_report.html
│   ├── execution_timeline.html
│   ├── execution_trace.txt
│   └── pipeline_dag.html
├── references/<tool>/<reference-id>/source.sha256
├── deacon/
│   ├── summaries/<reference-id>/<sample-id>.summary.json
│   └── reads/<reference-id>/<sample-id>.fastq.gz
├── sylph/
│   ├── profiles/<reference-id>/<sample-id>__<read-set>.profile.tsv
│   └── taxonomy/<reference-id>/<sample-id>__<read-set>.sylphmpa
└── skope/<reference-id>/<sample-id>__<read-set>.skope.tsv
```

`pipeline_info/` preserves the submitted samplesheet, records workflow and tool versions, and contains Nextflow execution reports. Each `source.sha256` records the observed SHA-256 digest and basename of every source used by that reference specification, including Sylph taxonomy metadata when supplied.

Deacon publishes its official JSON summary and one retained FASTQ for every sample/reference combination. This includes official summaries and valid empty FASTQs when no records pass. Sylph publishes raw profiles even when they contain only the header; taxonomy output is emitted only when the profile has data rows and the reference specification includes taxonomy metadata. Skope TSVs contain target-level rows and never include a `TOTAL` row. In filenames, `<read-set>` is `input` or `deacon-<deacon-id>`.

Built indexes and databases, sample sketches, CBQ read encodings, and downloaded input FASTQs remain Nextflow work artifacts rather than published results.

## Pipeline Configuration

The params YAML names the samplesheet and declares tool-specific reference specifications. Start from the [example YAML](assets/params.example.yaml); use [`nextflow_schema.json`](nextflow_schema.json) for the complete parameter contract and [`assets/samplesheet_schema.json`](assets/samplesheet_schema.json) for the samplesheet contract rather than copying every scientific option into a run guide.

The samplesheet supports three source modes. For users in the O'Connor group, this is the same samplesheet format accepted by NVD:

| Source mode | Samplesheet fields | Behavior |
|---|---|---|
| Exact local FASTQ | `fastq1`, optional `fastq2` | Reads one existing absolute gzip FASTQ path and an optional second path in column order. |
| Grouped local FASTQs | `fastq1_glob`, optional `fastq2_glob` | Resolves every matching gzip FASTQ and emits the sorted `fastq1_glob` matches followed by the sorted `fastq2_glob` matches. |
| SRA-family accession | `srr` | Accepts `SRR`, `ERR`, or `DRR` run accessions and downloads the read data with SRACha. |

Every row also supplies a unique `sample_id` and an Illumina or ONT `platform`. Use exactly one source mode per row. Local FASTQs must be gzip-compressed. FASTQs are processed in order; mate relationships are not preserved. SRA-family accessions may resolve to one or more FASTQs. See the [example samplesheet](assets/samplesheet.example.csv) for the exact-local column layout.

Reference sources use either an absolute local path (`kind: local`) or an HTTPS URL (`kind: https`). Either form may include an expected `sha256`; the pipeline verifies it when supplied and always publishes the observed checksum. Each tool has its own source-built and prebuilt forms:

| Tool | Build from source | Use prebuilt |
|---|---|---|
| Deacon | `fasta` plus optional `build` settings | `index` |
| Sylph | `fastas` plus optional `build` settings | `database` |
| Skope | `targets` plus optional `build` settings | `query_index` |

Every Sylph and Skope reference specification requires `read_sets`. Set `input: true` to search the input read set and list exact Deacon reference IDs under `deacon_filtered` to search those filtered read sets. At least one selection is required. If a selected Deacon ID is unavailable, the pipeline warns and creates no tasks for that selection; an available selection creates downstream work only when filtering retains reads.

`skip_deacon`, `skip_sylph`, and `skip_skope` disable all reference specifications for the named tool without requiring their declarations to be removed. Empty `references` lists also create no work for that tool.

## Containers and Dependencies

The `docker` and `apptainer` profiles enable their respective runtimes while leaving executor and site policy to Nextflow configuration. No runtime profile is selected automatically. `--monoimage` assigns one image to every pipeline process; that image contains the scientific tools and Python runtime, while Nextflow remains on the host. The `:dev` image is the only currently published monoimage.

| Tool | Pipeline role |
|---|---|
| [nf-schema](https://nextflow-io.github.io/nf-schema/latest/) | Validates run parameters and the samplesheet before work begins. |
| [SRACha](https://github.com/rnabioco/sracha-rs) | Validates `SRR`, `ERR`, and `DRR` accessions and acquires their FASTQs. |
| [BQTools](https://github.com/ArcInstitute/bqtools) | Encodes each read set as the CBQ read encoding consumed by Deacon. |
| [Deacon](https://github.com/bede/deacon) | Builds minimizer indexes and produces filtered read sets. |
| [Sylph](https://github.com/bluenote-1577/sylph) | Builds databases, creates sample sketches, and profiles selected read sets. |
| [sylph-tax](https://github.com/bluenote-1577/sylph-tax) | Converts meaningful Sylph profiles into taxonomy summaries using explicit metadata. |
| [Skope](https://github.com/bede/skope) | Builds query indexes and reports target-level containment for selected read sets. |

## Resources and Site Configuration

The default local executor is laptop-first: Nextflow schedules at most 8 CPUs and 12 GB of memory in aggregate. Individual tasks begin with these envelopes from [`conf/modules.config`](conf/modules.config):

| Work | CPUs | Memory | Disk | Time |
|---|---:|---:|---:|---:|
| Samplesheet preservation, accession validation, and checksum recording | 1 | 1 GB | 1 GB | 1 hour |
| Input/reference acquisition and reference verification | 1–4 | 2–4 GB | 20–50 GB | 4–8 hours |
| Deacon index build | 4 | 6 GB | 50 GB | 8 hours |
| Sylph database or Skope query-index build | 6 | 8 GB | 50 GB | 12 hours |
| Read encoding, filtering, sketching, profiling, taxonomy, and querying | 1–4 | 4–6 GB | 10–50 GB | 4–8 hours |

These are initial capacity envelopes, not measured optima. Use Nextflow trace and report data from representative runs to tune them for the reference sizes, read volumes, and executor in use.

A site configuration can override both aggregate local limits and individual process requests without changing the pipeline:

```groovy
executor {
    cpus = 16
    memory = '32 GB'
}

process {
    withName: BUILD_SYLPH_DATABASE {
        cpus = 8
        memory = '16 GB'
        disk = '100 GB'
        time = '24h'
    }
}
```

Supply it with `-c site.config`. Keep executor, queue, accounting, scratch, transfer, and container-cache policy in that site file.

## Development

From a source checkout, bootstrap the locked Mise tools, reference repositories, Pixi development environment, and uv runtime environment, then run all repository checks:

```bash
mise bootstrap
mise run check
```

Run one nf-test file while working on a focused path:

```bash
pixi run --environment dev nf-test test tests/query_reads_with_skope.nf.test
```

The real remote-accession contract test is intentionally separate from the default suite:

```bash
mise run test-remote-sra
```

Build and smoke-test the local `nrminor/silly-fast-bfx:dev` monoimage with:

```bash
mise run container-build
mise run container-test
```

After bootstrap, Mise activates the locked Pixi `dev` environment when entering the repository. With real local paths in `params.yaml`, run directly against those installed dependencies with:

```bash
nextflow run . -profile containerless -params-file params.yaml
```
