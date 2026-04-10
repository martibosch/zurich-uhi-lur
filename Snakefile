from pathlib import Path

PROJECT_NAME = "zurich-uhi-lur"

NOTEBOOKS_DIR = Path("notebooks")
NOTEBOOKS_OUTPUT_DIR = NOTEBOOKS_DIR / "output"

DATA_DIR = Path("data")
DATA_RAW_DIR = DATA_DIR / "raw"
DATA_INTERIM_DIR = DATA_DIR / "interim"
DATA_PROCESSED_DIR = DATA_DIR / "processed"

MODELS_DIR = Path("models")
FIGURES_DIR = Path("reports") / "figures"

EXTENT_FILEPATH = DATA_PROCESSED_DIR / "zurich-lcd-extent.gpkg"
LCD_BUFFER_DIST = 2000
BUFFER_DISTS_FILEPATH = DATA_RAW_DIR / "buffer-dists.yml"
LAND_WORKING_DIR = NOTEBOOKS_DIR / "land-working-dir"
DST_RES = 100

SITES_GDF_DICT = {
    "stations": DATA_PROCESSED_DIR / "stations.gpkg",
    "grid": DATA_PROCESSED_DIR / "regular-grid.gpkg",
}


METEOSWISS_STATIONS = ["KLO", "REH", "SMA"]


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
        MODELS_DIR / "pipeline-OLS.skops",
        MODELS_DIR / "pipeline-RF.skops",
        expand(
            str(FIGURES_DIR / "lur-importance-{model}.pdf"),
            model=["OLS", "EBM", "RF"],
        ),
        expand(
            str(FIGURES_DIR / "lur-importance-single-{model}.pdf"),
            model=["OLS", "EBM", "RF"],
        ),
        FIGURES_DIR / "lur-scores.pdf",
        FIGURES_DIR / "lur-rsa.pdf",
        FIGURES_DIR / "lur-maps.png",
        FIGURES_DIR / "lur-pca.pdf",
        FIGURES_DIR / "lur-pca-loadings.pdf",
        FIGURES_DIR / "lur-obs-pred.pdf",
        FIGURES_DIR / "t-ts.pdf",
        FIGURES_DIR / "station-t-mean-maps.png",
        FIGURES_DIR / "station-t-t-mean-maps.png",
        DATA_PROCESSED_DIR / "aws-day-clusters.json",
        expand(
            str(DATA_PROCESSED_DIR / "aws-day-clusters-{station_id}.json"),
            station_id=METEOSWISS_STATIONS,
        ),


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


rule lcd_data:
    input:
        aws_ts_df=rules.aws_data.output.ts_df,
        ugz_stations=DATA_RAW_DIR
        / "ugz_stadtklima_zuerich_messorte_messnetz_meteoblue.csv",
        ugz_ts_parquet=DATA_RAW_DIR
        / "ugz_stadtklima_zuerich_temperaturmessungen_messnetz_meteoblue_2019-aktuell.parquet",
        notebook=NOTEBOOKS_DIR / "lcd-data.ipynb",
    output:
        ts_df=DATA_INTERIM_DIR / "lcd-ts-df.csv",
        stations_gdf=DATA_INTERIM_DIR / "lcd-stations.gpkg",
        notebook=NOTEBOOKS_OUTPUT_DIR / "lcd-data.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p aws_ts_df_filepath {input.aws_ts_df} "
        "-p ugz_stations_filepath {input.ugz_stations} "
        "-p ugz_ts_parquet_filepath {input.ugz_ts_parquet} "
        "-p dst_ts_df_filepath {output.ts_df} "
        "-p dst_stations_gdf_filepath {output.stations_gdf}"


rule lcd_spatial_extent:
    input:
        lcd_stations_gdf=rules.lcd_data.output.stations_gdf,
        notebook=NOTEBOOKS_DIR / "lcd-spatial-extent.ipynb",
    output:
        extent=EXTENT_FILEPATH,
        notebook=NOTEBOOKS_OUTPUT_DIR / "lcd-spatial-extent.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p lcd_stations_gdf_filepath {input.lcd_stations_gdf} "
        "-p buffer_dist {LCD_BUFFER_DIST} "
        "-p dst_filepath {output.extent}"


rule merge_aws_lcd_data:
    input:
        aws_ts_df=rules.aws_data.output.ts_df,
        lcd_ts_df=rules.lcd_data.output.ts_df,
        aws_stations_gdf=rules.aws_data.output.stations_gdf,
        lcd_stations_gdf=rules.lcd_data.output.stations_gdf,
        notebook=NOTEBOOKS_DIR / "station-data.ipynb",
    output:
        ts_df=DATA_PROCESSED_DIR / "ts-df.csv",
        stations_gdf=DATA_PROCESSED_DIR / "stations.gpkg",
        notebook=NOTEBOOKS_OUTPUT_DIR / "station-data.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p aws_ts_df_filepath {input.aws_ts_df} "
        "-p lcd_ts_df_filepath {input.lcd_ts_df} "
        "-p aws_stations_gdf_filepath {input.aws_stations_gdf} "
        "-p lcd_stations_gdf_filepath {input.lcd_stations_gdf} "
        "-p dst_ts_df_filepath {output.ts_df} "
        "-p dst_stations_gdf_filepath {output.stations_gdf}"


rule eda:
    input:
        extent=rules.lcd_spatial_extent.output.extent,
        stations_gdf=rules.merge_aws_lcd_data.output.stations_gdf,
        ts_df=rules.merge_aws_lcd_data.output.ts_df,
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
        extent=rules.lcd_spatial_extent.output.extent,
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
        extent=rules.lcd_spatial_extent.output.extent,
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
        extent=rules.lcd_spatial_extent.output.extent,
        sites=lambda wc: SITES_GDF_DICT[wc.sites],
        buildings=rules.land_data.output.buildings,
        dem=rules.land_data.output.dem,
        tree_canopy=rules.land_data.output.tree_canopy,
        notebook=NOTEBOOKS_DIR / "land-features.ipynb",
    output:
        features=DATA_PROCESSED_DIR / "{sites}-features.csv",
        notebook=NOTEBOOKS_OUTPUT_DIR / "land-features-{sites}.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p agglom_extent_filepath {input.extent} "
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
        stations_gdf=rules.merge_aws_lcd_data.output.stations_gdf,
        station_features=DATA_PROCESSED_DIR / "stations-features.csv",
        ts_df=rules.merge_aws_lcd_data.output.ts_df,
        notebook=NOTEBOOKS_DIR / "lur-fit.ipynb",
    output:
        pipeline_ols=MODELS_DIR / "pipeline-OLS.skops",
        pipeline_rf=MODELS_DIR / "pipeline-RF.skops",
        results=DATA_PROCESSED_DIR / "lur-results.csv",
        importance=DATA_PROCESSED_DIR / "lur-importance.csv",
        obs_pred=DATA_PROCESSED_DIR / "lur-obs-pred.csv",
        baseline_moran=DATA_PROCESSED_DIR / "baseline-moran.json",
        notebook=NOTEBOOKS_OUTPUT_DIR / "lur-fit.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p stations_gdf_filepath {input.stations_gdf} "
        "-p station_features_filepath {input.station_features} "
        "-p ts_df_filepath {input.ts_df} "
        "-p models_dir {MODELS_DIR} "
        "-p dst_results_filepath {output.results} "
        "-p dst_importance_filepath {output.importance} "
        "-p dst_obs_pred_filepath {output.obs_pred} "
        "-p dst_baseline_moran_filepath {output.baseline_moran}"


rule lur_results:
    input:
        stations_gdf=rules.merge_aws_lcd_data.output.stations_gdf,
        station_features=DATA_PROCESSED_DIR / "stations-features.csv",
        ts_df=rules.merge_aws_lcd_data.output.ts_df,
        grid_gdf=rules.regular_grid.output.regular_grid,
        grid_features=DATA_PROCESSED_DIR / "grid-features.csv",
        results=rules.land_use_regression.output.results,
        importance=rules.land_use_regression.output.importance,
        obs_pred_data=rules.land_use_regression.output.obs_pred,
        baseline_moran=rules.land_use_regression.output.baseline_moran,
        notebook=NOTEBOOKS_DIR / "lur-results.ipynb",
    output:
        scores_fig=FIGURES_DIR / "lur-scores.pdf",
        rsa_fig=FIGURES_DIR / "lur-rsa.pdf",
        importance_ols=FIGURES_DIR / "lur-importance-OLS.pdf",
        importance_ebm=FIGURES_DIR / "lur-importance-EBM.pdf",
        importance_rf=FIGURES_DIR / "lur-importance-RF.pdf",
        importance_single_ols=FIGURES_DIR / "lur-importance-single-OLS.pdf",
        importance_single_ebm=FIGURES_DIR / "lur-importance-single-EBM.pdf",
        importance_single_rf=FIGURES_DIR / "lur-importance-single-RF.pdf",
        maps_fig=FIGURES_DIR / "lur-maps.png",
        pca_fig=FIGURES_DIR / "lur-pca.pdf",
        pca_loadings_fig=FIGURES_DIR / "lur-pca-loadings.pdf",
        obs_pred_fig=FIGURES_DIR / "lur-obs-pred.pdf",
        notebook=NOTEBOOKS_OUTPUT_DIR / "lur-results.ipynb",
    shell:
        "papermill {input.notebook} {output.notebook} "
        "-p stations_gdf_filepath {input.stations_gdf} "
        "-p station_features_filepath {input.station_features} "
        "-p ts_df_filepath {input.ts_df} "
        "-p grid_gdf_filepath {input.grid_gdf} "
        "-p grid_features_filepath {input.grid_features} "
        "-p models_dir {MODELS_DIR} "
        "-p dst_results_filepath {input.results} "
        "-p dst_importance_filepath {input.importance} "
        "-p obs_pred_data_filepath {input.obs_pred_data} "
        "-p dst_baseline_moran_filepath {input.baseline_moran} "
        "-p dst_scores_filepath {output.scores_fig} "
        "-p dst_rsa_filepath {output.rsa_fig} "
        "-p dst_importance_fig_prefix {FIGURES_DIR}/lur-importance "
        "-p dst_maps_filepath {output.maps_fig} "
        "-p dst_pca_filepath {output.pca_fig} "
        "-p dst_pca_loadings_filepath {output.pca_loadings_fig} "
        "-p dst_obs_pred_filepath {output.obs_pred_fig}"
