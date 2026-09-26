# nrminor/silly-fast-bfx

`nrminor/silly-fast-bfx` is an nf-core-style Nextflow pipeline for comparing rapid metagenomic searches across samples, read sets, and tool-specific reference specifications.

## Overview

The pipeline begins with one input read set per samplesheet row. It can then run four paths:

1. **Deacon** builds or accepts a minimizer index and filters every input read set. Each Deacon reference specification produces a distinct filtered read set for each sample.
2. **Sylph** sketches selected read sets, profiles each sample sketch against a source-built or prebuilt database, and optionally applies configured taxonomy metadata to meaningful profiles.
3. **Skope** queries selected read sets against a source-built or prebuilt query index and reports one row per target.
4. **Mapping** uses one configured Sylph profile per sample to select exact full-header records from one explicit FASTA, then competitively maps independently streamed selected read sets with minimap2. It publishes the selected FASTA, coordinate-sorted BAM/CSI, mapper counts, per-reference coverage/Sylph comparisons, depth intervals, optional Alignoth pileups, and a post-alignment classified-read Parquet table.

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
│   └── taxonomy/<reference-id>/
│       ├── <sample-id>__<read-set>.sylphmpa
│       ├── <sample-id>__<read-set>.krona.html (when enabled and nonempty)
│       └── all-samples.krona.html (when at least one chart exists)
├── skope/<reference-id>/<sample-id>__<read-set>.skope.tsv
└── mapping/<reference-id>/<sample-id>/
    ├── <sample-id>__<profile-read-set>.selected.fasta
    ├── <sample-id>__<read-set>__<reference-id>.bam
    ├── <sample-id>__<read-set>__<reference-id>.bam.csi
    ├── <sample-id>__<read-set>__<reference-id>.counts.json
    ├── <sample-id>__<read-set>__<reference-id>.coverage.tsv
    ├── <sample-id>__<read-set>__<reference-id>.coverage.intervals.tsv
    ├── <sample-id>__<read-set>__<reference-id>.classified-reads.parquet
    └── <sample-id>__<read-set>__<reference-id>.pileups/ (when enabled)
```

`pipeline_info/` preserves the submitted samplesheet, records workflow and tool versions, and contains Nextflow execution reports. Each `source.sha256` records the observed SHA-256 digest and basename of every source used by that reference specification, including Sylph taxonomy metadata when supplied.

Deacon publishes its official JSON summary and one retained FASTQ for every sample/reference combination. This includes official summaries and valid empty FASTQs when no records pass. Sylph publishes raw profiles even when they contain only the header; taxonomy output is emitted only when the profile has data rows and the reference specification includes taxonomy metadata. Skope TSVs contain target-level rows and never include a `TOTAL` row. Mapping selection reports in the Nextflow task work directory distinguish filtered-out, resolved, and unresolved `Contig_name` values; a selection has no mapping successor unless it resolves records. In filenames, `<read-set>` is `input` or `deacon-<deacon-id>`.

With Sylph taxonomy metadata configured, `taxonomy.krona` defaults to `true`. Set `taxonomy: {metadata: [...], krona: false}` on a reference specification to keep its `.sylphmpa` summaries without rendering charts. Each standalone HTML chart uses the reported, unscaled `relative_abundance` percentage points from canonical `d__` through `s__` taxonomic ranks only. Cumulative ancestors are counted once; positive parent mass without a reported descendant remains at that parent. `t__` paths and embedded reference-header metadata are excluded. The all-samples chart has independently selectable datasets for each available sample/read set **within the same Sylph reference specification**, rather than summing percentages across samples. If canonical abundance is zero or absent, no chart or comparative dataset is produced. The intermediate Krona TSV remains a work artifact.

Built indexes and databases, sample sketches, CBQ read encodings, and downloaded input FASTQs remain Nextflow work artifacts rather than published results.

## Pipeline Configuration

The params YAML names the samplesheet and declares tool-specific reference specifications. Start from the [example YAML](assets/params.example.yaml); use [`nextflow_schema.json`](nextflow_schema.json) for the complete parameter contract and [`assets/samplesheet_schema.json`](assets/samplesheet_schema.json) for the samplesheet contract rather than copying every scientific option into a run guide.

Set `work_dir: /scratch/my-run/work` in the params YAML to choose Nextflow's work directory without passing `-work-dir`. When omitted, it defaults to `NXF_WORK` when set, otherwise `work/` in the launch directory. This is separate from `results`, which controls the published results bundle.

`bqtools.block_size` controls the CBQ virtual block size for every sample encoded for Deacon, regardless of platform. It defaults to `128K`; increase it for long reads when needed:

```yaml
bqtools:
  block_size: 1M
```

Use a positive integer string in bytes (for example, `"131072"`) or an integer with a `K`, `M`, or `G` suffix (powers of 1024, case-insensitive). The size is in bytes, not bases or records. BQTools 0.5.14 concatenation inherits the input CBQ header's block size; its `cat --block-size` flag does not override that size. All inputs to concatenation are encoded with the same run-wide setting.

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
| Skope | one `targets` source or an ordered list plus optional `build` settings | `query_index` |

Every Sylph and Skope reference specification requires `read_sets`. Set `input: true` to search the input read set and list exact Deacon reference IDs under `deacon_filtered` to search those filtered read sets. Either property may be omitted when only the other selects read sets; at least one selection is required. If a selected Deacon ID is unavailable, the pipeline warns and creates no tasks for that selection; an available selection creates downstream work only when filtering retains reads.

For a Skope target represented by a FASTA of equal-length k-mers, set these build options on its reference specification:

```yaml
build:
  kmer_length: 31 # Match the sequence length in the target FASTA.
  all_kmers: true
  fraction: 1.0
  individual: false
```

`all_kmers` bypasses syncmer selection and ignores `smer_length`; it defaults to `false`. Fraction sampling still applies, so keep `fraction: 1.0` to retain all canonical k-mers. With `individual: false`, records form one target without concatenating their sequences, and containment is measured over distinct canonical k-mers, not record count. Duplicate k-mers and reverse complements do not add independent evidence. Target grouping remains independent: `individual: true` instead reports each record as a separate target. Selection settings are embedded in the index and automatically used during queries.

`targets` also accepts an ordered nonempty list of source maps. Multiple FASTAs are staged as a directory, so each file remains a separate target named from its filename in the output TSV. Checksum provenance preserves the source basenames. Target filenames must not collide when staged together; Skope also rejects duplicate derived target names. Leave `build.individual` at its default of `false` for a target list; use a single source map with `individual: true` when each FASTA record must remain a separate target.

`skip_deacon`, `skip_sylph`, `skip_skope`, and `skip_mapping` disable all reference specifications for the named path without requiring their declarations to be removed. Empty `references` lists also create no work. `skip_mapping` leaves independently configured Sylph profiling enabled.

Mapping reference selection uses one explicit `mapping.references` entry per configuration. Its `profile` names exactly one Sylph reference specification and one profile read set; its `fasta` is the sole candidate FASTA. Optional inclusive `select.sequence_abundance` and `select.adjusted_ani` bounds combine with AND on raw Sylph values: `Sequence_abundance` is normally percentage points, but the source Sylph reference's `profile.estimate_read_counts: true` changes it to estimated reads. Retained Sylph `Contig_name` values match the complete FASTA record header exactly, never `Genome_file` or a whitespace-delimited token. A profile with no qualifying rows, or whose qualifying names all miss the FASTA, creates no future mapping task; a partial match fails rather than silently removing competitors.

Mapping maps the independently selected `read_sets` against each selected FASTA with minimap2 2.30 and samtools 1.22.1. Illumina uses `-x sr --frag=no --secondary=yes`; ONT uses its configured preset with independent records and secondary reporting. BAMs retain primary, secondary, supplementary, and unmapped records. Counts use one primary mapped alignment per enforced-unique mapper QNAME, so they report distinct total, mapped, and unmapped read records rather than alignment rows.

In each per-reference coverage row, `supporting_read_count` counts a read once for that reference; `exclusive_read_count` counts reads reported at only one reference, and `shared_read_count` counts reads reported at multiple references. `exclusive_breadth` and `exclusive_mean_depth` use only exclusive reads; `breadth` and `mean_depth` use all supporting reads.

The coverage comparison TSV retains source Sylph values alongside mapper measurements:

| Columns | Interpretation |
|---|---|
| `Taxonomic_abundance` | Sylph's coverage-normalized percentage estimate. |
| `Sequence_abundance`, `sylph_sequence_abundance_units` | Raw Sylph value and explicit `percent` or `estimated_reads`, determined by the **source** Sylph profile's `estimate_read_counts` setting. |
| `Adjusted_ANI` | Sylph's adjusted ANI in percentage points. |
| `Eff_cov`, `True_cov` | Sylph's estimated depth; the unavailable alternative is empty. `True_cov` can also occur with `estimate_unknown: true` and does not imply estimated read counts. |
| `profiling_read_set`, `mapped_read_set` | Read sets behind the Sylph estimates and mapper measurements respectively; they can differ. |

Sylph's estimated reads are not mapper-observed read counts, and estimated depth is not a read count. Sylph's `estimate_read_counts` mode is optimized for short reads; interpret comparisons cautiously for long reads and when the profiling and mapped read sets differ.

Alignoth plotting is disabled by default. To enable it for a mapping reference specification, add `pileups: {enabled: true}` to that entry. Set `enabled: false` or omit it to skip plotting. The optional `pileups.max_read_depth` defaults to 500 and limits displayed alignments only; neither setting changes BAMs, coverage, counts, or classified-read storage.

When `read_store.enabled` is true, mapping also publishes `<sample>__<read-set>__<reference>.classified-reads.parquet`. Classified reads associate original read payloads with named references by reported mapping placements. The table has one row per reported mapped BAM alignment, repeats the original mapped-read-set FASTQ header, sequence, quality, and plus-line content in original orientation, and includes the BAM flags, coordinates, CIGAR, MAPQ, available alignment score, mapper QNAME/read key, sample, mapped read set, mapping reference specification, BAM reference ID, and exact selected FASTA full header. It preserves ambiguous placements and makes no taxonomy or exclusive-assignment claim. It is sorted by exact `reference_name` then `read_key` with Zstandard compression and Parquet statistics so filtering a reference retrieves sequences and all placement evidence directly. This is produced only after BAM alignment; the pipeline creates no pre-mapping payload Parquet, does not map from Parquet, and does not export FASTQ at runtime.

`read_store.reference_allowlist` is an optional local or HTTPS text artifact with one exact full reference name per line. It is acquired and checksum-verified through the normal reference-source path. If any reported placement for a read names an allowlisted reference, every reported placement for that read remains in the Parquet; unknown names produce a valid empty typed table. It never changes reference selection, BAMs, coverage, counts, or denominators.

```yaml
mapping:
  references:
    - id: example-mapping
      # profile, fasta, select, read_sets, align, and pileups are configured here.
      read_store:
        enabled: true
        reference_allowlist:
          kind: local
          path: /refs/references-of-interest.txt
```

## Containers and Dependencies

The `docker` and `apptainer` profiles enable their respective runtimes while leaving executor and site policy to Nextflow configuration. No runtime profile is selected automatically. `--monoimage` assigns one image to every pipeline process; that image contains the scientific tools and Python runtime, while Nextflow remains on the host. The `:dev` image is the only currently published monoimage.

| Tool | Pipeline role |
|---|---|
| [nf-schema](https://nextflow-io.github.io/nf-schema/latest/) | Validates run parameters and the samplesheet before work begins. |
| [SRACha](https://github.com/rnabioco/sracha-rs) | Validates `SRR`, `ERR`, and `DRR` accessions and acquires their FASTQs. |
| [BQTools](https://github.com/ArcInstitute/bqtools) | Encodes each FASTQ as CBQ and concatenates multifile read sets for Deacon. |
| [Deacon](https://github.com/bede/deacon) | Builds minimizer indexes and produces filtered read sets. |
| [Sylph](https://github.com/bluenote-1577/sylph) | Builds databases, creates sample sketches, and profiles selected read sets. |
| [sylph-tax](https://github.com/bluenote-1577/sylph-tax) | Converts meaningful Sylph profiles into taxonomy summaries using explicit metadata. |
| [Krona](https://github.com/marbl/Krona) | Renders standalone canonical-rank taxonomy charts for configured Sylph references. |
| [Skope](https://github.com/bede/skope) | Builds query indexes and reports target-level containment for selected read sets. |

Skope is built from pinned upstream revision `c016a1fd2441ee16227f9031d636333be35bae74` to support `--all-kmers`, which is not included in release 0.5.0. Rebuild query indexes made with Skope 0.4.0: the upstream serialized header changed. Container runs also require a monoimage rebuilt with this pin; an older image does not gain flag support from pipeline configuration alone.

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
