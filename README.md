[![GitHub license](https://img.shields.io/github/license/martibosch/zurich-uhi-lur.svg)](https://github.com/martibosch/zurich-uhi-lur/blob/main/LICENSE)

# Land use regression of urban heat in Zurich

Land use regression of Zurich heatwaves using automated weather stations (AWS) and
low-cost devices (LCD).

## Requirements

The only requirement is to [install pixi](https://pixi.sh/latest/installation), then you can follow the steps described in the "Instructions" section below

## Instructions

1. Create a git repository:

```bash
git init
```

2. Install the project environment:

```bash
pixi install
```

3. Activate pre-commit for the git repository:

```bash
pixi run pre-commit install
pixi run pre-commit install --hook-type commit-msg
```

4. Create the first commit:

```bash
git add .
git commit -m "feat: initial commit"
```

5. Enjoy! :rocket:

6. Run the Zurich pipeline:

```bash
pixi run snakemake -j1
```

The pipeline prepares AWS and UGZ LCD heatwave datasets, computes land features, and
finishes with the `land-use-regression` and `lur-postprocessing` notebooks.

_Optional_: if you are using GitHub, you can set up [pre-commit.ci](https://pre-commit.ci) as a continuous integration service for pre-commit.

## Acknowledgments

- Based on the [cookiecutter-data-snake :snake:](https://github.com/martibosch/cookiecutter-data-snake) template for reproducible data science.
