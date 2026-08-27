# `nrminor/silly-fast-bfx`

`silly-fast-bfx` is an nf-core-style Nextflow pipeline for rapidly comparing metagenomic screens. The current implementation validates hierarchical tool configuration and NVD-compatible samplesheets and accepts exact local FASTQ inputs. Scientific screening stages are being added as tested vertical slices.

Bootstrap the locked tools, agent reference repositories, Pixi development environment, and uv runtime environment with:

```bash
mise bootstrap
```

The reference repositories are cloned under `.agents/repos/` and remain outside version control and container build contexts. Once bootstrapped, Mise activates the locked Pixi `dev` environment when entering the repository.

Run the repository checks with:

```bash
mise run check
```

Inspect the pipeline entry point with:

```bash
nextflow run . --help
nextflow run . --version
```

Run with a schema-backed params YAML using:

```bash
nextflow run . -params-file params.yaml
```

Start from [`assets/params.example.yaml`](assets/params.example.yaml) and [`assets/samplesheet.example.csv`](assets/samplesheet.example.csv). Replace their illustrative `/data`, `/refs`, and HTTPS locations with real inputs.

Build and smoke-test the process monoimage with:

```bash
mise run container-build
mise run container-test
```
