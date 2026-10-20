from pathlib import Path

PROJECT_NAME = "zurich-uhi-lur"

NOTEBOOKS_DIR = Path("notebooks")
NOTEBOOKS_OUTPUT_DIR = NOTEBOOKS_DIR / "output"

DATA_DIR = Path("data")
DATA_RAW_DIR = DATA_DIR / "raw"
DATA_INTERIM_DIR = DATA_DIR / "interim"
DATA_PROCESSED_DIR = DATA_DIR / "processed"

FIGURES_DIR = Path("reports") / "figures"

EXTENT_FILEPATH = DATA_PROCESSED_DIR / "zurich-lcs-extent.gpkg"
LCS_BUFFER_DIST = 2000
BUFFER_DISTS_FILEPATH = DATA_RAW_DIR / "buffer-dists.yml"
LAND_WORKING_DIR = NOTEBOOKS_DIR / "land-working-dir"
DST_RES = 100

SITES_GDF_DICT = {
    "stations": DATA_PROCESSED_DIR / "stations.gpkg",
    "grid": DATA_PROCESSED_DIR / "regular-grid.gpkg",
}


rule all:
    input:
        DATA_PROCESSED_DIR / "ts-df.csv",
        DATA_PROCESSED_DIR / "stations.gpkg",
        DATA_PROCESSED_DIR / "buildings.gpkg",
        DATA_PROCESSED_DIR / "dem.tif",
        DATA_PROCESSED_DIR / "tree-canopy.tif",
        DATA_PROCESSED_DIR / "regular-grid.gpkg",
        expand(
            str(DATA_PROCESSED_DIR / "{sites}-features.csv"),
            sites=["stations", "grid"],
        ),
        expand(
            str(FIGURES_DIR / "lur-importance-{model}.pdf"),
            model=["MLR", "GAM", "RF"],
        ),
        expand(
            str(FIGURES_DIR / "lur-importance-single-{model}.pdf"),
            model=["MLR", "GAM", "RF"],
        ),
        FIGURES_DIR / "lur-importance-heatmap.pdf",
        FIGURES_DIR / "lur-importance-headline.pdf",
        FIGURES_DIR / "lur-scores-performance.pdf",
        FIGURES_DIR / "lur-scores-rsa.pdf",
        FIGURES_DIR / "lur-rsa.pdf",
        FIGURES_DIR / "lur-maps.png",
        FIGURES_DIR / "lur-pca.pdf",
        FIGURES_DIR / "lur-pca-loadings.pdf",
        FIGURES_DIR / "t-ts.pdf",
        FIGURES_DIR / "station-t-mean-maps.png",
        FIGURES_DIR / "station-t-t-mean-maps.png",


rule aws_data:
    input:
        nabel_stations=DATA_RAW_DIR / "nabel-stations.csv",
        nabel_temp=DATA_RAW_DIR / "nabel-temp.csv",
        notebook=NOTEBOOKS_DIR / "aws-data.ipynb",
    output:
        ts_df=DATA_INTERIM_DIR / "aws-ts-df.csv",
        stations_gdf=DATA_INTERIM_DIR / "aws-stations.gpkg",
        notebook=NOTEBOOKS_OUTPUT_DIR / "aws-data.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p nabel_stations_filepath {input.nabel_stations} "
        "-p nabel_temp_filepath {input.nabel_temp} "
        "-p dst_ts_df_filepath {output.ts_df} "
        "-p dst_stations_gdf_filepath {output.stations_gdf}"


rule lcs_data:
    input:
        aws_ts_df=rules.aws_data.output.ts_df,
        ugz_stations=DATA_RAW_DIR
        / "ugz_stadtklima_zuerich_messorte_messnetz_meteoblue.csv",
        ugz_ts_parquet=DATA_RAW_DIR
        / "ugz_stadtklima_zuerich_temperaturmessungen_messnetz_meteoblue_2019-aktuell.parquet",
        notebook=NOTEBOOKS_DIR / "lcs-data.ipynb",
    output:
        ts_df=DATA_INTERIM_DIR / "lcs-ts-df.csv",
        stations_gdf=DATA_INTERIM_DIR / "lcs-stations.gpkg",
        notebook=NOTEBOOKS_OUTPUT_DIR / "lcs-data.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p aws_ts_df_filepath {input.aws_ts_df} "
        "-p ugz_stations_filepath {input.ugz_stations} "
        "-p ugz_ts_parquet_filepath {input.ugz_ts_parquet} "
        "-p dst_ts_df_filepath {output.ts_df} "
        "-p dst_stations_gdf_filepath {output.stations_gdf}"


rule lcs_spatial_extent:
    input:
        lcs_stations_gdf=rules.lcs_data.output.stations_gdf,
        notebook=NOTEBOOKS_DIR / "lcs-spatial-extent.ipynb",
    output:
        extent=EXTENT_FILEPATH,
        notebook=NOTEBOOKS_OUTPUT_DIR / "lcs-spatial-extent.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p lcs_stations_gdf_filepath {input.lcs_stations_gdf} "
        "-p buffer_dist {LCS_BUFFER_DIST} "
        "-p dst_filepath {output.extent}"


rule merge_aws_lcs_data:
    input:
        aws_ts_df=rules.aws_data.output.ts_df,
        lcs_ts_df=rules.lcs_data.output.ts_df,
        aws_stations_gdf=rules.aws_data.output.stations_gdf,
        lcs_stations_gdf=rules.lcs_data.output.stations_gdf,
        notebook=NOTEBOOKS_DIR / "station-data.ipynb",
    output:
        ts_df=DATA_PROCESSED_DIR / "ts-df.csv",
        stations_gdf=DATA_PROCESSED_DIR / "stations.gpkg",
        notebook=NOTEBOOKS_OUTPUT_DIR / "station-data.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p aws_ts_df_filepath {input.aws_ts_df} "
        "-p lcs_ts_df_filepath {input.lcs_ts_df} "
        "-p aws_stations_gdf_filepath {input.aws_stations_gdf} "
        "-p lcs_stations_gdf_filepath {input.lcs_stations_gdf} "
        "-p dst_ts_df_filepath {output.ts_df} "
        "-p dst_stations_gdf_filepath {output.stations_gdf}"


rule eda:
    input:
        extent=rules.lcs_spatial_extent.output.extent,
        stations_gdf=rules.merge_aws_lcs_data.output.stations_gdf,
        ts_df=rules.merge_aws_lcs_data.output.ts_df,
        notebook=NOTEBOOKS_DIR / "eda.ipynb",
    output:
        t_ts=FIGURES_DIR / "t-ts.pdf",
        t_mean_maps=FIGURES_DIR / "station-t-mean-maps.png",
        t_minus_mean_maps=FIGURES_DIR / "station-t-t-mean-maps.png",
        notebook=NOTEBOOKS_OUTPUT_DIR / "eda.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p agglom_extent_filepath {input.extent} "
        "-p stations_gdf_filepath {input.stations_gdf} "
        "-p ts_df_filepath {input.ts_df} "
        "-p dst_t_ts_filepath {output.t_ts} "
        "-p dst_t_mean_maps_filepath {output.t_mean_maps} "
        "-p dst_t_minus_mean_maps_filepath {output.t_minus_mean_maps}"


rule land_data:
    input:
        extent=rules.lcs_spatial_extent.output.extent,
        notebook=NOTEBOOKS_DIR / "land-data.ipynb",
    output:
        buildings=DATA_PROCESSED_DIR / "buildings.gpkg",
        dem=DATA_PROCESSED_DIR / "dem.tif",
        tree_canopy=DATA_PROCESSED_DIR / "tree-canopy.tif",
        notebook=NOTEBOOKS_OUTPUT_DIR / "land-data.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p agglom_extent_filepath {input.extent} "
        "-p working_dir {LAND_WORKING_DIR} "
        "-p dst_buildings_gdf_filepath {output.buildings} "
        "-p dst_dem_filepath {output.dem} "
        "-p dst_tree_canopy_filepath {output.tree_canopy}"


rule regular_grid:
    input:
        extent=rules.lcs_spatial_extent.output.extent,
        notebook=NOTEBOOKS_DIR / "prediction-grid.ipynb",
    output:
        regular_grid=DATA_PROCESSED_DIR / "regular-grid.gpkg",
        notebook=NOTEBOOKS_OUTPUT_DIR / "prediction-grid.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p agglom_extent_filepath {input.extent} "
        "-p dst_res {DST_RES} "
        "-p dst_filepath {output.regular_grid}"


rule _compute_land_features:
    input:
        extent=rules.lcs_spatial_extent.output.extent,
        sites=lambda wc: SITES_GDF_DICT[wc.sites],
        buildings=rules.land_data.output.buildings,
        dem=rules.land_data.output.dem,
        tree_canopy=rules.land_data.output.tree_canopy,
        notebook=NOTEBOOKS_DIR / "land-features.ipynb",
    output:
        features=DATA_PROCESSED_DIR / "{sites}-features.csv",
        notebook=NOTEBOOKS_OUTPUT_DIR / "land-features-{sites}.ipynb",
    params:
        # the grid has ~16k sites against ~115 stations, and the default batch of 500
        # exhausts memory when the buffers are cut from the 558 MB DEM
        chunk_size=lambda wc: 100 if wc.sites == "grid" else 500,
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p agglom_extent_filepath {input.extent} "
        "-p chunk_size {params.chunk_size} "
        "-p sites_gdf_filepath {input.sites} "
        "-p buildings_gdf_filepath {input.buildings} "
        "-p tree_canopy_filepath {input.tree_canopy} "
        "-p dem_filepath {input.dem} "
        "-f {BUFFER_DISTS_FILEPATH} "
        "-p dst_filepath {output.features}"


rule compute_land_features:
    input:
        expand(
            str(DATA_PROCESSED_DIR / "{sites}-features.csv"),
            sites=["stations", "grid"],
        ),


rule land_use_regression:
    input:
        stations_gdf=rules.merge_aws_lcs_data.output.stations_gdf,
        station_features=DATA_PROCESSED_DIR / "stations-features.csv",
        ts_df=rules.merge_aws_lcs_data.output.ts_df,
        grid_gdf=rules.regular_grid.output.regular_grid,
        grid_features=DATA_PROCESSED_DIR / "grid-features.csv",
        notebook=NOTEBOOKS_DIR / "lur-model.ipynb",
    output:
        results=DATA_PROCESSED_DIR / "lur-results.csv",
        importance=DATA_PROCESSED_DIR / "lur-importance.csv",
        obs_pred=DATA_PROCESSED_DIR / "lur-obs-pred.csv",
        shap=DATA_PROCESSED_DIR / "lur-shap.csv",
        baseline_moran=DATA_PROCESSED_DIR / "baseline-moran.json",
        grid_pred=DATA_PROCESSED_DIR / "lur-grid-pred.nc",
        notebook=NOTEBOOKS_OUTPUT_DIR / "lur-model.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p stations_gdf_filepath {input.stations_gdf} "
        "-p station_features_filepath {input.station_features} "
        "-p ts_df_filepath {input.ts_df} "
        "-p grid_gdf_filepath {input.grid_gdf} "
        "-p grid_features_filepath {input.grid_features} "
        "-p dst_results_filepath {output.results} "
        "-p dst_importance_filepath {output.importance} "
        "-p dst_obs_pred_filepath {output.obs_pred} "
        "-p dst_shap_filepath {output.shap} "
        "-p dst_baseline_moran_filepath {output.baseline_moran} "
        "-p dst_grid_pred_filepath {output.grid_pred}"


rule lur_results:
    input:
        stations_gdf=rules.merge_aws_lcs_data.output.stations_gdf,
        station_features=DATA_PROCESSED_DIR / "stations-features.csv",
        ts_df=rules.merge_aws_lcs_data.output.ts_df,
        grid_gdf=rules.regular_grid.output.regular_grid,
        grid_features=DATA_PROCESSED_DIR / "grid-features.csv",
        results=rules.land_use_regression.output.results,
        importance=rules.land_use_regression.output.importance,
        obs_pred_data=rules.land_use_regression.output.obs_pred,
        shap=rules.land_use_regression.output.shap,
        baseline_moran=rules.land_use_regression.output.baseline_moran,
        grid_pred=rules.land_use_regression.output.grid_pred,
        notebook=NOTEBOOKS_DIR / "lur-results.ipynb",
    output:
        scores_performance_fig=FIGURES_DIR / "lur-scores-performance.pdf",
        scores_rsa_fig=FIGURES_DIR / "lur-scores-rsa.pdf",
        rsa_fig=FIGURES_DIR / "lur-rsa.pdf",
        importance_mlr=FIGURES_DIR / "lur-importance-MLR.pdf",
        importance_gam=FIGURES_DIR / "lur-importance-GAM.pdf",
        importance_rf=FIGURES_DIR / "lur-importance-RF.pdf",
        importance_single_mlr=FIGURES_DIR / "lur-importance-single-MLR.pdf",
        importance_single_gam=FIGURES_DIR / "lur-importance-single-GAM.pdf",
        importance_single_rf=FIGURES_DIR / "lur-importance-single-RF.pdf",
        maps_fig=FIGURES_DIR / "lur-maps.png",
        pca_fig=FIGURES_DIR / "lur-pca.pdf",
        pca_loadings_fig=FIGURES_DIR / "lur-pca-loadings.pdf",
        notebook=NOTEBOOKS_OUTPUT_DIR / "lur-results.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p stations_gdf_filepath {input.stations_gdf} "
        "-p station_features_filepath {input.station_features} "
        "-p ts_df_filepath {input.ts_df} "
        "-p grid_gdf_filepath {input.grid_gdf} "
        "-p grid_features_filepath {input.grid_features} "
        "-p dst_results_filepath {input.results} "
        "-p dst_importance_filepath {input.importance} "
        "-p obs_pred_data_filepath {input.obs_pred_data} "
        "-p dst_shap_filepath {input.shap} "
        "-p dst_baseline_moran_filepath {input.baseline_moran} "
        "-p grid_pred_filepath {input.grid_pred} "
        "-p dst_scores_performance_filepath {output.scores_performance_fig} "
        "-p dst_scores_rsa_filepath {output.scores_rsa_fig} "
        "-p dst_rsa_filepath {output.rsa_fig} "
        "-p dst_importance_fig_prefix {FIGURES_DIR}/lur-importance "
        "-p dst_maps_filepath {output.maps_fig} "
        "-p dst_pca_filepath {output.pca_fig} "
        "-p dst_pca_loadings_filepath {output.pca_loadings_fig} "


rule lur_importance_figures:
    input:
        importance=rules.land_use_regression.output.importance,
        shap=rules.land_use_regression.output.shap,
        notebook=NOTEBOOKS_DIR / "lur-importance-figures.ipynb",
    output:
        heatmap_fig=FIGURES_DIR / "lur-importance-heatmap.pdf",
        headline_fig=FIGURES_DIR / "lur-importance-headline.pdf",
        notebook=NOTEBOOKS_OUTPUT_DIR / "lur-importance-figures.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p dst_importance_filepath {input.importance} "
        "-p dst_shap_filepath {input.shap} "
        "-p dst_importance_heatmap_filepath {output.heatmap_fig} "
        "-p dst_importance_headline_filepath {output.headline_fig}"
